/**
  Publish a Nix package, or all its snapshots, to configured repository channels.
  Infer native metadata from `pname`, `version` and `meta`, and infer architecture
  from the host platform. APT inference supports x86_64-linux and aarch64-linux.

  Options merge in this order: inferred metadata, common package options,
  snapshot `passthru.publication`, `snapshotOptions`, format options, channel overrides.
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
    Unknown names are rejected. Channels with `inherits` reuse their parent artifact
    and are included when a parent is selected. A selected alias with an explicit
    channel override builds its own artifact. Parent formats must match, and
    unknown parents and inheritance cycles are rejected.
    In mixed repositories, select channels explicitly
    so Linux payloads are not published to MSI channels.

  `independent`
  : Defaults to `false`. When true, use APT `all`, RPM `noarch` and Pacman `any`.

  `formats`
  : Package option overrides indexed by format, or a function from the snapshot
    package to that attribute set; defaults to `{ }`.

  For MSI channels supply `formats.msi.installer` (a prebuilt MSI) and
  `formats.msi.architecture` (`x86`, `x64` or `arm64`); no Windows architecture
  is inferred from the Linux build host. The payload must remain empty.

  `overrides`
  : Package option overrides indexed by channel, or a function from the snapshot
    package to that attribute set; defaults to `{ }`.

  `snapshotOptions`
  : Function from each built snapshot package to publication options, default
    `_: { }`. Can select `channels`, `payload`, `independent`, `formats`,
    `overrides` and common package metadata per snapshot. The snapshot
    `passthru.publication` also accepts those structured options.
    Snapshot sources and package derivations are not modified.

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
  snapshotOptions ? (_: { }),
  ...
}@args:
let
  controls = [
    "repository"
    "package"
    "payload"
    "channels"
    "independent"
    "formats"
    "overrides"
    "snapshotOptions"
  ];
  optionsFor =
    pkg:
    (builtins.removeAttrs args [
      "repository"
      "package"
      "snapshotOptions"
    ])
    // {
      inherit
        payload
        channels
        independent
        formats
        overrides
        ;
    }
    // (pkg.passthru.publication or { })
    // snapshotOptions pkg;
  resolve = pkg: value: if builtins.isFunction value then value pkg else value;
  ancestors =
    name: visited:
    assert lib.assertMsg (
      !(builtins.elem name visited)
    ) "metarepo: cyclic channel inheritance at '${name}'";
    let
      channel = repository.channels.${name};
      parent = channel.inherits or null;
    in
    if parent == null then
      [ ]
    else
      assert lib.assertMsg (builtins.hasAttr parent repository.channels)
        "metarepo: channel '${name}' inherits unknown channel '${parent}'";
      assert lib.assertMsg (
        channel.format == repository.channels.${parent}.format
      ) "metarepo: inherited channels must use the same format";
      [ parent ] ++ ancestors parent (visited ++ [ name ]);
  channelNames = builtins.attrNames repository.channels;
  publishSnapshot =
    pkg:
    let
      options = optionsFor pkg;
      selected = options.channels;
      formatOptions = resolve pkg options.formats;
      channelOptions = resolve pkg options.overrides;
      architectures =
        if options.independent then
          {
            apt = "all";
            dnf = "noarch";
            pacman = "any";
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
          };
      build =
        channel:
        let
          format = repository.channels.${channel}.format;
        in
        mkPackage (
          {
            name = pkg.pname;
            inherit (pkg) version;
            inherit (pkg.meta) description homepage;
            license = pkg.meta.license.spdxId;
            architecture =
              architectures.${format}
                or (throw "metarepo: specify the MSI target architecture in formats.msi.architecture");
            payload = resolve pkg options.payload;
          }
          // builtins.removeAttrs options controls
          // (formatOptions.${format} or { })
          // (channelOptions.${channel} or { })
          // {
            inherit format;
          }
        );
      artifacts = lib.genAttrs channelNames (
        channel:
        let
          parent = repository.channels.${channel}.inherits or null;
        in
        if
          parent != null && !(builtins.elem channel selected && builtins.hasAttr channel channelOptions)
        then
          artifacts.${parent}
        else
          build channel
      );
      active = lib.filter (
        channel:
        builtins.elem channel selected
        || lib.any (parent: builtins.elem parent selected) (ancestors channel [ ])
      ) channelNames;
    in
    assert lib.assertMsg (lib.all (
      channel: builtins.hasAttr channel repository.channels
    ) selected) "metarepo: publication channels must exist in repository.channels";
    lib.genAttrs active (channel: [ artifacts.${channel} ]);
  packages = builtins.attrValues (package.passthru.snapshots or { current = package; });
  publications = map publishSnapshot packages;
  activeChannels = lib.unique (lib.concatMap builtins.attrNames publications);
in
# Validate aliases even when a particular snapshot does not subscribe to them.
assert builtins.deepSeq (map (channel: ancestors channel [ ]) channelNames) true;
{
  channels = lib.genAttrs activeChannels (
    channel: lib.concatMap (publication: publication.${channel} or [ ]) publications
  );
}
