{ pkgs, metarepo }:
let
  api = metarepo.forPkgs pkgs;
  empty = metarepo.mkPackages {
    packagesDir = ./fixtures/empty;
    repository = throw "An empty project must not evaluate repository configuration";
    pkgsFor = _: throw "An empty project must not instantiate nixpkgs";
  };
  nativeOnly = metarepo.mkPackages {
    packagesDir = ./fixtures/packages;
    repository = throw "Nix-only packages must not evaluate repository configuration";
  };
  repository = {
    id = "test";
    origin = "Test";
    label = "Test's repository";
    url = "https://example.invalid/packages";
    channels = {
      stable = { format = "apt"; releases = [ "example42" "another1" ]; };
      next = { format = "dnf"; releases = [ "example43" ]; };
      rolling = { format = "pacman"; releases = [ "custom" ]; };
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
  directPublications = [
    {
      channels = {
        stable = pkgs.emptyDirectory // { passthru = { metarepo = { format = "apt"; architecture = "all"; }; }; };
        next = pkgs.emptyDirectory // { passthru = { metarepo = { format = "dnf"; architecture = "aarch64"; }; }; };
        rolling = pkgs.emptyDirectory // { passthru = { metarepo = { format = "pacman"; architecture = "any"; }; }; };
      };
    }
  ];
  public = api.mkPublic { inherit repository publications; };
  directPublic = api.mkPublic { repository; publications = directPublications; };
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
assert directPublic.repositories.apt.architecturesBySuite.stable == [ "all" ];
assert directPublic.repositories.dnf == [ "next" ];
assert directPublic.repositories.pacman == [ "rolling" ];
{
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
        [ "$(_install_release custom)" = pacman:rolling:any ]
        [ "$(_install_release stable)" = apt:stable:all ]
        if (_install_release unknown) 2>/dev/null; then exit 1; fi
        _check_architecture 'amd64 all' amd64
        _check_architecture noarch aarch64
        _check_architecture any x86_64
        if (_check_architecture amd64 arm64) 2>/dev/null; then exit 1; fi
    SH
        sh functions.sh
        touch "$out"
  '';
}
