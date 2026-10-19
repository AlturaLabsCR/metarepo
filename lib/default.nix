{ nixpkgs }:
let
  lib = nixpkgs.lib;
in
rec {
  /**
    Bind the package and repository builders to a Nixpkgs package set.
    The builders use that set's overlays, configuration and host platform.

    # Type

    ```
    forPkgs :: AttrSet -> AttrSet
    ```

    # Inputs

    `pkgs`
    : A Nixpkgs package set. Native package builders require Linux.

    # Examples

    ```nix
    metarepo = inputs.metarepo.lib.forPkgs pkgs;
    # metarepo.mkPackage, mkPublication, mkPayload, mkSnapshots,
    # mkPublic, mkApt, mkDnf, mkPacman and mkMsi are now available.
    ```
  */
  forPkgs = pkgs: rec {
    mkApt = pkgs.callPackage ./mk-apt.nix { };
    mkDnf = pkgs.callPackage ./mk-dnf.nix { };
    mkPacman = pkgs.callPackage ./mk-pacman.nix { };
    mkMsi = pkgs.callPackage ./mk-msi.nix { };
    mkPublic = pkgs.callPackage ./mk-public.nix { };
    mkPackage = pkgs.callPackage ./mk-package.nix {
      inherit
        mkApt
        mkDnf
        mkPacman
        mkMsi
        ;
    };
    mkPublication = pkgs.callPackage ./mk-publication.nix { inherit mkPackage; };
    mkPayload = pkgs.callPackage ./mk-payload.nix { };
    mkSnapshots = pkgs.callPackage ./mk-snapshots.nix { };
  };

  mkPackages = import ./mk-packages.nix { inherit lib nixpkgs forPkgs; };
}
