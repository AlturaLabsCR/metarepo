/**
  Build named snapshots and return the selected default package.
  Attach every built package under `passthru.snapshots`, and attach each
  snapshot's native publication options under `passthru.publication`.
  Existing passthru attributes are preserved.

  # Type

  ```
  mkSnapshots :: AttrSet -> Derivation
  ```

  # Inputs

  `snapshots`
  : Attribute set of snapshot records. Records contain source fields such as
    `rev` and `hash`, arbitrary build options, and optional `publication`.

  `default`
  : Name of the snapshot returned for Nix users. Must exist in `snapshots`.

  `source`
  : Function receiving the entire snapshot record and returning its source.

  `build`
  : Function receiving the snapshot minus `rev`, `hash` and `publication`,
    plus `src = source snapshot`. Must return a derivation with `overrideAttrs`.

  # Examples

  ```nix
  metarepo.mkSnapshots {
    snapshots.release = { version = "1.0"; rev = "immutable-commit"; hash = sourceHash; };
    default = "release";
    source = snapshot: fetchurl {
      url = "https://example.org/archive/${snapshot.rev}.tar.gz";
      inherit (snapshot) hash;
    };
    build = { version, src }: stdenv.mkDerivation {
      pname = "example";
      inherit version src;
    };
  }
  ```
*/
{ lib }:
{
  snapshots,
  default,
  source,
  build,
}:
let
  packages = lib.mapAttrs (
    _: snapshot:
    (build (
      builtins.removeAttrs snapshot [
        "rev"
        "hash"
        "publication"
      ]
      // {
        src = source snapshot;
      }
    )).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          publication = snapshot.publication or { };
        };
      })
  ) snapshots;
in
assert lib.assertMsg (builtins.hasAttr default packages)
  "metarepo: unknown default snapshot '${default}'";
packages.${default}.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    snapshots = packages;
  };
})
