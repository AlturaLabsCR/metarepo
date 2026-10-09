#!/bin/sh

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

mkdir -p "$1"
cp -R "$PACKAGE_DIR"/. "$1/"
chmod -R u+w "$1"
cd "$1"

sign() {
  gpg --batch --yes --local-user "$GPG_KEY_ID" "$@"
}

if [ -n "${GPG_KEY_ID:-}" ]; then
  gpg --batch --armor --export "$GPG_KEY_ID" > "$REPOSITORY_ID.asc"
  for repository in $DNF_REPOSITORIES; do
    for package in "$repository"/*.rpm; do
      rpmsign --define "_gpg_name $GPG_KEY_ID" \
        --define "__gpg $(command -v gpg)" --addsign "$package"
    done
  done
  for repository in $PACMAN_REPOSITORIES; do
    for package in "$repository"/*.pkg.tar.zst; do
      sign --detach-sign "$package"
    done
  done
fi

for suite in $APT_SUITES; do
  (
    cd "$suite"
    mkdir -p pool/main
    mv ./*.deb pool/main/
    release="dists/$suite"
    for arch in $APT_ARCHITECTURES; do
      index="$release/main/binary-$arch/Packages"
      mkdir -p "$(dirname "$index")"
      dpkg-scanpackages --arch "$arch" pool/main > "$index"
      gzip -n -9 -c "$index" > "$index.gz"
    done
    apt-ftparchive \
      -o "APT::FTPArchive::Release::Origin=$REPOSITORY_ORIGIN" \
      -o "APT::FTPArchive::Release::Label=$REPOSITORY_LABEL" \
      -o "APT::FTPArchive::Release::Suite=$suite" \
      -o "APT::FTPArchive::Release::Codename=$suite" \
      -o "APT::FTPArchive::Release::Architectures=${APT_ARCHITECTURES}" \
      -o APT::FTPArchive::Release::Components=main \
      release "$release" > Release
    mv Release "$release/Release"
    if [ -n "${GPG_KEY_ID:-}" ]; then
      sign --clearsign --output "$release/InRelease" "$release/Release"
      sign --armor --detach-sign --output "$release/Release.gpg" "$release/Release"
    fi
  )
done

for repository in $PACMAN_REPOSITORIES; do
  if [ -n "${GPG_KEY_ID:-}" ]; then
    repo-add --sign --key "$GPG_KEY_ID" \
      "$repository/$REPOSITORY_ID.db.tar.gz" "$repository"/*.pkg.tar.zst
  else
    repo-add "$repository/$REPOSITORY_ID.db.tar.gz" "$repository"/*.pkg.tar.zst
  fi
done

for repository in $DNF_REPOSITORIES; do
  createrepo_c "$repository"
  if [ -n "${GPG_KEY_ID:-}" ]; then
    sign --armor --detach-sign "$repository/repodata/repomd.xml"
  fi
done
