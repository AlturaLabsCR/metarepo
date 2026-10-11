{ lib, stdenv, emptyDirectory, mkPackage }:
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
  architectures = if independent then {
    apt = "all"; dnf = "noarch"; pacman = "any";
  } else {
    apt = { x86_64-linux = "amd64"; aarch64-linux = "arm64"; }.${stdenv.hostPlatform.system};
    dnf = stdenv.hostPlatform.uname.processor;
    pacman = stdenv.hostPlatform.uname.processor;
  };
  common = builtins.removeAttrs args [
    "repository" "package" "payload" "channels" "independent" "formats" "overrides"
  ];
  publish = pkg: channel:
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
    in mkPackage (defaults // common // (pkg.passthru.publication or { })
      // (formats.${format} or { }) // (overrides.${channel} or { }) // { inherit format; });
  packages = builtins.attrValues (package.passthru.snapshots or { current = package; });
in
{
  channels = lib.genAttrs channels (channel: map (pkg: publish pkg channel) packages);
}
