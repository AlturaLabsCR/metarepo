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
  depends ? [ ],
  maintainer,
  recommends ? [ ],
  release ? "1",
  hooks ? { },
  conflicts ? [ ],
  provides ? [ ],
}:
let
  hasHooks = lib.any (script: script != "") (builtins.attrValues hooks);
  pkgbuild = writeText "PKGBUILD" ''
    pkgname=${lib.escapeShellArg name}
    pkgver=${lib.escapeShellArg version}
    pkgrel=${lib.escapeShellArg release}
    pkgdesc=${lib.escapeShellArg description}
    arch=(${lib.escapeShellArg architecture})
    url=${lib.escapeShellArg homepage}
    license=(${lib.escapeShellArg license})
    depends=(${lib.concatMapStringsSep " " lib.escapeShellArg depends})
    optdepends=(${lib.concatMapStringsSep " " lib.escapeShellArg recommends})
    ${lib.optionalString hasHooks "install=hooks.install"}
    conflicts=(${lib.concatMapStringsSep " " lib.escapeShellArg conflicts})
    provides=(${lib.concatMapStringsSep " " lib.escapeShellArg provides})
    source=()
    sha256sums=()

    package() {
      mkdir -p "$pkgdir"
      cp -R ${payload}/. "$pkgdir/"
      # Nix store directories are read-only; restore owner write permission
      # in the staging tree before makepkg records the package's modes.
      find "$pkgdir" -type d -exec chmod u+w {} +
    }
  '';
  installScript = writeText "hooks.install" ''
    post_install() {
      ${hooks.postInstall or ""}
      :
    }
    post_upgrade() { post_install "$@"; }
    post_remove() {
      ${hooks.postRemove or ""}
      :
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
    PACKAGER=${lib.escapeShellArg maintainer}
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
    passthru.metarepo = {
      format = "pacman";
      inherit architecture;
    };
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
    ${lib.optionalString hasHooks "cp ${installScript} hooks.install"}
    PATH=${pacmanTools}/bin:$PATH makepkg --config ${makepkgConf} --nodeps --noconfirm --skipchecksums --nosign
    test -n "$(find "$out" -type f -name '*.pkg.tar.zst' -print -quit)"
  ''
