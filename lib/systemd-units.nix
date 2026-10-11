/**
  Internal normalizer and lifecycle action builder for systemd units.
  Accept source files or records with a source and explicit lifecycle options.
  Return the file map and an action record consumed by the hook composer.
  Preserve users and service data on removal.

  # Type

  ```
  systemdUnits :: AttrSet -> AttrSet
  ```

  # Inputs

  `format`
  : Package format: `apt`, `dnf` or `pacman`. APT uses Debian's service helpers
    to respect policy-rc.d; other formats use systemctl.

  `units`
  : Unit basenames mapped to source paths, file derivations, or records with
    `source`, `enable`, `start`, `restartOnUpgrade` and `stopOnRemove`.
    The first three lifecycle flags default to false. `stopOnRemove` defaults
    to true when any of them is true, otherwise false.

  Hooks receive `METAREPO_ACTION` from the native builder. Enable/start requests
  occur only on installation; upgrades only try to restart active units.
  Before removal, managed units are stopped and those enabled by the package
  are disabled. Runtime requests are skipped without a running systemd manager.
  Lifecycle command failures are reported by the tools but do not fail packaging.

  # Examples

  ```nix
  actions = import ./lib/systemd-units.nix { inherit lib; } {
    format = "apt";
    units."example.service" = {
      source = ./example.service;
      enable = true;
      start = true;
      restartOnUpgrade = true;
    };
  };
  ```
*/
{ lib }:
{ format, units }:
let
  flags = [
    "enable"
    "start"
    "restartOnUpgrade"
    "stopOnRemove"
  ];
  policies = lib.mapAttrs (
    name: value:
    let
      options = if lib.isDerivation value || !builtins.isAttrs value then { source = value; } else value;
      policy = {
        enable = false;
        start = false;
        restartOnUpgrade = false;
      }
      // options;
    in
    assert lib.assertMsg
      (
        options ? source
        && (
          builtins.isPath options.source
          || builtins.isString options.source
          || lib.isDerivation options.source
        )
        && lib.all (key: builtins.elem key ([ "source" ] ++ flags)) (builtins.attrNames options)
        && lib.all (flag: !(options ? ${flag}) || builtins.isBool options.${flag}) flags
      )
      "metarepo: unit '${name}' must be a source file or a record with source and boolean lifecycle options";
    policy
    // {
      stopOnRemove = options.stopOnRemove or (policy.enable || policy.start || policy.restartOnUpgrade);
    }
  ) units;
  selected = flag: builtins.attrNames (lib.filterAttrs (_: policy: policy.${flag}) policies);
  managed = lib.unique (lib.concatMap selected flags);
  helper = if format == "apt" then "deb-systemd-helper" else "systemctl";
  invoke = if format == "apt" then "deb-systemd-invoke" else "systemctl";
  command =
    tool: action: names:
    lib.optionalString (names != [ ]) ''
      ${tool} ${action} ${lib.escapeShellArgs names} || true
    '';
  running =
    script:
    lib.optionalString (script != "") ''
      if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
        ${script}
      fi
    '';
  reload = running "systemctl daemon-reload";
  enable = command helper "enable" (selected "enable");
  start = running (command invoke "start" (selected "start"));
  restart = running (
    lib.concatMapStringsSep "\n" (
      name:
      if format == "apt" then
        ''
          if systemctl is-active --quiet ${lib.escapeShellArg name}; then
            ${command invoke "restart" [ name ]}
          fi
        ''
      else
        command invoke "try-restart" [ name ]
    ) (selected "restartOnUpgrade")
  );
in
assert lib.assertMsg
  (lib.all (name: builtins.match "[a-zA-Z0-9_][a-zA-Z0-9_@.+-]*" name != null) managed)
  "metarepo: managed unit names must be plain basenames starting with a letter, digit or underscore";
{
  files = lib.mapAttrs (_: policy: policy.source) policies;
  enabled = units != { };
  depends = [ "systemd" ] ++ lib.optional (format == "apt" && managed != [ ]) "init-system-helpers";
  postInstall =
    reload
    + lib.optionalString (enable + start + restart != "") ''
      case "''${METAREPO_ACTION:-install}" in
        install)
          ${enable}
          ${start}
          : ;;
        upgrade)
          ${restart}
          : ;;
      esac
    '';
  preRemove =
    running (command invoke "stop" (selected "stopOnRemove"))
    + command helper "disable" (selected "enable");
  postRemove =
    reload
    + lib.optionalString (format == "apt" && selected "enable" != [ ]) ''
      if [ "''${METAREPO_ACTION:-remove}" = purge ]; then
        ${command helper "purge" (selected "enable")}
      fi
    '';
}
