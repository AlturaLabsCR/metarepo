/**
  Internal repository builder used by `mkPublic`.
  Generate APT indexes, RPM metadata and Pacman databases from staged artifacts.

  # Type

  ```
  mkRepository :: AttrSet -> Derivation
  ```

  # Inputs

  `packages`
  : Directory containing per-channel artifacts and an `install.sh`.

  `repositories`
  : APT configuration (`suites`, fallback `architectures`, optional
    `architecturesBySuite`), and lists of `dnf` and `pacman` channel names.

  `repository`
  : Repository identity containing `id`, `origin` and `label`.

  The result is unsigned. Its `builder` executable stages a replacement of
  `public/` and uses `GPG_KEY_ID` for signing, including values loaded from `.env`.

  # Examples

  ```nix
  public = pkgs.callPackage ./lib/mk-repository.nix { } {
    inherit packages repositories repository;
  };
  ```
*/
{
  lib,
  runCommand,
  writeScriptBin,
  dash,
  apt,
  dpkg,
  pacman,
  rpm,
  createrepo_c,
  gnupg,
  coreutils,
  gzip,
}:
{
  packages,
  repositories,
  repository,
}:
let
  runtimeInputs = [
    apt
    dpkg
    pacman
    rpm
    createrepo_c
    gnupg
    coreutils
    gzip
  ];
  generate = writeScriptBin "build-repository" ''
    #!${dash}/bin/dash
    set -eu
    export PATH=${lib.makeBinPath runtimeInputs}:$PATH
    export PACKAGE_DIR="${packages}"
    export APT_SUITES=${lib.escapeShellArg (lib.concatStringsSep " " repositories.apt.suites)}
    export DNF_REPOSITORIES=${lib.escapeShellArg (lib.concatStringsSep " " repositories.dnf)}
    export PACMAN_REPOSITORIES=${lib.escapeShellArg (lib.concatStringsSep " " repositories.pacman)}
    export REPOSITORY_ID=${lib.escapeShellArg repository.id}
    export REPOSITORY_ORIGIN=${lib.escapeShellArg repository.origin}
    export REPOSITORY_LABEL=${lib.escapeShellArg repository.label}
    apt_architectures() {
      case "$1" in
        ${lib.concatMapStringsSep "\n" (
          suite:
          "${lib.escapeShellArg suite}) printf '%s\\n' ${
            lib.escapeShellArg (
              lib.concatStringsSep " " (
                repositories.apt.architecturesBySuite.${suite} or repositories.apt.architectures
              )
            )
          } ;;"
        ) repositories.apt.suites}
        *) return 1 ;;
      esac
    }
    ${builtins.readFile ./repository.sh}
  '';
  builder = writeScriptBin "build-public" ''
    #!${dash}/bin/dash
    set -eu
    export PATH=${
      lib.makeBinPath [
        generate
        coreutils
      ]
    }:$PATH
    attempt=0
    staging=
    while [ "$attempt" -lt 10 ]; do
      candidate=".public.$$.$attempt"
      if (umask 077 && mkdir "$candidate") 2>/dev/null; then
        staging=$candidate
        break
      fi
      attempt=$((attempt + 1))
    done
    if [ -z "$staging" ]; then
      echo "could not create a staging directory" >&2
      exit 1
    fi
    trap 'rm -rf "$staging"' 0
    build-repository "$staging/repository"
    if [ -e public ] || [ -L public ]; then
      mv public "$staging/previous"
    fi
    mv "$staging/repository" public
  '';
in
runCommand "public" { passthru = { inherit builder; }; } ''
  GPG_KEY_ID= ${generate}/bin/build-repository "$out"
''
