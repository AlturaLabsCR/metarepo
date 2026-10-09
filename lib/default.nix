{ nixpkgs }:
let
  lib = nixpkgs.lib;
in
rec {
  # Bind the builders to the consumer's package set (including its overlays).
  forPkgs = pkgs: {
    mkApt = pkgs.callPackage ./mk-apt.nix { };
    mkDnf = pkgs.callPackage ./mk-dnf.nix { };
    mkPacman = pkgs.callPackage ./mk-pacman.nix { };
    mkPublic = pkgs.callPackage ./mk-public.nix { };
  };

  # Convenience API for projects following the packages/<name> convention.
  # systems.nix declares availability without evaluating a derivation.
  # public.nix is optional.
  mkPackages =
    {
      packagesDir,
      repository,
      pkgsFor ? (system: nixpkgs.legacyPackages.${system}),
    }:
    let
      directories = lib.filterAttrs (
        name: type: type == "directory" && builtins.pathExists (packagesDir + "/${name}/package.nix")
      ) (builtins.readDir packagesDir);
      packageSystems = lib.mapAttrs (name: _: import (packagesDir + "/${name}/systems.nix")) directories;
      systems = lib.unique (lib.concatLists (builtins.attrValues packageSystems));
    in
    lib.genAttrs systems (
      system:
      let
        pkgs = pkgsFor system;
        metarepo = forPkgs pkgs;
        available = lib.filterAttrs (_: systems: builtins.elem system systems) packageSystems;
        packages = lib.mapAttrs (
          name: _: pkgs.callPackage (packagesDir + "/${name}/package.nix") { }
        ) available;
        publicNames = lib.filter (name: builtins.pathExists (packagesDir + "/${name}/public.nix")) (
          builtins.attrNames packages
        );
        publications = map (
          name:
          pkgs.callPackage (packagesDir + "/${name}/public.nix") {
            inherit metarepo;
            package = packages.${name};
          }
        ) publicNames;
        public = metarepo.mkPublic { inherit publications repository; };
      in
      assert lib.assertMsg (
        !(packages ? build-public)
      ) "metarepo: build-public is reserved for the repository builder";
      packages // lib.optionalAttrs (publicNames != [ ]) { build-public = public.builder; }
    );
}
