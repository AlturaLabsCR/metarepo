{ lib, callPackage, emptyDirectory, mkApt, mkDnf, mkPacman }:
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
  builders = { apt = mkApt; dnf = mkDnf; pacman = mkPacman; };
  integration = callPackage ./package-integrations.nix { } {
    inherit format payload certificates systemd refreshCertificates hooks;
    inherit (args) name;
  };
in
assert lib.assertMsg (builtins.hasAttr format builders) "metarepo: unsupported package format '${format}'";
builtins.seq integration.hooks (builders.${format} (builtins.removeAttrs args [
  "format" "payload" "certificates" "systemd" "hooks" "refreshCertificates"
] // {
  inherit (integration) payload hooks;
  depends = lib.unique ((args.depends or [ ]) ++ integration.depends);
}))
