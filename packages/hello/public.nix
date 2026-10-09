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
  apt = metarepo.mkApt (
    common
    // {
      architecture = package.passthru.packageArchitectures.apt;
      depends = [ ];
    }
  );
  dnf = metarepo.mkDnf (
    common
    // {
      architecture = package.passthru.packageArchitectures.dnf;
      depends = [ ];
    }
  );
  pacman = metarepo.mkPacman (
    common
    // {
      architecture = package.passthru.packageArchitectures.pacman;
      depends = [ ];
    }
  );
in
{
  channels = {
    jammy = {
      releases = [ "ubuntu2204" ];
      package = apt;
    };
    noble = {
      releases = [
        "ubuntu2404"
        "ubuntu2604"
        "debian13"
        "linuxmint7"
      ];
      package = apt;
    };
    fedora = {
      releases = [ "fedora44" ];
      package = dnf;
    };
    arch = {
      releases = [ "arch" ];
      package = pacman;
    };
  };
}
