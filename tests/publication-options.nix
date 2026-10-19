{ pkgs, api }:
let
  inherit (pkgs) lib;
  repository = {
    id = "test";
    origin = "Tests";
    label = "Tests";
    url = "https://example.invalid";
    channels = {
      base.format = "apt";
      alias = {
        format = "apt";
        inherits = "base";
      };
      nested = {
        format = "apt";
        inherits = "alias";
      };
      rpm.format = "dnf";
    };
  };
  make =
    version: publication:
    pkgs.runCommand "publication-fixture-${version}" {
      pname = "example";
      inherit version;
      meta = {
        description = "Example";
        homepage = "https://example.invalid";
        license = lib.licenses.mit;
      };
      passthru.publication = publication;
    } "mkdir -p $out";
  old = make "1.0" {
    channels = [ "base" ];
    independent = true;
    release = "2";
    formats.apt.depends = [ "old-dependency" ];
  };
  new = make "2.0" {
    channels = [ "rpm" ];
    independent = false;
    formats.dnf.depends = [ "new-dependency" ];
  };
  collection = old.overrideAttrs (previous: {
    passthru = previous.passthru // {
      snapshots = { inherit old new; };
    };
  });
  publication = api.mkPublication {
    inherit repository;
    package = collection;
    maintainer = "Tests";
  };
  customized = api.mkPublication {
    inherit repository;
    package = old;
    maintainer = "Tests";
    snapshotOptions = snapshot: {
      channels = [
        "base"
        "alias"
      ];
      release = "3";
      formats = package: {
        apt = {
          release = "4";
          description = package.version;
        };
      };
      overrides = package: { alias.release = "5"; };
    };
  };
  aliasOnly = api.mkPublication {
    inherit repository;
    package = make "3.0" { };
    maintainer = "Tests";
    channels = [ "alias" ];
    independent = true;
  };
  invalid =
    channels:
    builtins.tryEval
      (api.mkPublication {
        repository.channels = channels;
        package = old;
        maintainer = "Tests";
      }).channels;
  path = channel: (builtins.head publication.channels.${channel}).drvPath;
in
assert
  builtins.attrNames publication.channels == [
    "alias"
    "base"
    "nested"
    "rpm"
  ];
assert lib.all (channel: builtins.length publication.channels.${channel} == 1) [
  "base"
  "alias"
  "nested"
  "rpm"
];
assert path "base" == path "alias" && path "alias" == path "nested";
assert (builtins.head publication.channels.base).passthru.metarepo.architecture == "all";
assert
  (builtins.head publication.channels.rpm).passthru.metarepo.architecture
  == pkgs.stdenv.hostPlatform.uname.processor;
assert
  (builtins.head customized.channels.base).drvPath != (builtins.head customized.channels.alias)
  .drvPath;
assert
  (builtins.head customized.channels.alias).drvPath == (builtins.head customized.channels.nested)
  .drvPath;
assert
  builtins.attrNames aliasOnly.channels == [
    "alias"
    "nested"
  ];
assert
  !(invalid {
    base = {
      format = "apt";
      inherits = "missing";
    };
  }).success;
assert
  !(invalid {
    base = {
      format = "apt";
      inherits = "base";
    };
  }).success;
assert
  !(invalid {
    base = {
      format = "apt";
      inherits = "alias";
    };
    alias = {
      format = "apt";
      inherits = "base";
    };
  }).success;
assert
  !(invalid {
    base.format = "apt";
    alias = {
      format = "dnf";
      inherits = "base";
    };
  }).success;
# Compare complete derivations with the original flat API, not implementation fields.
assert
  path "base" == (api.mkPackage {
    format = "apt";
    name = "example";
    version = "1.0";
    architecture = "all";
    release = "2";
    description = "Example";
    homepage = "https://example.invalid";
    license = "MIT";
    maintainer = "Tests";
    depends = [ "old-dependency" ];
  }).drvPath;
pkgs.runCommand "snapshot-publication-options-tests" { nativeBuildInputs = [ pkgs.dpkg ]; } ''
  dpkg-deb -f ${builtins.head customized.channels.base}/*.deb Version | grep -Fx 1.0-4
  dpkg-deb -f ${builtins.head customized.channels.alias}/*.deb Version | grep -Fx 1.0-5
  dpkg-deb -f ${builtins.head publication.channels.base}/*.deb Depends | grep -Fx old-dependency
  touch "$out"
''
