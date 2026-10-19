{ pkgs, api }:
let
  payload = pkgs.writeTextDir "tool.exe" "payload fixture, not a Windows executable";
  build =
    name:
    api.mkMsiInstaller {
      inherit name payload;
      version = "1.2.3+git";
      family = "example";
      manufacturer = "Tests";
      launcher = "tool.exe";
      registry = [
        {
          key = "Software\\Tests\\Example";
          name = "Path";
          value = "[INSTALLDIR]tool.exe";
        }
      ];
    };
  first = build "example";
  second = build "example-git";
in
assert
  !(builtins.tryEval
    (api.mkMsiInstaller {
      name = "bad/path";
      version = "1.2.3";
      inherit payload;
    }).drvPath
  ).success;
assert
  !(builtins.tryEval
    (api.mkMsiInstaller {
      name = "example";
      version = "bad";
      inherit payload;
    }).drvPath
  ).success;
pkgs.runCommand "msi-installer-tests" { nativeBuildInputs = [ pkgs.msitools ]; } ''
  msiextract -C extracted ${first}
  find extracted -name tool.exe -exec cmp '{}' ${payload}/tool.exe \;
  test "$(find extracted -name tool.exe | wc -l)" = 1
  msiinfo export ${first} Property > first.tsv
  msiinfo export ${second} Property > second.tsv
  grep -F $'ProductVersion\t1.2.3' first.tsv
  grep -F $'ALLUSERS\t1' first.tsv
  grep '^UpgradeCode' first.tsv > first-upgrade
  grep '^UpgradeCode' second.tsv > second-upgrade
  cmp first-upgrade second-upgrade
  if cmp -s first.tsv second.tsv; then exit 1; fi
  msiinfo export ${first} Registry | grep -F 'Software\Tests\Example'
  msiinfo export ${first} Shortcut | grep -F '[INSTALLDIR]tool.exe'
  touch "$out"
''
