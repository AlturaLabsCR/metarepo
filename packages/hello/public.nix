{
  callPackage,
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
  };
  deb = callPackage ../../lib/mk-deb.nix { } (
    common
    // {
      architecture = package.passthru.packageArchitectures.deb;
      depends = [ ];
      maintainer = "Hello Example Authors <hello@example.invalid>";
    }
  );
  dnf = callPackage ../../lib/mk-rpm.nix { } (
    common
    // {
      architecture = package.passthru.packageArchitectures.dnf;
      depends = [ ];
    }
  );
  arch = callPackage ../../lib/mk-arch.nix { } (
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
