{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      metarepo = import ./lib { inherit nixpkgs; };
      documentation = pkgs: pkgs.callPackage ./doc { };
      discovered = metarepo.mkPackages {
        packagesDir = ./packages;
        repository = import ./repository.nix;
        inherit documentation;
      };
      packages = nixpkgs.lib.mapAttrs (
        system: packages:
        packages
        // {
          docs = documentation nixpkgs.legacyPackages.${system};
        }
      ) discovered;
    in
    {
      lib = metarepo;
      inherit packages;
      formatter = nixpkgs.lib.mapAttrs (system: _: nixpkgs.legacyPackages.${system}.nixfmt-tree) packages;
      checks = nixpkgs.lib.mapAttrs (
        system: _:
        import ./tests {
          inherit metarepo;
          documentation = packages.${system}.docs;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      ) packages;
    };
}
