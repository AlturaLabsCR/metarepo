/**
  Copy selected package trees into a native filesystem layout.
  This copies files without relocating binaries, wrappers or Nix store references.
  Use a portable build or assemble a custom payload when relocation is needed.

  # Type

  ```
  mkPayload :: AttrSet -> Derivation
  ```

  # Inputs

  `package`
  : Derivation with `pname` and `version`, whose selected trees will be copied.

  `paths`
  : Paths relative to the package output; defaults to `[ "bin" "share" ]`.
    Each tree is copied by basename; paths must exist.

  `prefix`
  : Destination prefix inside the payload; defaults to `"usr"`.

  # Examples

  ```nix
  metarepo.mkPayload { inherit package; paths = [ "bin" ]; }
  # Result: $out/usr/bin contains the package's bin tree.
  ```
*/
{ lib, runCommand }:
{
  package,
  paths ? [
    "bin"
    "share"
  ],
  prefix ? "usr",
}:
runCommand "${package.pname}-payload-${package.version}" { } ''
  mkdir -p "$out"/${lib.escapeShellArg prefix}
  ${lib.concatMapStringsSep "\n" (path: ''
    cp -R ${package}/${lib.escapeShellArg path} "$out"/${lib.escapeShellArg prefix}/
  '') paths}
''
