"""Validate staged MSI metadata and produce deterministic per-channel catalogs."""
import hashlib
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
channels = json.loads(Path(sys.argv[2]).read_text())
for channel in channels:
    directory = root / channel["name"]
    entries = []
    identities = set()
    filenames = set()
    for path in sorted(directory.glob("*.msi.json")):
        entry = json.loads(path.read_text())
        for field in ("name", "version", "release"):
            if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._+-]*", entry[field]):
                raise SystemExit(f"Invalid MSI {field}: {path}")
        filename = entry["file"]
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._+-]*\.msi", filename):
            raise SystemExit(f"Invalid MSI filename: {filename}")
        if entry["architecture"] not in channel["architectures"] or entry["architecture"] not in ("x86", "x64", "arm64"):
            raise SystemExit(f"Invalid MSI architecture: {path}")
        identity = tuple(entry[key] for key in ("name", "version", "release", "architecture"))
        if identity in identities or filename in filenames:
            raise SystemExit(f"Ambiguous MSI metadata: {path}")
        identities.add(identity)
        filenames.add(filename)
        with (directory / filename).open("rb") as stream:
            if stream.read(8) != bytes.fromhex("d0cf11e0a1b11ae1"):
                raise SystemExit(f"Not an MSI compound document: {filename}")
            stream.seek(0)
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if entry["sha256"] != digest:
            raise SystemExit(f"MSI hash mismatch: {filename}")
        entries.append(entry)
    if not entries or filenames != {path.name for path in directory.glob("*.msi")}:
        raise SystemExit(f"Every MSI needs metadata in channel {channel['name']}")
    catalog = {"schemaVersion": 1, "packages": entries}
    (directory / "catalog.json").write_text(json.dumps(catalog, sort_keys=True, indent=2) + "\n")
