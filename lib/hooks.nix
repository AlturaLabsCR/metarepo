/**
  Internal composer for package installation and removal actions.
  Enable actions from declared files, infer dependencies and append custom hooks.
  Sysusers runs before tmpfiles, certificate trust refresh and unit lifecycle actions.
  Unit lifecycle options explicitly request enable/start/restart/stop actions.
  Users and service data are preserved.

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
  : Optional `postInstall`, `preRemove` and `postRemove` shell strings; defaults
    to `{ }`. Native builders set `METAREPO_ACTION` to install, upgrade, remove
    or purge. Other hook names are rejected.

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
  refresh = if format == "apt" then "update-ca-certificates" else "update-ca-trust extract";
  actions = lib.filter (action: action.enabled) [
    (configuration "sysusers" "systemd-sysusers" [ ])
    (configuration "tmpfiles" "systemd-tmpfiles" [ "--create" ])
    {
      enabled = certificates != { } || refreshCertificates;
      depends = [ (if format == "pacman" then "ca-certificates-utils" else "ca-certificates") ];
      postInstall = refresh;
      postRemove = refresh;
    }
    (import ./systemd-units.nix { inherit lib; } {
      inherit format;
      units = systemd.units or { };
    })
  ];
  events = [
    "postInstall"
    "preRemove"
    "postRemove"
  ];
in
assert lib.assertMsg (lib.all (event: builtins.elem event events) (
  builtins.attrNames hooks
)) "metarepo: hooks supports postInstall, preRemove and postRemove";
{
  depends = lib.unique (lib.concatMap (action: action.depends) actions);
  hooks = lib.genAttrs events (
    event:
    lib.concatStringsSep "\n" (
      lib.unique (map (action: action.${event} or "") actions)
      ++ lib.optional (hooks ? ${event}) hooks.${event}
    )
  );
}
