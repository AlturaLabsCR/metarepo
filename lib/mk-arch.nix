{
  lib,
  runCommand,
  writeText,
  makeWrapper,
  pacman,
  fakeroot,
  binutils,
  coreutils,
  findutils,
  gawk,
  gettext,
  gnugrep,
  gnused,
  gzip,
  libarchive,
  zstd,
}:
{
  name,
  version,
  payload,
  architecture,
  description,
  homepage,
  license,
  depends,
  release ? "1",
}:
let
  pkgbuild = writeText "PKGBUILD" ''
    pkgname=${lib.escapeShellArg name}
    pkgver=${lib.escapeShellArg version}
    pkgrel=${lib.escapeShellArg release}
    pkgdesc=${lib.escapeShellArg description}
    arch=(${lib.escapeShellArg architecture})
    url=${lib.escapeShellArg homepage}
    license=(${lib.escapeShellArg license})
    depends=(${lib.concatMapStringsSep " " lib.escapeShellArg depends})
    source=()
    sha256sums=()

    package() {
      mkdir -p "$pkgdir"
      cp -R ${payload}/. "$pkgdir/"
    }
  '';
  makepkgConf = writeText "makepkg.conf" ''
    . ${pacman}/etc/makepkg.conf
    CARCH=${lib.escapeShellArg architecture}
    BUILDDIR="$PWD/build"
    PKGDEST="$out"
    PKGEXT='.pkg.tar.zst'
    SRCDEST="$PWD/src"
    LOGDEST="$PWD/log"
    PACKAGER="Metarepo <packages@example.invalid>"
    GPGKEY=""
  '';
  pacmanConf = writeText "pacman.conf" ''
    [options]
    Architecture = auto
    DBPath = /tmp/pacman-db
    CacheDir = /tmp/pacman-cache
    LogFile = /tmp/pacman.log
  '';
  pacmanTools = runCommand "makepkg-pacman-tools" { nativeBuildInputs = [ makeWrapper ]; } ''
    mkdir -p "$out/bin"
    makeWrapper ${pacman}/bin/pacman "$out/bin/pacman" \
      --add-flags "--config ${pacmanConf}"
    makeWrapper ${pacman}/bin/pacman-conf "$out/bin/pacman-conf" \
      --add-flags "--config ${pacmanConf}"
  '';
in
runCommand "${name}-arch-${version}"
  {
    nativeBuildInputs = [
      pacmanTools
      pacman
      fakeroot
      binutils
      coreutils
      findutils
      gawk
      gettext
      gnugrep
      gnused
      gzip
      libarchive
      zstd
    ];
  }
  ''
    mkdir -p "$out" build src log /tmp/pacman-db /tmp/pacman-cache
    cp ${pkgbuild} PKGBUILD
    PATH=${pacmanTools}/bin:$PATH makepkg --config ${makepkgConf} --nodeps --noconfirm --skipchecksums --nosign
    test -n "$(find "$out" -type f -name '*.pkg.tar.zst' -print -quit)"
  ''
