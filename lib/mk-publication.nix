/**
  Publish a Nix package, or all its snapshots, to configured repository channels.
  Infer native metadata from `pname`, `version` and `meta`, and infer architecture
  from the host platform. APT inference supports x86_64-linux and aarch64-linux.

  Options merge in this order: inferred metadata, common package options,
  snapshot `passthru.publication`, format options, channel overrides.
  The repository channel always determines the final format.

  Return `{ channels.<name> = [ artifact ... ]; }` for `mkPublic`.
  When `package.passthru.snapshots` exists, every snapshot is published.

  # Type

  ```
  mkPublication :: AttrSet -> AttrSet
  ```

  # Inputs

  `repository`
  : Repository configuration with a `channels` attribute set; see `mkPublic`.

  `package`
  : Nix derivation. Inferred metadata uses `pname`, `version`,
    `meta.description`, `meta.homepage` and `meta.license.spdxId`.
    Override missing or unsuitable metadata through common package options.

  `payload`
  : Native filesystem directory, or function from each snapshot package to
    its directory. Defaults to an empty directory. Use a function when the
    payload depends on a snapshot's contents.

  `channels`
  : Channel names to subscribe to; defaults to all configured channels.
    Unknown names are rejected. In mixed repositories, select channels explicitly
    so Linux payloads are not published to MSI channels.

  `independent`
  : Defaults to `false`. When true, use APT `all`, RPM `noarch` and Pacman `any`.

  `formats`
  : Package option overrides indexed by format; defaults to `{ }`.

  For MSI channels supply `formats.msi.installer` (a prebuilt MSI) and
  `formats.msi.architecture` (`x86`, `x64` or `arm64`); no Windows architecture
  is inferred from the Linux build host. The payload must remain empty.

  `overrides`
  : Package option overrides indexed by channel; defaults to `{ }`.

  Additional attributes are common `mkPackage` options. Supply `maintainer`,
  which cannot be inferred from the Nix package.

  # Examples

  ```nix
  metarepo.mkPublication {
    inherit repository package;
    payload = package: metarepo.mkPayload { inherit package; };
    maintainer = "Example Authors <hello@example.org>";
    formats.apt.depends = [ "libc6" ];
    formats.dnf.depends = [ "glibc" ];
    formats.pacman.depends = [ "glibc" ];
  }
  ```
*/
{
  lib,
  stdenv,
  emptyDirectory,
  mkPackage,
}:
{
  repository,
  package,
  payload ? emptyDirectory,
  channels ? builtins.attrNames repository.channels,
  independent ? false,
  formats ? { },
  overrides ? { },
  ...
}@args:
let
  architectures =
    if independent then
      {
        apt = "all";
        dnf = "noarch";
        pacman = "any";
        msi = throw "metarepo: specify the MSI target architecture in formats.msi.architecture";
      }
    else
      {
        apt =
          {
            x86_64-linux = "amd64";
            aarch64-linux = "arm64";
          }
          .${stdenv.hostPlatform.system};
        dnf = stdenv.hostPlatform.uname.processor;
        pacman = stdenv.hostPlatform.uname.processor;
        msi = throw "metarepo: specify the MSI target architecture in formats.msi.architecture";
      };
  common = builtins.removeAttrs args [
    "repository"
    "package"
    "payload"
    "channels"
    "independent"
    "formats"
    "overrides"
  ];
  publish =
    pkg: channel:
    let
      format = repository.channels.${channel}.format;
      defaults = {
        name = pkg.pname;
        inherit (pkg) version;
        inherit (pkg.meta) description homepage;
        license = pkg.meta.license.spdxId;
        architecture = architectures.${format};
        payload = if builtins.isFunction payload then payload pkg else payload;
      };
    in
    mkPackage (
      defaults
      // common
      // (pkg.passthru.publication or { })
      // (formats.${format} or { })
      // (overrides.${channel} or { })
      // {
        inherit format;
      }
    );
  packages = builtins.attrValues (package.passthru.snapshots or { current = package; });
in
assert lib.assertMsg (lib.all (
  channel: builtins.hasAttr channel repository.channels
) channels) "metarepo: publication channels must exist in repository.channels";
{
  channels = lib.genAttrs channels (channel: map (pkg: publish pkg channel) packages);
}
