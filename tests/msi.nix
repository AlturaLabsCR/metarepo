{ pkgs, api }:
let
  # A compound-document header fixture, not an installable Windows product.
  installer = pkgs.runCommand "fixture.msi" { } ''
    printf '\320\317\021\340\241\261\032\341fixture' > "$out"
  '';
  artifact =
    version: architecture:
    api.mkPackage {
      format = "msi";
      name = "example";
      inherit version architecture installer;
    };
  repository = {
    id = "test";
    origin = "Test";
    label = "Test Windows repository";
    url = "https://example.invalid/repo's";
    channels.win = {
      format = "msi";
      releases = [ "windows11" ];
    };
  };
  publication = api.mkPublication {
    inherit repository;
    package = pkgs.runCommand "example" {
      pname = "example";
      version = "2.0";
      meta = {
        description = "Example";
        homepage = "https://example.invalid";
        license = pkgs.lib.licenses.mit;
      };
    } "mkdir -p $out";
    formats.msi = {
      inherit installer;
      architecture = "x64";
    };
  };
  public = api.mkPublic {
    inherit repository;
    publications = [
      publication
      {
        channels.win = [
          (artifact "1.0" "x64")
          (artifact "2.0" "arm64")
        ];
      }
    ];
  };
  mixed = api.mkPublic {
    repository = repository // {
      channels = repository.channels // {
        stable = {
          format = "apt";
          releases = [ "example42" ];
        };
      };
    };
    publications = [
      publication
      {
        channels.stable = api.mkPackage {
          format = "apt";
          name = "example-linux";
          version = "1.0";
          architecture = "all";
          description = "Example";
          homepage = "https://example.invalid";
          maintainer = "Tests";
          license = "MIT";
        };
      }
    ];
  };
  invalid =
    options:
    builtins.tryEval
      (api.mkPackage (
        {
          format = "msi";
          name = "example";
          version = "1.0";
          architecture = "x64";
          inherit installer;
        }
        // options
      )).drvPath;
in
assert !(invalid { architecture = "amd64"; }).success;
assert !(invalid { name = "../unsafe"; }).success;
assert !(invalid { depends = [ "linux-only" ]; }).success;
assert !(invalid { hooks.postInstall = "true"; }).success;
assert !(invalid { certificates."test.crt" = installer; }).success;
assert (builtins.head publication.channels.win).passthru.metarepo.format == "msi";
pkgs.runCommand "msi-publication-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 ${./msi.py} ${public} ${installer} ${../lib/msi-catalog.py}
    sh -n ${public}/install.sh
    # MSI selectors must not dispatch to nonexistent shell installer functions.
    if grep -q '_install_msi' ${public}/install.sh; then exit 1; fi
    ${public.builder}/bin/build-public
    diff -r ${public}/win public/win
    cmp ${public}/install.ps1 public/install.ps1
    test -f ${mixed}/apt/dists/stable/Release
    test -f ${mixed}/win/catalog.json
    test -f ${mixed}/install.ps1
    grep -F '_install_apt' ${mixed}/install.sh
    if grep -q '_install_msi' ${mixed}/install.sh; then exit 1; fi
    touch "$out"
  ''
