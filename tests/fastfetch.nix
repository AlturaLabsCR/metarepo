{ pkgs, api }:
let
  packages = map (path: pkgs.callPackage path { metarepo = api; }) [
    ../packages/fastfetch/package.nix
    ../packages/fastfetch-git/package.nix
  ];
  snapshots = pkgs.lib.concatMap (package: builtins.attrValues package.passthru.snapshots) packages;
in
pkgs.runCommand "fastfetch-snapshot-tests" { nativeBuildInputs = [ pkgs.binutils ]; } ''
  ${pkgs.lib.concatMapStringsSep "\n" (package: ''
    ${package}/bin/fastfetch --version
    readelf -l ${package}/bin/fastfetch > program-headers
    if grep -q INTERP program-headers; then
      echo "Fastfetch snapshot must be static" >&2
      exit 1
    fi
    readelf -d ${package}/bin/fastfetch > dynamic-section
    if grep -q NEEDED dynamic-section; then exit 1; fi
  '') snapshots}
  touch "$out"
''
