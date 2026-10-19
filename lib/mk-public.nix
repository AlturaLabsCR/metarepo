/**
  Assemble native artifacts into an unsigned repository and generate its installer.
  Configured channels without artifacts are omitted. Unknown publication channels,
  mismatched formats, unsafe tokens and ambiguous release selectors are rejected.

  Return a repository derivation. Its `builder` is an executable that replaces
  `public/` in the working directory and optionally signs using `GPG_KEY_ID`
  from the environment or `.env`. Its `installScript` is the generated installer.

  # Type

  ```
  mkPublic :: AttrSet -> Derivation
  ```

  # Inputs

  `publications`
  : List of `mkPublication` results. Each `channels.<name>` accepts one
    artifact or a list. Artifacts need `passthru.metarepo.format` and
    `architecture`, or a record `{ package; architecture; format; }`.
    Record metadata can fall back to the package's metadata; record `format`
    ultimately defaults to the configured channel format.

  `repository`
  : Attribute set with `id`, `origin`, `label`, `url` and `channels`.
    Each channel specifies `format` (`apt`, `dnf` or `pacman`) and optional
    `releases` (installer aliases, default `[ ]`). The installer also accepts
    channel names. IDs, published channels, release aliases and architectures
    must match `[a-zA-Z0-9][a-zA-Z0-9_+-]*`.

  `documentation`
  : Optional directory copied under `public/doc`; defaults to `null`.
    When supplied, the channel name `doc` is reserved.

  APT suites share `apt/pool` with indexes under `apt/dists/<suite>`.
  Identical artifacts are stored once by SHA-256; `apt` is a reserved channel
  name. Existing APT clients must rerun the installer to use the `/apt` URL.

  # Examples

  ```nix
  public = metarepo.mkPublic {
    publications = [ publication ];
    repository = {
      id = "example";
      origin = "Example";
      label = "Example packages";
      url = "https://packages.example.org";
      channels.stable = { format = "apt"; releases = [ "ubuntu2404" ]; };
    };
  };
  # public.builder generates public/; public itself is an unsigned Nix output.
  ```
*/
{
  lib,
  callPackage,
  runCommand,
  writeText,
}:
{
  publications,
  repository,
  documentation ? null,
}:
let
  normalizeEntry =
    channelName: entry:
    if builtins.isAttrs entry && entry ? package then
      entry
    else if builtins.isAttrs entry && entry ? passthru && entry.passthru ? metarepo then
      {
        package = entry;
        format = entry.passthru.metarepo.format;
        architecture = entry.passthru.metarepo.architecture;
      }
    else
      throw "metarepo: publication for channel '${channelName}' must be a package derivation with passthru.metarepo format and architecture, or a record with package";
  configuredChannelNames = builtins.attrNames repository.channels;
  unknownChannels = lib.subtractLists configuredChannelNames (
    lib.unique (lib.concatMap (publication: builtins.attrNames publication.channels) publications)
  );
  channel =
    name:
    let
      entries = lib.concatMap (
        publication: map (normalizeEntry name) (lib.toList publication.channels.${name})
      ) (lib.filter (publication: builtins.hasAttr name publication.channels) publications);
      format = repository.channels.${name}.format;
    in
    assert lib.assertMsg (builtins.elem format [
      "apt"
      "dnf"
      "pacman"
    ]) "metarepo: unsupported format '${format}' for channel '${name}'";
    {
      inherit format;
      releases = repository.channels.${name}.releases or [ ];
      packages = map (entry: entry.package) entries;
      entryFormats = map (
        entry: entry.format or (entry.package.passthru.metarepo.format or format)
      ) entries;
      architectures = map (
        entry: entry.architecture or entry.package.passthru.metarepo.architecture
      ) entries;
    };
  configuredChannels = lib.genAttrs configuredChannelNames channel;
  # A configured channel is published only when at least one package subscribes.
  channelNames = lib.filter (name: configuredChannels.${name}.packages != [ ]) configuredChannelNames;
  channels = lib.genAttrs channelNames (name: configuredChannels.${name});
  repositoriesOf = format: lib.filter (name: channels.${name}.format == format) channelNames;
  aptSuites = repositoriesOf "apt";
  repositoryArchitectures =
    names: lib.unique (lib.concatMap (name: channels.${name}.architectures) names);
  aptArchitectures = repositoryArchitectures aptSuites;
  # Only evaluated publications contribute channels and installer aliases.
  selectors = name: lib.unique ([ name ] ++ channels.${name}.releases);
  supportedReleases = lib.concatMap selectors channelNames;
  validToken =
    token: builtins.isString token && builtins.match "[a-zA-Z0-9][a-zA-Z0-9_+-]*" token != null;
  installCases = lib.concatMapStringsSep "\n" (
    name:
    let
      entry = channels.${name};
      arguments = lib.concatMapStringsSep " " lib.escapeShellArg [
        name
        (lib.concatStringsSep " " (lib.unique entry.architectures))
      ];
    in
    "    ${lib.concatStringsSep "|" (selectors name)}) _install_${entry.format} ${arguments} ;;"
  ) channelNames;
  installScript = writeText "install.sh" (
    lib.replaceStrings
      [ "@REPO_ROOT@" "@REPO_ID@" "@REPO_LABEL@" "@SUPPORTED@" "@INSTALL_CASES@" ]
      [
        (lib.escapeShellArg repository.url)
        (lib.escapeShellArg repository.id)
        (lib.escapeShellArg repository.label)
        (lib.escapeShellArg (lib.concatStringsSep " " supportedReleases))
        installCases
      ]
      (builtins.readFile ./install.sh)
  );
  packages = runCommand "repository-packages" { } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (name: ''
      mkdir -p "$out/${name}"
      ${lib.concatMapStringsSep "\n" (package: ''
        cp -R ${package}/. "$out/${name}/"
      '') channels.${name}.packages}
    '') channelNames}
    cp ${installScript} "$out/install.sh"
    chmod 644 "$out/install.sh"
    ${lib.optionalString (documentation != null) ''
      cp -R ${lib.escapeShellArg (toString documentation)} "$out/doc"
    ''}
  '';
  repositories = {
    apt = {
      suites = aptSuites;
      architectures = aptArchitectures;
      architecturesBySuite = lib.genAttrs aptSuites (name: lib.unique channels.${name}.architectures);
    };
    dnf = repositoriesOf "dnf";
    pacman = repositoriesOf "pacman";
  };
