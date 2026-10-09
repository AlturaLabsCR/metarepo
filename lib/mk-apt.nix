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
  depends,
  license,
  release ? "1",
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
      ++ [
        "Homepage: ${homepage}"
        "Description: ${description}"
        ""
      ]
    )
  );
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
    dpkg-deb --root-owner-group --build root "$out/${name}_${version}-${release}_${architecture}.deb"
  ''
