#!/bin/sh
set -eu

repository_script="$1"
export PACKAGE_DIR="$PWD/packages"
export APT_SUITES='single mixed portable'
export DNF_REPOSITORIES= PACMAN_REPOSITORIES= GPG_KEY_ID=
export REPOSITORY_ID=test REPOSITORY_ORIGIN=Test REPOSITORY_LABEL=Test
scan_log="$PWD/scans"

make_deb() {
  suite="$1" name="$2" version="$3" arch="$4"
  mkdir -p control/DEBIAN "$PACKAGE_DIR/$suite"
  cat > control/DEBIAN/control <<EOF
Package: $name
Version: $version
Architecture: $arch
Maintainer: Test <test@example.invalid>
Description: Test repository version indexing
EOF
  dpkg-deb --build control "$PACKAGE_DIR/$suite/${name}_${version}_${arch}.deb"
}

make_deb single example 1.0 all
make_deb mixed example 1.0 amd64
make_deb mixed example 2.0 amd64
make_deb mixed example 1.0 arm64
make_deb portable example 1.0 all
make_deb portable example 2.0 all

apt_architectures() {
  case "$1" in
    single) echo all ;;
    mixed) echo 'amd64 arm64' ;;
    portable) echo 'amd64 arm64 all' ;;
  esac
}

dpkg-scanpackages() {
  printf '%s %s\n' "$suite" "$*" >> "$scan_log"
  command dpkg-scanpackages "$@"
}

(
  set -- "$PWD/public"
  . "$repository_script"
) 2> scan-errors

grep -Fx 'single --arch all pool/main' "$scan_log"
grep -Fx 'mixed --arch amd64 --multiversion pool/main' "$scan_log"
grep -Fx 'mixed --arch arm64 pool/main' "$scan_log"
for arch in amd64 arm64 all; do
  grep -Fx "portable --arch $arch --multiversion pool/main" "$scan_log"
done

for entry in single:all:1 mixed:amd64:2 mixed:arm64:1 portable:amd64:2 portable:arm64:2 portable:all:2; do
  suite="${entry%%:*}"
  rest="${entry#*:}"
  arch="${rest%%:*}"
  count="${rest#*:}"
  index="public/$suite/dists/$suite/main/binary-$arch/Packages"
  test "$(grep -c '^Package: example$' "$index")" = "$count"
  grep -Fx 'Version: 1.0' "$index"
  if [ "$count" = 2 ]; then grep -Fx 'Version: 2.0' "$index"; fi
  gzip -dc "$index.gz" | cmp - "$index"
done
if grep -E 'repeat|multiple instances' scan-errors; then exit 1; fi
