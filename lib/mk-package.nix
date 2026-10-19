/**
  Build an APT, DNF or Pacman artifact, or publish an existing Windows MSI.
  Declarative certificate and systemd files extend the payload, dependencies
  and hooks before dispatching to the format builder. Hooks run on the target
  machine, never during the Nix build.

  Return a derivation containing the native package file and
  `passthru.metarepo = { format; architecture; }`.

  # Type

  ```
  mkPackage :: AttrSet -> Derivation
  ```

  # Inputs

  `format`
  : One of `"apt"`, `"dnf"`, `"pacman"` or `"msi"`. MSI requires `installer`
    (a prebuilt file) and architecture `x86`, `x64` or `arm64`. Linux payloads,
    integrations, hooks and dependency options are rejected for MSI.

  `name`, `version`, `architecture`
  : Native package name, upstream version and format-specific architecture.

  `description`, `homepage`, `maintainer`, `license`
  : Required metadata strings. `license` is an SPDX identifier; APT accepts
    it for API consistency but does not write it to the control file.

  `payload`
  : Directory laid out as the target filesystem root. Defaults to an empty
    directory, useful for packages containing only declarative resources.

  `depends`, `recommends`, `conflicts`, `provides`
  : Lists of strings in the package manager's syntax; default to `[ ]`.
    Pacman uses `optdepends` for `recommends`.

  `release`
  : Native package revision string; defaults to `"1"`.

  `certificates`
  : Attribute set from plain `.crt` basenames to PEM source files; defaults
    to `{ }`. Files are prefixed with the package name and trust is refreshed.

  `systemd`
  : Optional `units`, `sysusers` and `tmpfiles` file maps; defaults to `{ }`.
    Sysusers and tmpfiles basenames must end in `.conf`. Installation creates
    users, applies tmpfiles and reloads units as needed. Unit values may also be
    records with `source` and boolean `enable`, `start`, `restartOnUpgrade` and
    `stopOnRemove` options. The first three default to false. `stopOnRemove`
    defaults to true when any of them is true, otherwise false. Enable/start
    requests run only on installation; upgrades restart only active units.
    Removal stops managed units before deleting files and disables units enabled
    by the package. APT honors policy-rc.d and adds init-system-helpers.
    Users and service data are preserved. See the library guide for examples.

  `hooks`
  : Optional shell strings `postInstall`, `preRemove` and `postRemove`; defaults
    to `{ }`. Custom actions run after inferred actions and should be idempotent.
    `postInstall` runs on installation and upgrades; removal hooks run only on
    actual removal (APT also invokes `postRemove` on purge). `METAREPO_ACTION`
    identifies the event as install, upgrade, remove or purge.

  `refreshCertificates`
  : Also refresh trust for certificates in a custom payload; defaults to `false`.

  # Examples

  ```nix
  metarepo.mkPackage {
    format = "apt";
    name = "example-ca";
    version = "1.0";
    architecture = "all";
    description = "Example trust anchor";
    homepage = "https://example.org";
    maintainer = "Example Authors <hello@example.org>";
    license = "MIT";
    certificates."example.crt" = ./example.crt;
  }
  ```
*/
{
  lib,
  callPackage,
  emptyDirectory,
  mkApt,
  mkDnf,
  mkPacman,
  mkMsi,
}:
{
  format,
  payload ? emptyDirectory,
  certificates ? { },
  systemd ? { },
  hooks ? { },
  refreshCertificates ? false,
  ...
}@args:
let
  builders = {
    apt = mkApt;
    dnf = mkDnf;
    pacman = mkPacman;
    msi = mkMsi;
  };
  integration = callPackage ./package-integrations.nix { } {
    inherit
      format
      payload
      certificates
      systemd
      refreshCertificates
      hooks
      ;
    inherit (args) name;
  };
in
assert lib.assertMsg (builtins.hasAttr format builders)
  "metarepo: unsupported package format '${format}'";
if format == "msi" then
  assert lib.assertMsg (
    payload == emptyDirectory
    && certificates == { }
    && systemd == { }
    && hooks == { }
    && !refreshCertificates
  ) "metarepo: MSI publication accepts an existing installer, not Linux payloads or integrations";
  mkMsi (
    builtins.removeAttrs args [
      "format"
      "payload"
      "certificates"
      "systemd"
      "hooks"
      "refreshCertificates"
    ]
  )
else
  builtins.seq integration.hooks (
    builders.${format} (
      builtins.removeAttrs args [
        "format"
        "payload"
        "certificates"
        "systemd"
        "hooks"
        "refreshCertificates"
      ]
      // {
        inherit (integration) payload hooks;
        depends = lib.unique ((args.depends or [ ]) ++ integration.depends);
      }
    )
  )
