{ lib }:
{ format, certificates, systemd, refreshCertificates, hooks ? { } }:
let
  configuration = kind: tool: arguments: {
    enabled = (systemd.${kind} or { }) != { };
    depends = [ "systemd" ];
    # Basenames preserve administrator overrides in /etc.
    postInstall = ''
      if command -v ${tool} >/dev/null 2>&1; then
        ${tool} ${lib.escapeShellArgs (arguments ++ builtins.attrNames (systemd.${kind} or { }))}
      fi
    '';
    postRemove = "";
  };
  reload = ''
    if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
      systemctl daemon-reload
    fi
  '';
  refresh = if format == "apt" then "update-ca-certificates" else "update-ca-trust extract";
  actions = lib.filter (action: action.enabled) [
    (configuration "sysusers" "systemd-sysusers" [ ])
    (configuration "tmpfiles" "systemd-tmpfiles" [ "--create" ])
    {
      enabled = (systemd.units or { }) != { };
      depends = [ "systemd" ];
      postInstall = reload;
      postRemove = reload;
    }
    {
      enabled = certificates != { } || refreshCertificates;
      depends = [ (if format == "pacman" then "ca-certificates-utils" else "ca-certificates") ];
      postInstall = refresh;
      postRemove = refresh;
    }
  ];
  events = [ "postInstall" "postRemove" ];
in
assert lib.assertMsg (lib.all (event: builtins.elem event events) (builtins.attrNames hooks))
  "metarepo: hooks supports postInstall and postRemove";
{
  depends = lib.unique (lib.concatMap (action: action.depends) actions);
  hooks = lib.genAttrs events (event:
    lib.concatStringsSep "\n" (
      lib.unique (map (action: action.${event}) actions)
      ++ lib.optional (hooks ? ${event}) hooks.${event}
    )
  );
}
