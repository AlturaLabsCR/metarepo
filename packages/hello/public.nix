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
  packages = lib.mapAttrs (
    format: builder:
    builder (
      common
      // {
        architecture = package.passthru.packageArchitectures.${format};
        depends = dependencies.${format};
      }
    )
  ) builders;
in
{
  channels = {
    jammy = {
      releases = [ "ubuntu2204" ];
      package = packages.apt;
    };
    noble = {
      releases = [
        "ubuntu2404"
        "ubuntu2604"
        "debian13"
        "linuxmint7"
      ];
      package = packages.apt;
    };
    fedora = {
      releases = [ "fedora44" ];
      package = packages.dnf;
    };
    arch = {
      releases = [ "arch" ];
      package = packages.pacman;
    };
  };
}
