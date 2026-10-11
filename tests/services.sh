#!/bin/sh
set -eu

format=$1
package=$2
mkdir bin
export CALLS="$PWD/calls" ACTIVE=no FAIL_ACTIONS=no
for tool in systemctl deb-systemd-helper deb-systemd-invoke update-ca-certificates update-ca-trust; do
  cat > "bin/$tool" <<'SH'
#!/bin/sh
printf '%s:%s\n' "${0##*/}" "$*" >> "$CALLS"
case "${0##*/}:$*" in
  systemctl:is-active*) [ "$ACTIVE" = yes ] ;;
  update-ca-*) exit 0 ;;
  *) [ "$FAIL_ACTIONS" = no ] ;;
esac
SH
  chmod 755 "bin/$tool"
done
export PATH="$PWD/bin:$PATH"

case "$format" in
  apt)
    dpkg-deb -e "$package"/*.deb scripts
    dpkg-deb -f "$package"/*.deb Depends | grep -F init-system-helpers
    dpkg-deb -x "$package"/*.deb payload
    test -f payload/usr/lib/systemd/system/example.service
    install_event() { sh scripts/postinst configure; }
    upgrade_event() { sh scripts/postinst configure 1.0; }
    before_remove() { sh scripts/prerm remove; }
    after_remove() { sh scripts/postrm remove; }
    skipped_events() {
      sh scripts/prerm upgrade 2.0
      sh scripts/prerm deconfigure
      sh scripts/postinst abort-upgrade
      sh scripts/postrm upgrade 2.0
      sh scripts/postrm abort-install
    }
    boot=deb-systemd-helper
    runtime=deb-systemd-invoke
    ;;
  dnf)
    mkdir scripts
    rpm -qp --qf '%{POSTIN}' "$package"/*.rpm > scripts/postinst
    rpm -qp --qf '%{PREUN}' "$package"/*.rpm > scripts/prerm
    rpm -qp --qf '%{POSTUN}' "$package"/*.rpm > scripts/postrm
    install_event() { sh scripts/postinst 1; }
    upgrade_event() { sh scripts/postinst 2; }
    before_remove() { sh scripts/prerm 0; }
    after_remove() { sh scripts/postrm 0; }
    skipped_events() { sh scripts/prerm 1; sh scripts/postrm 1; }
    boot=systemctl
    runtime=systemctl
    ;;
  pacman)
    mkdir scripts
    bsdtar -xOf "$package"/*.pkg.tar.zst .INSTALL > scripts/hooks
    install_event() { sh -c '. scripts/hooks; post_install 1.0'; }
    upgrade_event() { sh -c '. scripts/hooks; post_upgrade 2.0 1.0'; }
    before_remove() { sh -c '. scripts/hooks; pre_remove 1.0'; }
    after_remove() { sh -c '. scripts/hooks; post_remove 1.0'; }
    skipped_events() { :; }
    boot=systemctl
    runtime=systemctl
    ;;
esac
for script in scripts/*; do sh -n "$script"; done

# Redirect only the runtime-directory guard to simulate online/offline roots.
# Every service tool is a stub; these tests never touch host units or /etc.
for script in scripts/*; do
  sed "s|/run/systemd/system|$PWD/manager|g" "$script" > rewritten
  mv rewritten "$script"
done
mkdir manager
: > "$CALLS"
install_event
grep -Fx "$boot:enable example.service" "$CALLS"
grep -Fx "$runtime:start example.service leave-running.service" "$CALLS"
test "$(grep -n '^update-ca-' "$CALLS" | cut -d : -f 1)" \
  -lt "$(grep -n "^$runtime:start " "$CALLS" | cut -d : -f 1)"
test "$(tail -n 1 "$CALLS")" = custom:install
if grep -q 'manual.service\|source-only.service' "$CALLS"; then exit 1; fi

: > "$CALLS"
upgrade_event
if grep -q ':enable\|:start\|:restart ' "$CALLS"; then exit 1; fi
test "$(tail -n 1 "$CALLS")" = custom:upgrade
export ACTIVE=yes
: > "$CALLS"
upgrade_event
if [ "$format" = apt ]; then
  grep -Fx "$runtime:restart example.service" "$CALLS"
else
  grep -Fx 'systemctl:try-restart example.service' "$CALLS"
fi
if grep -q ':enable\|:start' "$CALLS"; then exit 1; fi

: > "$CALLS"
before_remove
grep -Fx "$runtime:stop example.service" "$CALLS"
grep -Fx "$boot:disable example.service" "$CALLS"
test "$(tail -n 1 "$CALLS")" = custom:before-remove
if grep -q leave-running "$CALLS"; then exit 1; fi
after_remove
test "$(tail -n 1 "$CALLS")" = custom:after-remove

: > "$CALLS"
skipped_events
test ! -s "$CALLS"
if [ "$format" = apt ]; then
  sh scripts/postrm purge
  grep -Fx 'deb-systemd-helper:purge example.service' "$CALLS"
  test "$(tail -n 1 "$CALLS")" = custom:after-purge
fi

export FAIL_ACTIONS=yes
install_event
upgrade_event
before_remove
export FAIL_ACTIONS=no
mv manager offline
: > "$CALLS"
install_event
grep -Fx "$boot:enable example.service" "$CALLS"
upgrade_event
before_remove
after_remove
if grep -q ':start\|:stop\|:restart\|:try-restart\|:daemon-reload\|:is-active' "$CALLS"; then exit 1; fi

if [ "$format" = pacman ]; then
  mkdir manager
  : > "$CALLS"
  sh -c '. scripts/hooks; post_install 1.0; post_upgrade 2.0 1.0'
  test "$(grep -c '^custom:install$' "$CALLS")" = 1
  test "$(grep -c '^custom:upgrade$' "$CALLS")" = 1
fi
