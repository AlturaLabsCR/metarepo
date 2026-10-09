{
  lib,
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
  builders = {
    apt = metarepo.mkApt;
    dnf = metarepo.mkDnf;
    pacman = metarepo.mkPacman;
  };
  dependencies = {
    apt = [ ];
    dnf = [ ];
    pacman = [ ];
  };
  recommendations = {
    apt = [ ];
    dnf = [ ];
    pacman = [ ];
  };
  packages = lib.mapAttrs (
    format: builder:
    builder (
      common
      // {
        architecture = package.passthru.packageArchitectures.${format};
        depends = dependencies.${format};
        recommends = recommendations.${format};
      }
    )
  ) builders;
in
{
  channels = {
    jammy.package = packages.apt;
    noble.package = packages.apt;
    fedora.package = packages.dnf;
    arch.package = packages.pacman;
  };
}
