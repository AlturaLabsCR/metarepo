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
  };
  publications = [
    {
      channels = {
        stable = {
          releases = [ "example42" ];
          format = "apt";
          architecture = "all";
          package = pkgs.emptyDirectory;
        };
        next = {
          releases = [ "example43" ];
          format = "dnf";
          architecture = "aarch64";
          package = pkgs.emptyDirectory;
        };
        rolling = {
          releases = [ "custom" ];
          format = "pacman";
          architecture = "any";
          package = pkgs.emptyDirectory;
        };
      };
    }
    {
      channels.stable = {
        format = "apt";
        architecture = "all";
        package = pkgs.emptyDirectory;
        releases = [
          "example42"
          "another1"
        ];
      };
    }
  ];
  public = api.mkPublic { inherit repository publications; };
  invalid =
    releases:
    builtins.tryEval
      (api.mkPublic {
        inherit repository;
        publications = map (publication: {
          channels = pkgs.lib.mapAttrs (
            name: channel: channel // { releases = releases.${name} or [ ]; }
          ) publication.channels;
        }) publications;
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
