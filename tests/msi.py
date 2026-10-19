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
    ("1.0", "x64"), ("2.0", "x64"), ("2.0", "arm64"),
    ("2.9", "x64"), ("2.10", "x64")
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

# Browser aliases select numerically latest versions without copying an MSI.
from html.parser import HTMLParser

class Page(HTMLParser):
    def __init__(self, path):
        super().__init__()
        self.refresh = None
        self.links = []
        self.feed(path.read_text())

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        assert tag != "script"
        if tag == "meta" and attrs.get("http-equiv") == "refresh":
            self.refresh = attrs["content"]
        if tag == "a":
            self.links.append(attrs["href"])

base = public / "win/example"
assert Page(base / "index.html").refresh is None
assert set(Page(base / "index.html").links) == {"x64/", "arm64/"}
for architecture, version in [("x64", "2.10"), ("arm64", "2.0")]:
    path = base / architecture / "index.html"
    page = Page(path)
    target = f"../../example-{version}-1-{architecture}.msi"
    assert page.refresh == "0; url=" + target
    assert page.links == [target]
    assert (path.parent / target).read_bytes() == fixture.read_bytes()
assert len(list((public / "win").rglob("*.msi"))) == len(catalog["packages"])

# A single architecture redirects directly at the short package URL.
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    channel = root / "win"
    channel.mkdir()
    for entry in catalog["packages"]:
        if entry["architecture"] == "x64":
            (channel / entry["file"]).write_bytes(fixture.read_bytes())
            (channel / (entry["file"] + ".json")).write_text(json.dumps(entry))
    config = root / "channels.json"
    config.write_text(json.dumps([{"name": "win", "architectures": ["x64"]}]))
    subprocess.run([sys.executable, str(validator), str(root), str(config)], check=True)
    page = Page(channel / "example/index.html")
    assert page.refresh == "0; url=../example-2.10-1-x64.msi"
    assert page.links == ["../example-2.10-1-x64.msi"]

    # Revisions are compared numerically too, independently of file ordering.
    latest = next(e for e in catalog["packages"] if e["version"] == "2.10")
    for release in ["10", "2"]:
        entry = dict(latest, release=release, file=f"example-2.10-{release}-x64.msi")
        (channel / entry["file"]).write_bytes(fixture.read_bytes())
        (channel / (entry["file"] + ".json")).write_text(json.dumps(entry))
    subprocess.run([sys.executable, str(validator), str(root), str(config)], check=True)
    assert Page(channel / "example/index.html").refresh == "0; url=../example-2.10-10-x64.msi"
