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
    export APT_SUITES="${builtins.concatStringsSep " " repositories.apt.suites}"
    export APT_ARCHITECTURES="${builtins.concatStringsSep " " repositories.apt.architectures}"
    export DNF_REPOSITORIES="${builtins.concatStringsSep " " repositories.dnf}"
    export PACMAN_REPOSITORIES="${builtins.concatStringsSep " " repositories.pacman}"
    export REPOSITORY_ID="${repository.id}"
    export REPOSITORY_ORIGIN="${repository.origin}"
    export REPOSITORY_LABEL="${repository.label}"
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
