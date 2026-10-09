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
      entries = lib.filter (publication: builtins.hasAttr name publication.channels) publications;
      formats = map (publication: publication.channels.${name}.format) entries;
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
      packages = map (publication: publication.channels.${name}.package) entries;
      architectures = map (publication: publication.channels.${name}.architecture) entries;
    };
  channels = lib.genAttrs channelNames channel;
  repositoriesOf = format: lib.filter (name: channels.${name}.format == format) channelNames;
  aptSuites = repositoriesOf "apt";
  repositoryArchitectures = names: lib.unique (
    lib.concatMap (name: channels.${name}.architectures) names
  );
  aptArchitectures = repositoryArchitectures aptSuites;
  dnfArchitectures = repositoryArchitectures repositories.dnf;
  pacmanArchitectures = repositoryArchitectures repositories.pacman;
  aptReleaseMappings = [
    { release = "ubuntu2404"; suite = "noble"; }
    { release = "ubuntu2604"; suite = "noble"; }
    { release = "debian13"; suite = "noble"; }
    { release = "linuxmint7"; suite = "noble"; }
    { release = "ubuntu2204"; suite = "jammy"; }
  ];
  availableAptReleaseMappings = lib.filter
    (mapping: builtins.elem mapping.suite repositories.apt.suites)
    aptReleaseMappings;
  aptInstallCases = lib.concatMapStringsSep "\n"
    (suite:
      let
        aliases = map (mapping: mapping.release) (lib.filter
          (mapping: mapping.suite == suite)
          availableAptReleaseMappings);
        releases = [ suite ] ++ aliases;
      in
      "    ${lib.concatStringsSep "|" releases}) _install_apt ${suite} ;;")
    repositories.apt.suites;
  dnfInstallCases = if repositories.dnf == [ ] then "" else "    fedora44) _install_dnf ;;";
  pacmanInstallCases = if repositories.pacman == [ ] then "" else "    arch) _install_arch ;;";
  supportedReleases = lib.unique (
    repositories.apt.suites
    ++ map (mapping: mapping.release) availableAptReleaseMappings
    ++ (if repositories.dnf == [ ] then [ ] else [ "fedora44" ])
    ++ (if repositories.pacman == [ ] then [ ] else [ "arch" ])
  );
  installScript = writeText "install.sh" (lib.replaceStrings
    [
      "@REPO_ROOT@"
      "@REPO_ID@"
      "@REPO_LABEL@"
      "@APT_ARCHITECTURES@"
      "@DNF_ARCHITECTURES@"
      "@DNF_REPOSITORIES@"
      "@PACMAN_ARCHITECTURES@"
      "@PACMAN_REPOSITORIES@"
      "@SUPPORTED@"
      "@APT_INSTALL_CASES@"
      "@DNF_INSTALL_CASES@"
      "@PACMAN_INSTALL_CASES@"
    ]
    [
      (lib.escapeShellArg repository.url)
      (lib.escapeShellArg repository.id)
      (lib.escapeShellArg repository.label)
      (lib.escapeShellArg (lib.concatStringsSep " " aptArchitectures))
      (lib.escapeShellArg (lib.concatStringsSep " " dnfArchitectures))
      (lib.escapeShellArg (lib.concatStringsSep " " repositories.dnf))
      (lib.escapeShellArg (lib.concatStringsSep " " pacmanArchitectures))
      (lib.escapeShellArg (lib.concatStringsSep " " repositories.pacman))
      (lib.escapeShellArg (lib.concatStringsSep " " supportedReleases))
      aptInstallCases
      dnfInstallCases
      pacmanInstallCases
    ]
    (builtins.readFile ./install.sh));
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
    };
    dnf = repositoriesOf "dnf";
    pacman = repositoriesOf "pacman";
  };
in
callPackage ./mk-repository.nix { } { inherit packages repositories repository; }
