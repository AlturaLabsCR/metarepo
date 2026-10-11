{ metarepo, repository, package }:
metarepo.mkPublication {
  inherit repository package;
  payload = package: metarepo.mkPayload { inherit package; };
  maintainer = "Example Authors <hello@example.invalid>";
  conflicts = [ "fastfetch" ];
  provides = [ "fastfetch" ];
}
