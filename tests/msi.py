"""Check Linux publication of MSI bytes and generated scripts, not installation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

public, fixture, validator = map(Path, sys.argv[1:])
catalog = json.loads((public / "win/catalog.json").read_text())
assert catalog["schemaVersion"] == 1
assert {(p["version"], p["architecture"]) for p in catalog["packages"]} == {
    ("1.0", "x64"), ("2.0", "x64"), ("2.0", "arm64")
}
for package in catalog["packages"]:
    data = (public / "win" / package["file"]).read_bytes()
    assert data == fixture.read_bytes()
    assert package["sha256"] == hashlib.sha256(data).hexdigest()
script = (public / "install.ps1").read_text()
assert "@REPO_ROOT_PS@" not in script and "@CHANNELS_PS@" not in script
assert "https://example.invalid/repo''s" in script
# Exercise catalog rejection using a deliberately corrupted published MSI.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    channel = root / "win"
    channel.mkdir()
    package = catalog["packages"][0]
    (channel / package["file"]).write_bytes(fixture.read_bytes() + b"tampered")
    (channel / (package["file"] + ".json")).write_text(json.dumps(package))
    config = root / "channels.json"
    config.write_text(json.dumps([{"name": "win", "architectures": ["x64", "arm64"]}]))
    result = subprocess.run([sys.executable, str(validator), str(root), str(config)], capture_output=True)
    assert result.returncode != 0
    assert b"MSI hash mismatch" in result.stderr
