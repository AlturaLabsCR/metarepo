{
  lib,
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
  builders = {
    apt = metarepo.mkApt;
    dnf = metarepo.mkDnf;
    pacman = metarepo.mkPacman;
  };
  dependencies = {
    apt = [ "python3" ];
    dnf = [ "python3" ];
    pacman = [ "python" ];
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
