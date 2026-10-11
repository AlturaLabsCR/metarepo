/**
  Discover packages and publications using the `packages/<name>` convention.
  Each package needs `package.nix` and a `systems.nix` list. An optional
  `public.nix` receives `package`, `metarepo`, `repository` and Nixpkgs dependencies.
  Only packages declared for a system are evaluated on that system.

  Return an attribute set indexed by system, suitable for a flake's `packages`.
  Systems with publications also export `build-public`. An empty directory
  returns `{ }` without evaluating Nixpkgs or repository configuration.

  # Type

  ```
  mkPackages :: AttrSet -> AttrSet
  ```

  # Inputs

  `packagesDir`
  : Path to package directories. `build-public` is a reserved package name.

  `repository`
  : Repository identity and channels; see `mkPublic`.

  `pkgsFor`
  : Optional function from system name to package set. Defaults to the input's
    `nixpkgs.legacyPackages`.

  `documentation`
  : Optional documentation directory, or function from package set to directory.
    Defaults to `null`. Its contents are published under `public/doc`.

  # Examples

  ```nix
  packages = metarepo.lib.mkPackages {
    packagesDir = ./packages;
    repository = import ./repository.nix;
    pkgsFor = system: import nixpkgs { inherit system; overlays = [ myOverlay ]; };
  };
  ```
*/
{
  lib,
  nixpkgs,
  forPkgs,
}:
{
  packagesDir,
  repository,
  pkgsFor ? (system: nixpkgs.legacyPackages.${system}),
  documentation ? null,
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
    packageScope = pkgs // {
      inherit metarepo;
    };
    available = lib.filterAttrs (_: systems: builtins.elem system systems) packageSystems;
    packages = lib.mapAttrs (
      name: _: lib.callPackageWith packageScope (packagesDir + "/${name}/package.nix") { }
    ) available;
    publicNames = lib.filter (name: builtins.pathExists (packagesDir + "/${name}/public.nix")) (
      builtins.attrNames packages
    );
    publications = map (
      name:
      lib.callPackageWith (
        packageScope
        // {
          inherit repository;
          package = packages.${name};
        }
      ) (packagesDir + "/${name}/public.nix") { }
    ) publicNames;
    public = metarepo.mkPublic {
      inherit publications repository;
      documentation = if builtins.isFunction documentation then documentation pkgs else documentation;
    };
  in
  assert lib.assertMsg (
    !(packages ? build-public)
  ) "metarepo: build-public is reserved for the repository builder";
  packages // lib.optionalAttrs (publicNames != [ ]) { build-public = public.builder; }
)
