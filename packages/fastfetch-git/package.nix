{ metarepo, callPackage, fetchurl }:
let
  build = callPackage ../fastfetch/build.nix { pname = "fastfetch-git"; };
in
metarepo.mkSnapshots {
  snapshots = import ./snapshots.nix;
  default = "dev_73e61c2";
  inherit build;
  source = snapshot: fetchurl {
    url = "https://codeload.github.com/fastfetch-cli/fastfetch/tar.gz/${snapshot.rev}";
    name = "fastfetch-${snapshot.rev}.tar.gz";
    inherit (snapshot) hash;
  };
}
