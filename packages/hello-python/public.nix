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
  architectures = package.passthru.packageArchitectures;
  apt = metarepo.mkApt (common // {
    architecture = architectures.apt;
    depends = [ "python3" ];
  });
  dnf = metarepo.mkDnf (common // {
    architecture = architectures.dnf;
    depends = [ "python3" ];
  });
  pacman = metarepo.mkPacman (common // {
    architecture = architectures.pacman;
    depends = [ "python" ];
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
