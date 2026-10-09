{ stdenv }:
assert stdenv.hostPlatform.system == "x86_64-linux";
stdenv.mkDerivation {
  name = "x86-only";
  dontUnpack = true;
  installPhase = "mkdir -p $out";
  meta.platforms = import ./systems.nix;
}
