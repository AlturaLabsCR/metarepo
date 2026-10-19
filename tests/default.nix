{
  pkgs,
  metarepo,
  documentation,
}:
let
  api = metarepo.forPkgs pkgs;
  empty = metarepo.mkPackages {
    packagesDir = ./fixtures/empty;
    repository = throw "An empty project must not evaluate repository configuration";
    pkgsFor = _: throw "An empty project must not instantiate nixpkgs";
    documentation = _: throw "An empty project must not build documentation";
  };
  nativeOnly = metarepo.mkPackages {
    packagesDir = ./fixtures/packages;
    repository = throw "Nix-only packages must not evaluate repository configuration";
    documentation = _: throw "Nix-only packages must not build documentation";
  };
  repository = {
    id = "test";
    origin = "Test";
    label = "Test's repository";
    url = "https://example.invalid/packages";
    channels = {
      stable = {
        format = "apt";
        releases = [
          "example42"
          "another1"
        ];
      };
      next = {
        format = "dnf";
        releases = [ "example43" ];
      };
      suse = {
        format = "dnf";
        releases = [
          "opensuse-leap160"
          "opensuse-tumbleweed"
        ];
      };
      rolling = {
        format = "pacman";
        releases = [ "custom" ];
      };
    };
  };
  publications = [
    {
      channels = {
        stable = {
          architecture = "all";
          package = pkgs.emptyDirectory;
        };
        next = {
          architecture = "aarch64";
          package = pkgs.emptyDirectory;
        };
        suse = {
          architecture = "noarch";
          package = pkgs.emptyDirectory;
        };
        rolling = {
          architecture = "any";
          package = pkgs.emptyDirectory;
        };
      };
    }
    {
      channels.stable = {
        architecture = "all";
        package = pkgs.emptyDirectory;
      };
    }
  ];
  artifact =
    format: architecture:
    pkgs.emptyDirectory
    // {
      passthru.metarepo = { inherit format architecture; };
    };
  directPublications = [
    {
      channels = {
        stable = artifact "apt" "all";
        next = artifact "dnf" "aarch64";
        suse = artifact "dnf" "noarch";
        rolling = artifact "pacman" "any";
      };
    }
  ];
  public = api.mkPublic { inherit repository publications; };
  directPublic = api.mkPublic {
    inherit repository;
    publications = directPublications;
  };
  documentedPublic = api.mkPublic {
    repository = repository // {
      channels = { };
    };
    publications = [ ];
    documentation = pkgs.writeTextDir "index.html" "<h1>Test documentation</h1>";
  };
  documentedProject = metarepo.mkPackages {
    packagesDir = ./fixtures/project;
    inherit repository;
    pkgsFor = _: pkgs;
    documentation = pkgs: pkgs.writeTextDir "index.html" "<h1>Test documentation</h1>";
  };
  invalid =
    releases:
    builtins.tryEval
      (api.mkPublic {
        publications = publications;
        repository = repository // {
          channels = pkgs.lib.mapAttrs (
            name: channel: channel // { releases = releases.${name} or [ ]; }
          ) repository.channels;
        };
      }).drvPath;
in
assert import ./api.nix { inherit pkgs api repository; };
assert empty == { };
assert
  builtins.attrNames nativeOnly == [
    "aarch64-linux"
    "x86_64-linux"
  ];
assert builtins.attrNames nativeOnly.aarch64-linux == [ "arm-only" ];
assert builtins.attrNames nativeOnly.x86_64-linux == [ "x86-only" ];
assert nativeOnly.aarch64-linux.arm-only.system == "aarch64-linux";
assert nativeOnly.x86_64-linux.x86-only.system == "x86_64-linux";
assert
  !(invalid {
    stable = [ "duplicate" ];
    next = [ "duplicate" ];
  }).success;
assert !(invalid { stable = [ "bad|selector" ]; }).success;
assert public.installScript == directPublic.installScript;
assert
  !(builtins.tryEval
    (api.mkPublic {
      repository = repository // {
        channels.apt.format = "dnf";
      };
      publications = [ ];
    }).drvPath
  ).success;
assert
  !(builtins.tryEval
    (api.mkPublic {
      inherit repository;
      publications = [ { channels.stable = (builtins.head directPublications).channels.next; } ];
    }).drvPath
  ).success;
assert
  !(builtins.tryEval
    (api.mkPublic {
      inherit repository;
      publications = [ { channels.typo = [ ]; } ];
    }).drvPath
  ).success;
