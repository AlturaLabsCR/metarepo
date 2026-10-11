{ lib, runCommand }:
{ name, format, payload, certificates, systemd, refreshCertificates, hooks ? { } }:
let
  actions = import ./hooks.nix { inherit lib; } {
    inherit format certificates systemd refreshCertificates hooks;
  };
  certificateDirectory = {
    apt = "usr/local/share/ca-certificates";
    dnf = "usr/share/pki/ca-trust-source/anchors";
    pacman = "usr/share/ca-certificates/trust-source/anchors";
  }.${format};
  resources = [
    {
      directory = certificateDirectory;
      files = lib.mapAttrs' (file: source: lib.nameValuePair "${name}-${file}" source) certificates;
    }
    { directory = "usr/lib/systemd/system"; files = systemd.units or { }; }
    { directory = "usr/lib/sysusers.d"; files = systemd.sysusers or { }; }
    { directory = "usr/lib/tmpfiles.d"; files = systemd.tmpfiles or { }; }
  ];
  active = lib.filter (resource: resource.files != { }) resources;
  safeFile = file: !(builtins.elem file [ "." ".." ]) && builtins.match "[a-zA-Z0-9_@.+-]+" file != null;
in
assert lib.assertMsg (lib.all (resource: lib.all safeFile (builtins.attrNames resource.files)) active)
  "metarepo: integration file names must be plain basenames";
assert lib.assertMsg (lib.all (file: lib.hasSuffix ".crt" file) (builtins.attrNames certificates))
  "metarepo: certificate names must end in .crt (one PEM certificate per file)";
assert lib.assertMsg (lib.all (kind:
  lib.all (file: lib.hasSuffix ".conf" file) (builtins.attrNames (systemd.${kind} or { }))
) [ "sysusers" "tmpfiles" ]) "metarepo: sysusers and tmpfiles names must end in .conf";
assert lib.assertMsg (lib.all (key: builtins.elem key [ "units" "sysusers" "tmpfiles" ]) (builtins.attrNames systemd))
  "metarepo: systemd supports units, sysusers and tmpfiles";
{
  inherit (actions) depends hooks;
  payload = if active == [ ] then payload else runCommand "${name}-integrated-payload" { } ''
    cp -R ${payload} "$out"
    chmod -R u+w "$out"
    ${lib.concatMapStringsSep "\n" (resource:
      lib.concatStringsSep "\n" (lib.mapAttrsToList (file: source: ''
        install -Dm644 ${lib.escapeShellArg (toString source)} "$out"/${lib.escapeShellArg "${resource.directory}/${file}"}
      '') resource.files)
    ) active}
  '';
}
