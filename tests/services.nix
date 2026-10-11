{ pkgs, api }:
let
  lib = pkgs.lib;
  unit = pkgs.writeText "example.service" ''
    [Service]
    ExecStart=/usr/bin/example
    [Install]
    WantedBy=multi-user.target
  '';
  make =
    format: architecture:
    api.mkPackage {
      inherit format architecture;
      name = "test-services";
      version = "1.0";
      description = "Test optional systemd lifecycle";
      homepage = "https://example.invalid";
      maintainer = "Test";
      license = "MIT";
      systemd.units = {
        "example.service" = {
          source = unit;
          enable = true;
          start = true;
          restartOnUpgrade = true;
        };
        "leave-running.service" = {
          source = unit;
          start = true;
          stopOnRemove = false;
        };
        "manual.service" = unit;
        "source-only.service" = {
          source = unit;
        };
      };
      hooks = {
        postInstall = ''printf 'custom:%s\n' "$METAREPO_ACTION" >> "$CALLS"'';
        preRemove = ''printf 'custom:before-%s\n' "$METAREPO_ACTION" >> "$CALLS"'';
        postRemove = ''printf 'custom:after-%s\n' "$METAREPO_ACTION" >> "$CALLS"'';
      };
    };
  packages = {
    apt = make "apt" "all";
    dnf = make "dnf" "noarch";
    pacman = make "pacman" "any";
  };
in
pkgs.runCommand "service-lifecycle-tests"
  {
    nativeBuildInputs = [
      pkgs.dpkg
      pkgs.rpm
      pkgs.libarchive
    ];
  }
  ''
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (format: package: ''
        mkdir ${format}
        (cd ${format}; sh ${./services.sh} ${format} ${package})
      '') packages
    )}
    touch "$out"
  ''