in
assert lib.assertMsg (
  !(repository.channels ? apt)
) "metarepo: channel 'apt' conflicts with the shared APT repository directory";
assert lib.assertMsg (
  unknownChannels == [ ]
) "metarepo: publications reference unknown channels: ${lib.concatStringsSep ", " unknownChannels}";
assert lib.assertMsg (
  documentation == null || !(repository.channels ? doc)
) "metarepo: channel 'doc' conflicts with the documentation directory";
assert lib.assertMsg (lib.all
  (
    name:
    lib.all (
      entryFormat: entryFormat == configuredChannels.${name}.format
    ) configuredChannels.${name}.entryFormats
  )
  configuredChannelNames
) "metarepo: publication package format does not match its configured channel format";
assert lib.assertMsg (lib.all validToken (
  channelNames
  ++ lib.concatMap (name: configuredChannels.${name}.releases) configuredChannelNames
  ++ supportedReleases
  ++ lib.concatMap (name: channels.${name}.architectures) channelNames
  ++ [ repository.id ]
)) "metarepo: invalid repository ID, channel, release or architecture";
assert lib.assertMsg (
  builtins.length supportedReleases == builtins.length (lib.unique supportedReleases)
) "metarepo: a release selector cannot refer to multiple channels";
(callPackage ./mk-repository.nix { } { inherit packages repositories repository; }).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit installScript;
    };
  })
