{
  callPackage,
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
  deb = callPackage ../../lib/mk-deb.nix { } (
    common
    // {
      architecture = package.passthru.packageArchitectures.deb;
      depends = [ "python3" ];
    }
  );
  dnf = callPackage ../../lib/mk-rpm.nix { } (
    common
    // {
      architecture = package.passthru.packageArchitectures.dnf;
      depends = [ "python3" ];
    }
  );
  arch = callPackage ../../lib/mk-arch.nix { } (
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
      format = "apt";
      package = deb;
      architecture = package.passthru.packageArchitectures.deb;
    };
    noble = {
      format = "apt";
      package = deb;
      architecture = package.passthru.packageArchitectures.deb;
    };
    fedora = {
      format = "dnf";
      package = dnf;
      architecture = package.passthru.packageArchitectures.dnf;
    };
    arch = {
      format = "pacman";
      package = arch;
      architecture = package.passthru.packageArchitectures.pacman;
    };
  };
}
