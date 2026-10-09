{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      packageDirectories = lib.filterAttrs (
        name: type:
        type == "directory"
        && builtins.pathExists (./packages + "/${name}/package.nix")
        && builtins.pathExists (./packages + "/${name}/public.nix")
      ) (builtins.readDir ./packages);
      packageNames = builtins.attrNames packageDirectories;
      packageFile = name: ./packages + "/${name}/package.nix";
      publicFile = name: ./packages + "/${name}/public.nix";
      packagesFor = pkgs: lib.genAttrs packageNames (name: pkgs.callPackage (packageFile name) { });
      basePackages = packagesFor nixpkgs.legacyPackages.x86_64-linux;
      systems = lib.unique (lib.concatMap (name: basePackages.${name}.meta.platforms) packageNames);
      repository = import ./repository.nix;
    in
    {
      packages = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          packages = packagesFor pkgs;
          publications = map (
            name: pkgs.callPackage (publicFile name) { package = packages.${name}; }
          ) packageNames;
          public = pkgs.callPackage ./lib/mk-public.nix { } {
            inherit publications repository;
          };
        in
        packages
        // {
          build-public = public.builder;
        }
      );
    };
}
