{ stdenv }:
assert stdenv.hostPlatform.system == "aarch64-linux";
stdenv.mkDerivation {
  name = "arm-only";
  dontUnpack = true;
  installPhase = "mkdir -p $out";
  meta.platforms = import ./systems.nix;
}
