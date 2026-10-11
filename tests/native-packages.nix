{ pkgs, api }:
let
  common = {
    name = "test-native";
    version = "1.0";
    payload = pkgs.runCommand "test-payload" { } ''
      mkdir -p "$out/usr/share/test-native"
      echo hello > "$out/usr/share/test-native/hello"
    '';
    description = "Test native packaging defaults";
    homepage = "https://example.invalid";
    maintainer = "Test <test@example.invalid>";
    license = "MIT";
  };
  make = format: architecture: api.mkPackage (common // {
    inherit format architecture;
    refreshCertificates = true;
    hooks.postInstall = "echo custom-hook";
  });
  apt = make "apt" "all";
  dnf = make "dnf" "noarch";
  pacman = make "pacman" "any";
  plain = api.mkApt (common // { architecture = "all"; });
in
pkgs.runCommand "native-package-tests" {
  nativeBuildInputs = [ pkgs.dpkg pkgs.rpm pkgs.libarchive ];
} ''
  test -z "$(dpkg-deb -f ${plain}/*.deb Depends)"
  test "$(dpkg-deb -f ${apt}/*.deb Package)" = test-native
  test "$(dpkg-deb -f ${apt}/*.deb Depends)" = ca-certificates
  dpkg-deb -e ${apt}/*.deb control
  sh -n control/postinst
  sh -n control/postrm
  mkdir -p bin
  printf '#!/bin/sh\nprintf "refreshed\\n"\n' > bin/update-ca-certificates
  cp bin/update-ca-certificates bin/update-ca-trust
  chmod 755 bin/update-ca-certificates bin/update-ca-trust
  export PATH="$PWD/bin:$PATH"
  test "$(sh control/postinst configure)" = "$(printf 'refreshed\ncustom-hook')"
  test -z "$(sh control/postinst abort-upgrade)"
  test "$(sh control/postrm remove)" = refreshed
  test "$(sh control/postrm purge)" = refreshed
  test -z "$(sh control/postrm upgrade)"
  grep -q update-ca-certificates control/postinst
  grep -q custom-hook control/postinst
  grep -q update-ca-certificates control/postrm
  test "$(rpm -qp --qf '%{NAME}' ${dnf}/*.rpm)" = test-native
  rpm -qp --requires ${dnf}/*.rpm | grep -q ca-certificates
  rpm -qp --scripts ${dnf}/*.rpm | grep -q 'update-ca-trust extract'
  bsdtar -xOf ${pacman}/*.pkg.tar.zst .INSTALL > hooks.sh
  sh -n hooks.sh
  grep -q update-ca-trust hooks.sh
  test "$(sh -c '. ./hooks.sh; post_upgrade')" = "$(printf 'refreshed\ncustom-hook')"
  test "$(sh -c '. ./hooks.sh; post_remove')" = refreshed
  bsdtar -xOf ${pacman}/*.pkg.tar.zst .PKGINFO > pkginfo
  grep -q '^pkgname = test-native$' pkginfo
  grep -q '^depend = ca-certificates-utils$' pkginfo
  touch "$out"
''
