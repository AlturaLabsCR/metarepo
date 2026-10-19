/**
  Publish an existing Windows MSI without rebuilding or modifying its bytes.
  Building the installer (for example with WiX on Windows) is the caller's job.

  # Inputs

  `installer`: Path to an already built MSI, typically from `fetchurl` with a hash.
  `name`, `version`: Catalog identifiers and filename components.
  `architecture`: Windows target architecture: `x86`, `x64` or `arm64`.
  Standard descriptive metadata is accepted for consistency with `mkPackage`.

  Return a directory containing the MSI and its JSON metadata with SHA-256,
  plus `passthru.metarepo = { format = "msi"; architecture; }`.
*/
{
  lib,
  runCommand,
  python3,
  writeText,
}:
{
  name,
  version,
  architecture,
  installer,
  description ? "",
  homepage ? "",
  maintainer ? "",
  license ? "",
  release ? "1",
  depends ? [ ],
  recommends ? [ ],
  conflicts ? [ ],
  provides ? [ ],
}:
let
  token =
    value: builtins.isString value && builtins.match "[a-zA-Z0-9][a-zA-Z0-9._+-]*" value != null;
  filename = "${name}-${version}-${release}-${architecture}.msi";
  metadata = writeText "msi-metadata.json" (
    builtins.toJSON {
      inherit
        name
        version
        architecture
        description
        homepage
        maintainer
        license
        release
        ;
      file = filename;
    }
  );
in
assert lib.assertMsg (
  token name && token version && token release
) "metarepo: MSI name, version and release must be safe filename components";
assert lib.assertMsg (builtins.elem architecture [
  "x86"
  "x64"
  "arm64"
]) "metarepo: MSI architecture must be x86, x64 or arm64";
assert lib.assertMsg (
  depends == [ ] && recommends == [ ] && conflicts == [ ] && provides == [ ]
) "metarepo: MSI dependencies and upgrade behavior belong in the existing installer";
runCommand "${name}-msi-${version}"
  {
    nativeBuildInputs = [ python3 ];
    passthru.metarepo = {
      format = "msi";
      inherit architecture;
    };
  }
  ''
    mkdir -p "$out"
    cp ${lib.escapeShellArg (toString installer)} "$out/${filename}"
    python3 ${./msi-metadata.py} ${metadata} "$out/${filename}"
  ''
