{
  metarepo,
  repository,
  runCommand,
  package,
}:
let
  payload = runCommand "metarepo-hello-python-payload" { } ''
    mkdir -p "$out/usr/bin" "$out/usr/lib/metarepo-hello-python/hello_python" "$out/usr/share/licenses/metarepo-hello-python"
    cp ${./src/hello_python/__init__.py} "$out/usr/lib/metarepo-hello-python/hello_python/__init__.py"
    cp ${./LICENSE} "$out/usr/share/licenses/metarepo-hello-python/LICENSE"
    cp ${./launcher.sh} "$out/usr/bin/metarepo-hello-python"
    chmod 755 "$out/usr/bin/metarepo-hello-python"
    chmod 644 "$out/usr/lib/metarepo-hello-python/hello_python/__init__.py" "$out/usr/share/licenses/metarepo-hello-python/LICENSE"
  '';
in
metarepo.mkPublication {
  inherit repository package payload;
  maintainer = "Example Authors <hello@example.invalid>";
  independent = true;
  formats = {
    apt.depends = [ "python3" ];
    dnf.depends = [ "python3" ];
    pacman.depends = [ "python" ];
  };
}