assert
  !(builtins.tryEval
    (api.mkPublic {
      repository = repository // {
        channels.doc.format = "apt";
      };
      publications = [ ];
      documentation = pkgs.emptyDirectory;
    }).drvPath
  ).success;
{
  documentation = pkgs.runCommand "documentation-tests" { } ''
    diff -ru ${documentation} ${../public/doc}
    touch "$out"
  '';
  public-documentation = pkgs.runCommand "public-documentation-tests" { } ''
    test -f ${documentedPublic}/doc/index.html
    ${documentedProject.${pkgs.stdenv.hostPlatform.system}.build-public}/bin/build-public
    cmp ${documentedPublic}/doc/index.html public/doc/index.html
    touch public/obsolete
    ${documentedProject.${pkgs.stdenv.hostPlatform.system}.build-public}/bin/build-public
    test ! -e public/obsolete
    cmp ${documentedPublic}/doc/index.html public/doc/index.html
    touch "$out"
  '';
  apt-multiversion =
    pkgs.runCommand "apt-multiversion-tests"
      {
        nativeBuildInputs = [
          pkgs.dpkg
          pkgs.apt
          pkgs.gzip
          pkgs.diffutils
          pkgs.gnupg
        ];
      }
      ''
        sh ${./apt-multiversion.sh} ${../lib/repository.sh}
        touch "$out"
      '';
  integrations = import ./integrations.nix { inherit pkgs; };
  fastfetch = import ./fastfetch.nix { inherit pkgs api; };
  native-packages = import ./native-packages.nix { inherit pkgs api; };
  services = import ./services.nix { inherit pkgs api; };
  installer = pkgs.runCommand "installer-tests" { } ''
        sh -n ${public.installScript}
        # Source only the definitions; never run package managers or alter /etc.
        sed '/^if \[ "$(id -u)"/,/^fi/d; /^release="$(_get_release)"/,$d' \
          ${public.installScript} > functions.sh
        cat >> functions.sh <<'SH'
        _install_apt() { printf 'apt:%s:%s\n' "$1" "$2"; }
        _install_dnf() { printf 'dnf:%s:%s\n' "$1" "$2"; }
        _install_pacman() { printf 'pacman:%s:%s\n' "$1" "$2"; }
        [ "$(_install_release example42)" = apt:stable:all ]
        [ "$(_install_release another1)" = apt:stable:all ]
        [ "$(_install_release example43)" = dnf:next:aarch64 ]
        [ "$(_install_release opensuse-leap160)" = dnf:suse:noarch ]
        [ "$(_install_release opensuse-tumbleweed)" = dnf:suse:noarch ]
        [ "$(_install_release custom)" = pacman:rolling:any ]
        [ "$(_install_release stable)" = apt:stable:all ]
        if (_install_release unknown) 2>/dev/null; then exit 1; fi
        _check_architecture 'amd64 all' amd64
        _check_architecture noarch aarch64
        _check_architecture any x86_64
        if (_check_architecture amd64 arm64) 2>/dev/null; then exit 1; fi
    SH
        sh functions.sh
        # Exercise detection and RPM setup against an isolated filesystem.
        sed 's|/etc/|./etc/|g; s|/usr/lib/os-release|./usr/lib/os-release|g; s|/usr/share/keyrings|./usr/share/keyrings|g' functions.sh \
          | sed '/^[[:space:]]*_install_apt() { printf/,$d' > isolated.sh
        mkdir -p etc
        cat >> isolated.sh <<'SH'
        printf 'ID=opensuse-tumbleweed\nVERSION_ID=20261016\n' > etc/os-release
        [ "$(_get_release)" = opensuse-tumbleweed ]
        printf 'ID=opensuse-leap\nVERSION_ID=16.0\n' > etc/os-release
        [ "$(_get_release)" = opensuse-leap160 ]
        printf 'ID=opensuse-leap\nVERSION_ID=99.0\n' > etc/os-release
        if (_get_release) 2>/dev/null; then exit 1; fi
        curl() { printf key > "$2"; }
        dpkg() { printf 'amd64\n'; }
        apt-get() { [ "$1" = update ]; }
        mkdir -p usr/share/keyrings etc/apt/sources.list.d
        _install_apt stable 'all amd64'
        grep -F 'https://example.invalid/packages/apt stable main' etc/apt/sources.list.d/test.list
        rpm() { [ "$1" = --import ] && [ -f "$2" ]; }
        zypper() { printf '%s\n' "$*" > zypper.log; }
        _install_release opensuse-tumbleweed
        grep -Fx 'baseurl=https://example.invalid/packages/suse/' etc/zypp/repos.d/test.repo
        grep -Fx '[test]' etc/zypp/repos.d/test.repo
        grep -Fx 'pkg_gpgcheck=1' etc/zypp/repos.d/test.repo
        grep -Fx -- '--non-interactive refresh test' zypper.log
        unset -f zypper
        _install_dnf next noarch
        grep -Fx '[test]' etc/yum.repos.d/test.repo
        grep -Fx 'baseurl=https://example.invalid/packages/next/' etc/yum.repos.d/test.repo

    SH
        sh isolated.sh
        touch "$out"
  '';
}
