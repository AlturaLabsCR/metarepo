{ lib }:
# source receives rev/hash; build receives the snapshot's build options and src.
{ snapshots, default, source, build }:
let
  packages = lib.mapAttrs (_: snapshot:
    (build (builtins.removeAttrs snapshot [ "rev" "hash" "publication" ] // {
      src = source snapshot;
    })).overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        publication = snapshot.publication or { };
      };
    })
  ) snapshots;
in
assert lib.assertMsg (builtins.hasAttr default packages) "metarepo: unknown default snapshot '${default}'";
packages.${default}.overrideAttrs (old: {
  passthru = (old.passthru or { }) // { snapshots = packages; };
})
