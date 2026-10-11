/**
  Internal composer for package installation and removal actions.
  Enable actions from declared files, infer dependencies and append custom hooks.
  Sysusers runs before tmpfiles, unit reloads and certificate trust refresh.
  No action enables or starts services or deletes users or service data.

  # Type

  ```
  hooks :: AttrSet -> { depends :: [String], hooks :: AttrSet }
  ```

  # Inputs

  `format`
  : Package format: `apt`, `dnf` or `pacman`.

  `certificates`, `systemd`, `refreshCertificates`
  : Integration declarations from `mkPackage`; these inputs are required here.

  `hooks`
  : Optional `postInstall` and `postRemove` shell strings; defaults to `{ }`.
    Other hook names are rejected.

  # Examples

  ```nix
  actions = import ./lib/hooks.nix { inherit lib; } {
    format = "apt";
    certificates = { };
    systemd = { };
    refreshCertificates = true;
    hooks.postInstall = "echo refreshed";
  };
  # actions.depends == [ "ca-certificates" ]
  ```
*/
{ lib }:
{
  format,
  certificates,
  systemd,
  refreshCertificates,
  hooks ? { },
}:
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
  events = [
    "postInstall"
    "postRemove"
  ];
in
assert lib.assertMsg (lib.all (event: builtins.elem event events) (
  builtins.attrNames hooks
)) "metarepo: hooks supports postInstall and postRemove";
{
  depends = lib.unique (lib.concatMap (action: action.depends) actions);
  hooks = lib.genAttrs events (
    event:
    lib.concatStringsSep "\n" (
      lib.unique (map (action: action.${event}) actions) ++ lib.optional (hooks ? ${event}) hooks.${event}
    )
  );
}
