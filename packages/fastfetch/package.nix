{ metarepo, callPackage, fetchurl }:
let
  build = callPackage ../fastfetch/build.nix { pname = "fastfetch"; };
in
metarepo.mkSnapshots {
  snapshots = import ./snapshots.nix;
  default = "v2_26_1";
  inherit build;
  source = snapshot: fetchurl {
    url = "https://codeload.github.com/fastfetch-cli/fastfetch/tar.gz/${snapshot.rev}";
    name = "fastfetch-${snapshot.rev}.tar.gz";
    inherit (snapshot) hash;
  };
}
