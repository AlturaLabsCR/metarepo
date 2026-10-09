{
  lib,
  callPackage,
  runCommand,
  writeText,
}:
{ publications, repository }:
let
  channelNames = lib.unique (
    lib.concatMap (publication: builtins.attrNames publication.channels) publications
  );
  channel =
    name:
    let
      entries = map (publication: publication.channels.${name}) (
        lib.filter (publication: builtins.hasAttr name publication.channels) publications
      );
      formats = map (entry: entry.format or entry.package.passthru.metarepo.format) entries;
      format = builtins.head formats;
    in
    assert lib.all (candidate: candidate == format) formats;
    assert builtins.elem format [
      "apt"
      "dnf"
      "pacman"
    ];
    {
      inherit format;
      releases = lib.unique (lib.concatMap (entry: entry.releases or [ ]) entries);
      packages = map (entry: entry.package) entries;
      architectures = map (
        entry: entry.architecture or entry.package.passthru.metarepo.architecture
      ) entries;
    };
  channels = lib.genAttrs channelNames channel;
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
assert lib.assertMsg (lib.all validToken (
  channelNames
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
