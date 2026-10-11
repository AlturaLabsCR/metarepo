/**
  Build a Debian .deb artifact directly, bypassing declarative integrations.
  Prefer `mkPackage` to infer certificate/systemd dependencies and actions.

  # Type

  ```
  mkApt :: AttrSet -> Derivation
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
  metarepo.mkApt {
    name = "example";
    version = "1.0";
    architecture = "all";
    inherit payload;
    description = "Example package";
    homepage = "https://example.org";
    maintainer = "Example Authors <hello@example.org>";
    license = "MIT";
  }
  # Produces "$out/example_1.0-1_all.deb".
  ```
*/
{
  lib,
  runCommand,
  dpkg,
  writeText,
}:
{
  name,
  version,
  payload,
  architecture,
  description,
  homepage,
  maintainer,
  depends ? [ ],
  license,
  recommends ? [ ],
  release ? "1",
  hooks ? { },
  conflicts ? [ ],
  provides ? [ ],
}:
let
  control = writeText "control" (
    lib.concatStringsSep "\n" (
      [
        "Package: ${name}"
        "Version: ${version}-${release}"
        "Architecture: ${architecture}"
        "Maintainer: ${maintainer}"
        "Section: utils"
        "Priority: optional"
      ]
      ++ lib.optional (depends != [ ]) "Depends: ${lib.concatStringsSep ", " depends}"
      ++ lib.optional (recommends != [ ]) "Recommends: ${lib.concatStringsSep ", " recommends}"
      ++ lib.optional (conflicts != [ ]) "Conflicts: ${lib.concatStringsSep ", " conflicts}"
      ++ lib.optional (provides != [ ]) "Provides: ${lib.concatStringsSep ", " provides}"
      ++ [
        "Homepage: ${homepage}"
        "Description: ${description}"
        ""
      ]
    )
  );
  hookScripts =
    lib.mapAttrs (event: script: writeText event ("#!/bin/sh\nset -eu\n" + script + "\n"))
      {
        postinst = ''
          if [ "$1" = configure ]; then
            ${hooks.postInstall or ""}
            :
          fi
        '';
        postrm = ''
          case "$1" in remove|purge)
            ${hooks.postRemove or ""}
            : ;;
          esac
        '';
      };
  scripts = lib.filterAttrs (
    event: _: (hooks.${if event == "postinst" then "postInstall" else "postRemove"} or "") != ""
  ) hookScripts;
in
runCommand "${name}-deb-${version}"
  {
    nativeBuildInputs = [ dpkg ];
    passthru.metarepo = {
      format = "apt";
      inherit architecture;
    };
  }
  ''
    cp -R ${payload} root
    chmod -R u+w root
    mkdir -p root/DEBIAN "$out"
    cp ${control} root/DEBIAN/control
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (event: script: ''
        cp ${script} root/DEBIAN/${event}
        chmod 755 root/DEBIAN/${event}
      '') scripts
    )}
    dpkg-deb --root-owner-group --build root "$out/${name}_${version}-${release}_${architecture}.deb"
  ''
