{ lib, runCommand }:
# Select native filesystem trees; this does not relocate Nix-linked binaries.
{ package, paths ? [ "bin" "share" ], prefix ? "usr" }:
runCommand "${package.pname}-payload-${package.version}" { } ''
  mkdir -p "$out"/${lib.escapeShellArg prefix}
  ${lib.concatMapStringsSep "\n" (path: ''
    cp -R ${package}/${lib.escapeShellArg path} "$out"/${lib.escapeShellArg prefix}/
  '') paths}
''
