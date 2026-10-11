{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "metarepo-hello-c";
  version = "1.0.0";
  src = ./.;
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    "$CC" -std=c99 -O2 -o metarepo-hello-c hello.c
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/licenses/metarepo-hello-c"
    cp metarepo-hello-c "$out/bin/metarepo-hello-c"
    cp ${./LICENSE} "$out/share/licenses/metarepo-hello-c/LICENSE"
    chmod 755 "$out/bin/metarepo-hello-c"
    chmod 644 "$out/share/licenses/metarepo-hello-c/LICENSE"
    runHook postInstall
  '';
  meta = {
    description = "A minimal Hello World example package";
    homepage = "https://example.org/";
    license = lib.licenses.mit;
    mainProgram = "metarepo-hello-c";
    platforms = import ./systems.nix;
  };
}
