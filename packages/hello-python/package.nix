{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "metarepo-hello-python";
  version = "0.1.0";
  pyproject = true;
  src = ./.;
  build-system = [ python3Packages.hatchling ];
  meta = {
    description = "A minimal Python example managed with uv";
    homepage = "https://example.org/";
    license = lib.licenses.mit;
    mainProgram = "metarepo-hello-python";
    platforms = import ./systems.nix;
  };
  passthru.packageArchitectures = {
    apt = "all";
    dnf = "noarch";
    pacman = "any";
  };
}
