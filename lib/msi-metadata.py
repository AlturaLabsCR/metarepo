"""Describe a prebuilt MSI, preserving its bytes and computing its digest."""
import hashlib
import json
from pathlib import Path
import sys

metadata = json.loads(Path(sys.argv[1]).read_text())
installer = Path(sys.argv[2])
# MSI is an OLE compound document. Reject obvious wrong downloads such as HTML.
with installer.open("rb") as stream:
    if stream.read(8) != bytes.fromhex("d0cf11e0a1b11ae1"):
        raise SystemExit(f"Not an MSI compound document: {installer.name}")
    stream.seek(0)
    metadata["sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
installer.with_suffix(".msi.json").write_text(json.dumps(metadata, indent=2) + "\n")
