{ pkgs, api, repository }:
let
  snapshots = api.mkSnapshots {
    default = "new";
    snapshots = {
      old = { version = "1.0"; rev = "old"; publication.depends = [ "old-dependency" ]; };
      new = { version = "2.0"; rev = "new"; publication.depends = [ "new-dependency" ]; };
    };
    source = snapshot: pkgs.writeText "source" snapshot.rev;
    build = { version, src }: pkgs.runCommand "snapshot-${version}" {
      pname = "snapshot";
      inherit version src;
      meta = {
        description = "Snapshot test";
        homepage = "https://example.invalid";
        license = pkgs.lib.licenses.mit;
      };
    } "touch $out";
  };
  publication = api.mkPublication {
    inherit repository;
    package = snapshots;
    payload = package: package;
    independent = true;
    maintainer = "Test";
    channels = [ "stable" "next" ];
    formats.apt.recommends = [ "optional" ];
    overrides.next.release = "2";
  };
  public = api.mkPublic { inherit repository; publications = [ publication ]; };
in
assert snapshots.version == "2.0";
assert snapshots.passthru.snapshots.old.version == "1.0";
assert snapshots.passthru.snapshots.old.passthru.publication.depends == [ "old-dependency" ];
assert builtins.attrNames publication.channels == [ "next" "stable" ];
assert builtins.length publication.channels.stable == 2;
assert (builtins.head publication.channels.stable).passthru.metarepo.architecture == "all";
assert (builtins.head publication.channels.next).passthru.metarepo.format == "dnf";
assert builtins.isString public.drvPath;
assert !(builtins.tryEval (api.mkPackage { format = "unknown"; }).drvPath).success;
assert !(builtins.tryEval (api.mkPackage { format = "apt"; hooks.invalid = "true"; }).drvPath).success;
true
