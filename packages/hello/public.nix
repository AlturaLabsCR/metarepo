{
  metarepo,
  runCommand,
  package,
}:
let
  payload = runCommand "metarepo-hello-c-payload" { } ''
    mkdir -p "$out/usr/bin" "$out/usr/share/licenses/metarepo-hello-c"
    cp ${package}/bin/metarepo-hello-c "$out/usr/bin/metarepo-hello-c"
    cp ${./LICENSE} "$out/usr/share/licenses/metarepo-hello-c/LICENSE"
    chmod 755 "$out/usr/bin/metarepo-hello-c"
    chmod 644 "$out/usr/share/licenses/metarepo-hello-c/LICENSE"
  '';
  common = {
    inherit payload;
    name = package.pname;
    inherit (package) version;
    inherit (package.meta) description homepage;
    license = package.meta.license.spdxId;
    maintainer = "Hello Example Authors <hello@example.invalid>";
  };
  architectures = package.passthru.packageArchitectures;
  apt = metarepo.mkApt (common // {
    architecture = architectures.apt;
  });
  dnf = metarepo.mkDnf (common // {
    architecture = architectures.dnf;
  });
  pacman = metarepo.mkPacman (common // {
    architecture = architectures.pacman;
  });
in
{
  channels = {
    jammy = apt;
    noble = apt;
    fedora = dnf;
    arch = pacman;
  };
}
