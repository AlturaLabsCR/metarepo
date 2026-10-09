{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      metarepo = import ./lib { inherit nixpkgs; };
      packages = metarepo.mkPackages {
        packagesDir = ./packages;
        repository = import ./repository.nix;
      };
    in
    {
      lib = metarepo;
      inherit packages;
      checks = nixpkgs.lib.mapAttrs (
        system: _:
        import ./tests {
          inherit metarepo;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      ) packages;
    };
}
