{
  metarepo,
  runCommand,
  package,
}:
let
  payload = runCommand "metarepo-hello-python-payload" { } ''
    mkdir -p "$out/usr/bin" "$out/usr/lib/metarepo-hello-python/hello_python" "$out/usr/share/licenses/metarepo-hello-python"
    cp ${./src/hello_python/__init__.py} "$out/usr/lib/metarepo-hello-python/hello_python/__init__.py"
    cp ${./LICENSE} "$out/usr/share/licenses/metarepo-hello-python/LICENSE"
    cp ${./launcher.sh} "$out/usr/bin/metarepo-hello-python"
    chmod 755 "$out/usr/bin/metarepo-hello-python"
    chmod 644 "$out/usr/lib/metarepo-hello-python/hello_python/__init__.py" "$out/usr/share/licenses/metarepo-hello-python/LICENSE"
  '';
  common = {
    inherit payload;
    name = package.pname;
    inherit (package) version;
    inherit (package.meta) description homepage;
    license = package.meta.license.spdxId;
    maintainer = "Hello Python Authors <hello-python@example.invalid>";
  };
  apt = metarepo.mkApt (
    common
    // {
      architecture = package.passthru.packageArchitectures.apt;
      depends = [ "python3" ];
    }
  );
  dnf = metarepo.mkDnf (
    common
    // {
      architecture = package.passthru.packageArchitectures.dnf;
      depends = [ "python3" ];
    }
  );
  pacman = metarepo.mkPacman (
    common
    // {
      architecture = package.passthru.packageArchitectures.pacman;
      depends = [ "python" ];
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
