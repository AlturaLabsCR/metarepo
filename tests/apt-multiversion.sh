#!/bin/sh
set -eu

repository_script="$1"
export PACKAGE_DIR="$PWD/packages"
export APT_SUITES='single mixed portable variant'
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
# Guarantee byte-identical input across suites, regardless of build timestamps.
cp "$PACKAGE_DIR/single/example_1.0_all.deb" "$PACKAGE_DIR/portable/"
# Same name/version/architecture, but a genuinely different distro payload.
printf variant > control/variant
make_deb variant example 1.0 all

apt_architectures() {
  case "$1" in
    single) echo all ;;
    mixed) echo 'amd64 arm64' ;;
    portable) echo 'amd64 arm64 all' ;;
    variant) echo 'amd64 all' ;;
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

for entry in single:all:1 mixed:amd64:2 mixed:arm64:1 portable:amd64:2 portable:arm64:2 portable:all:2 variant:all:1; do
  suite="${entry%%:*}"
  rest="${entry#*:}"
  arch="${rest%%:*}"
  count="${rest#*:}"
  index="public/apt/dists/$suite/main/binary-$arch/Packages"
  test "$(grep -c '^Package: example$' "$index")" = "$count"
  grep -Fx 'Version: 1.0' "$index"
  if [ "$count" = 2 ]; then grep -Fx 'Version: 2.0' "$index"; fi
  gzip -dc "$index.gz" | cmp - "$index"
done
# Six unique payloads remain as regular files, with no published suite copies.
test "$(find public/apt/pool -type f | wc -l)" = 6
test -z "$(find public -type l)"
for suite in $APT_SUITES; do test ! -e "public/$suite"; done
single_path="$(sed -n 's/^Filename: //p' public/apt/dists/single/main/binary-all/Packages)"
grep -Fx "Filename: $single_path" public/apt/dists/portable/main/binary-all/Packages
variant_path="$(sed -n 's/^Filename: //p' public/apt/dists/variant/main/binary-all/Packages)"
test "$single_path" != "$variant_path"
for index in public/apt/dists/*/main/binary-*/Packages; do
  awk '/^Filename: / { file=$2 } /^SHA256: / { print $2 "  " file }' "$index" > checksums
  (cd public/apt && sha256sum -c ../../checksums)
done
if grep -E 'repeat|multiple instances' scan-errors; then exit 1; fi

# Resolve and download through APT, including equal filenames with different
# suite-specific bytes. No package installation or system configuration writes.
for suite in portable variant; do
  client="$PWD/client-$suite"
  mkdir -p "$client/lists/partial" "$client/cache/archives/partial" "$client/download"
  printf 'deb [trusted=yes] file:%s/public/apt %s main\n' "$PWD" "$suite" > "$client/sources.list"
  apt_client() {
    apt-get -o "Dir::Etc::sourcelist=$client/sources.list" \
      -o Dir::Etc::sourceparts=- -o "Dir::State::lists=$client/lists" \
      -o "Dir::Cache=$client/cache" -o APT::Architecture=amd64 \
      -o 'APT::System=Debian dpkg interface' \
      -o "Dir::Bin::dpkg=$(command -v dpkg)" \
      -o "APT::Sandbox::User=$(id -un)" -o Debug::NoLocking=true "$@"
  }
  apt_client update
  (cd "$client/download" && apt_client download example=1.0)
  case "$suite" in
    portable) path="$single_path" ;;
    variant) path="$variant_path" ;;
  esac
  cmp "$client/download/example_1.0_all.deb" "public/apt/$path"
done

# Signing must cover the final indexes at their shared repository location.
export GNUPGHOME="$PWD/gnupg"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --passphrase '' --quick-generate-key 'Test <test@example.invalid>' rsa2048 sign 0
export GPG_KEY_ID=test@example.invalid
(
  set -- "$PWD/signed"
  . "$repository_script"
) 2> signed-errors
for suite in $APT_SUITES; do
  release="signed/apt/dists/$suite"
  gpg --verify "$release/InRelease"
  gpg --verify "$release/Release.gpg" "$release/Release"
  for index in "$release"/main/binary-*/Packages; do
    cmp "public/apt/dists/$suite/${index#"$release/"}" "$index"
  done
done
