/**
  Build a Windows x64 MSI from an already prepared Windows filesystem tree.
  Compilers, runtimes and application-specific configuration belong to callers.

  # Inputs

  `name`, `version`, `payload`: Product identity and Windows files to package.
  `manufacturer`: Vendor directory and MSI manufacturer, default `Metarepo`.
  `family`: Upgrade identity and installation directory, default `name`.
    Products sharing a family replace one another, including equal MSI versions.
  `launcher`: Optional relative file path receiving a Start Menu shortcut.
  `registry`: Optional records with `key`, `value`, optional `name`, `root`
    (default `HKLM`) and `type` (default `string`). MSI directory properties such
    as `[INSTALLDIR]` can be used in values. No custom actions are executed.

  The result is an unsigned MSI file built on Linux with wixl. Installation is
  per-machine and requires Windows administrator permissions. Windows execution
  and MSI signing are separate from construction. Use the result as `installer`
  in `mkMsi` or `mkPackage { format = "msi"; ...; }` for catalog publication.
*/
{
  lib,
  runCommand,
  writeText,
  python3,
  msitools,
}:
{
  name,
  version,
  payload,
  manufacturer ? "Metarepo",
  family ? name,
  launcher ? "",
  registry ? [ ],
}:
let
  options = writeText "msi-options.json" (
    builtins.toJSON {
      inherit
        name
        version
        manufacturer
        family
        launcher
        registry
        ;
    }
  );
in
assert lib.assertMsg (
  builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+.*" version != null
) "metarepo: MSI installer version must begin with three numeric components";
assert lib.assertMsg (lib.all (value: builtins.match "[a-zA-Z0-9][a-zA-Z0-9 ._+-]*" value != null) [
  name
  family
  manufacturer
]) "metarepo: MSI names must be safe Windows directory names";
runCommand "${name}-installer-${version}.msi"
  {
    nativeBuildInputs = [
      python3
      msitools
    ];
  }
  ''
    python3 ${./msi-build.py} ${options} ${lib.escapeShellArg (toString payload)}
    wixl -a x64 -o "$out" installer.wxs
  ''
