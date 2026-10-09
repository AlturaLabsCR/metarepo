#!/bin/sh

set -eu

REPO_ROOT=@REPO_ROOT@
REPO_ID=@REPO_ID@
REPO_LABEL=@REPO_LABEL@
REPO_KEY="$REPO_ID.asc"
APT_ARCHITECTURES=@APT_ARCHITECTURES@
DNF_ARCHITECTURES=@DNF_ARCHITECTURES@
DNF_REPOSITORIES=@DNF_REPOSITORIES@
PACMAN_ARCHITECTURES=@PACMAN_ARCHITECTURES@
PACMAN_REPOSITORIES=@PACMAN_REPOSITORIES@
SUPPORTED=@SUPPORTED@

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must be run as root" >&2
  exit 1
fi

_error() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

_check_architecture() {
  available="$1"
  requested="$2"
  case " $available " in
    *" $requested "*|*" noarch "*|*" any "*) ;;
    *) _error "architecture '$requested' is not available (available: $available)" ;;
  esac
}

_install_apt() {
  suite="$1"
  architecture="$(dpkg --print-architecture)"
  _check_architecture "$APT_ARCHITECTURES" "$architecture"

  install -d -m 0755 /usr/share/keyrings
  curl -fsSLo "/usr/share/keyrings/$REPO_KEY" "$REPO_ROOT/$REPO_KEY"
  printf 'deb [arch=%s signed-by=/usr/share/keyrings/%s] %s/%s %s main\n' \
    "$architecture" "$REPO_KEY" "$REPO_ROOT" "$suite" "$suite" \
    > "/etc/apt/sources.list.d/$REPO_ID.list"
  apt-get update
}

_install_dnf() {
  architecture="$(uname -m)"
  _check_architecture "$DNF_ARCHITECTURES" "$architecture"

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' 0
  curl -fsSLo "$tmp" "$REPO_ROOT/$REPO_KEY"
  install -D -m 0644 "$tmp" "/etc/pki/rpm-gpg/$REPO_KEY"
  rpm --import "/etc/pki/rpm-gpg/$REPO_KEY"

  install -d -m 0755 /etc/yum.repos.d
  for repository in $DNF_REPOSITORIES; do
    cat > "/etc/yum.repos.d/$REPO_ID-$repository.repo" <<INI
[$REPO_ID-$repository]
name=$REPO_LABEL ($repository)
baseurl=$REPO_ROOT/$repository/
enabled=1
gpgcheck=1
# Disable metadata signature checks to avoid the related warning.
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/$REPO_KEY
INI
  done
}

_install_arch() {
  architecture="$(uname -m)"
  _check_architecture "$PACMAN_ARCHITECTURES" "$architecture"

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' 0
  curl -fsSLo "$tmp" "$REPO_ROOT/$REPO_KEY"
  pacman-key --add "$tmp"
  fingerprint="$(gpg --show-keys --with-colons "$tmp" | sed -n '/^fpr:/ { s/:$//; s/.*://; p; q; }')"
  [ -n "$fingerprint" ] || _error "could not read repository key fingerprint"
  pacman-key --lsign-key "$fingerprint"
  rm -f "$tmp"
  trap - 0

  install -d -m 0755 /etc/pacman.d/repos.d
  : > "/etc/pacman.d/repos.d/$REPO_ID.conf"
  for repository in $PACMAN_REPOSITORIES; do
    cat >> "/etc/pacman.d/repos.d/$REPO_ID.conf" <<INI
[$REPO_ID-$repository]
SigLevel = Required
Server = $REPO_ROOT/$repository/

INI
  done

  if ! grep -Eq '^ *Include *= */etc/pacman\.d/repos\.d/\*\.conf *(#.*)?$' /etc/pacman.conf; then
    printf '\nInclude = /etc/pacman.d/repos.d/*.conf\n' >> /etc/pacman.conf
  fi

  pacman -Sy
}

_install_release() {
  case "$1" in
@APT_INSTALL_CASES@
@DNF_INSTALL_CASES@
@PACMAN_INSTALL_CASES@
    *) _error "unsupported release '$1'" ;;
  esac
}

_get_release() {
  for release_file in /etc/os-release /usr/lib/os-release; do
    if [ -f "$release_file" ] && [ -r "$release_file" ]; then
      # shellcheck disable=SC1090
      . "$release_file"
      break
    fi
  done

  release_id="$(printf '%s' "${ID:-}${VERSION_ID:-}" | tr -d '.')"
  case " $SUPPORTED " in
    *" $release_id "*) printf '%s\n' "$release_id"; return ;;
  esac

  codename="${VERSION_CODENAME:-}"
  case " $SUPPORTED " in
    *" $codename "*) printf '%s\n' "$codename"; return ;;
  esac

  printf "error: unsupported release '%s', install manually\n\nsupported:\n  %s\n" \
    "$release_id" "$SUPPORTED" >&2
  return 1
}

release="$(_get_release)"
_install_release "$release"
