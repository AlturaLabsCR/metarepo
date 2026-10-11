{ pkgs }:
let
  lib = pkgs.lib;
  integrate = pkgs.callPackage ../lib/package-integrations.nix { };
  make = format: integrate {
    inherit format;
    name = "example";
    payload = pkgs.emptyDirectory;
    refreshCertificates = true;
    certificates = {
      "first.crt" = pkgs.writeText "first.crt" "first certificate";
      "second.crt" = pkgs.writeText "second.crt" "second certificate";
    };
    systemd = {
      units."example.service" = pkgs.writeText "example.service" "[Service]\nExecStart=/usr/bin/example\n";
      sysusers."example.conf" = pkgs.writeText "sysusers.conf" "u example -\n";
      tmpfiles."example.conf" = pkgs.writeText "tmpfiles.conf" "d /var/lib/example 0750 example example -\n";
    };
  };
  cases = lib.genAttrs [ "apt" "dnf" "pacman" ] make;
  empty = integrate {
    name = "empty"; format = "apt"; payload = pkgs.emptyDirectory;
    certificates = { }; systemd = { }; refreshCertificates = false;
  };
  directories = {
    apt = "usr/local/share/ca-certificates";
    dnf = "usr/share/pki/ca-trust-source/anchors";
    pacman = "usr/share/ca-certificates/trust-source/anchors";
  };
  invalid = options: builtins.tryEval ((integrate ({
    name = "example"; format = "apt"; payload = pkgs.emptyDirectory;
    certificates = { }; systemd = { }; refreshCertificates = false;
  } // options)).payload.drvPath);
in
assert empty.payload == pkgs.emptyDirectory;
assert empty.depends == [ ];
assert empty.hooks.postInstall == "";
assert empty.hooks.postRemove == "";
assert cases.apt.depends == [ "systemd" "ca-certificates" ];
assert cases.pacman.depends == [ "systemd" "ca-certificates-utils" ];
assert !(invalid { certificates."../bad.crt" = pkgs.emptyDirectory; }).success;
assert !(invalid { certificates."bad.pem" = pkgs.emptyDirectory; }).success;
assert !(invalid { systemd.typo = { }; }).success;
assert !(invalid { systemd.tmpfiles."bad.txt" = pkgs.emptyDirectory; }).success;
pkgs.runCommand "integration-tests" { } ''
  mkdir bin
  for tool in update-ca-certificates update-ca-trust systemctl systemd-sysusers systemd-tmpfiles; do
    cat > "bin/$tool" <<'SH'
  #!/bin/sh
  printf '%s:%s\n' "''${0##*/}" "$*" >> "$CALLS"
  SH
    chmod 755 "bin/$tool"
  done
  export PATH="$PWD/bin:$PATH" CALLS="$PWD/calls"
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (format: integration: ''
    test -f ${integration.payload}/${directories.${format}}/example-first.crt
    test -f ${integration.payload}/${directories.${format}}/example-second.crt
    test -f ${integration.payload}/usr/lib/systemd/system/example.service
    test -f ${integration.payload}/usr/lib/sysusers.d/example.conf
    test -f ${integration.payload}/usr/lib/tmpfiles.d/example.conf
    installScript=${pkgs.writeText "${format}-install" integration.hooks.postInstall}
    removeScript=${pkgs.writeText "${format}-remove" integration.hooks.postRemove}
    sh -n "$installScript"
    sh -n "$removeScript"
    : > "$CALLS"
    sh "$installScript"
    test "$(grep -c '^update-ca-' "$CALLS")" = 1
    grep -Fx 'systemd-sysusers:example.conf' "$CALLS"
    grep -Fx 'systemd-tmpfiles:--create example.conf' "$CALLS"
    if [ -d /run/systemd/system ]; then grep -Fx 'systemctl:daemon-reload' "$CALLS"; fi
    : > "$CALLS"
    sh "$removeScript"
    test "$(grep -c '^update-ca-' "$CALLS")" = 1
    if grep -q '^systemd-\(sysusers\|tmpfiles\):' "$CALLS"; then exit 1; fi
  '') cases)}
  touch "$out"
''
