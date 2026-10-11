/**
  Build a RPM .rpm artifact directly, bypassing declarative integrations.
  Prefer `mkPackage` to infer certificate/systemd dependencies and actions.

  # Type

  ```
  mkDnf :: AttrSet -> Derivation
  ```

  # Inputs

  `name`, `version`, `payload`, `architecture`, `description`, `homepage`, `maintainer`, `license`
  : Required native package inputs, as documented in `mkPackage`.
    Here `payload` is required.

  `depends`, `recommends`, `conflicts`, `provides`
  : Optional package-manager dependency lists; each defaults to `[ ]`.

  `release`, `hooks`
  : Native revision (default `"1"`) and installation/removal scripts
    (default `{ }`), as documented in `mkPackage`.

  Return a directory containing the artifact and `passthru.metarepo` metadata.
  Only native metadata and filesystem content are packaged.

  # Examples

  ```nix
  metarepo.mkDnf {
    name = "example";
    version = "1.0";
    architecture = "noarch";
    inherit payload;
    description = "Example package";
    homepage = "https://example.org";
    maintainer = "Example Authors <hello@example.org>";
    license = "MIT";
  }
  # Produces "$out/example-1.0-1.noarch.rpm".
  ```
*/
{
  lib,
  runCommand,
  rpm,
  writeText,
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
  spec = writeText "${name}.spec" ''
    Name: ${name}
    Version: ${version}
    Release: ${release}
    Summary: ${description}
    License: ${license}
    URL: ${homepage}
    Packager: ${maintainer}
    BuildArch: ${architecture}
    AutoReqProv: no
    ${lib.concatMapStringsSep "\n" (dep: "Requires: ${dep}") depends}
    ${lib.concatMapStringsSep "\n" (dep: "Recommends: ${dep}") recommends}

    ${lib.concatMapStringsSep "\n" (dep: "Conflicts: ${dep}") conflicts}
    ${lib.concatMapStringsSep "\n" (dep: "Provides: ${dep}") provides}

    %description
    ${description}

    %install
    mkdir -p %{buildroot}
    cp -R ${payload}/. %{buildroot}/

    %files -f %{_topdir}/filelist

    ${lib.optionalString ((hooks.postInstall or "") != "") ("%post\n" + hooks.postInstall)}
    ${lib.optionalString ((hooks.postRemove or "") != "") ("%postun\n" + hooks.postRemove)}
  '';
in
runCommand "${name}-rpm-${version}"
  {
    nativeBuildInputs = [ rpm ];
    passthru.metarepo = {
      format = "dnf";
      inherit architecture;
    };
  }
  ''
    mkdir -p "$out"
    mkdir -p "$TMPDIR/rpmbuild"
    find ${payload} \( -type f -o -type l \) -print \
      | sed 's|^${payload}||' \
      | while IFS= read -r path; do
          case "$path" in
            /usr/share/licenses/${name}/*) printf '%%license %s\n' "$path" ;;
            *) printf '%s\n' "$path" ;;
          esac
        done > "$TMPDIR/rpmbuild/filelist"
    rpmbuild -bb ${spec} \
      --define "_topdir $TMPDIR/rpmbuild" \
      --define "_tmppath $TMPDIR" \
      --define "_dbpath $TMPDIR/rpmdb" \
      --define "_rpmdir $out" \
      --define '_build_id_links none' \
      --define '__os_install_post %{nil}'
    rpm_file="$(find "$out" -type f -name '*.rpm' -print -quit)"
    test -n "$rpm_file"
    rpm_dir="''${rpm_file%/*}"
    mv "$rpm_file" "$out/"
    rmdir "$rpm_dir"
  ''
