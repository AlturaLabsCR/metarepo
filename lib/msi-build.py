"""Build a small WiX description without application-specific behavior."""
import hashlib
import json
from pathlib import Path
import re
import sys
import uuid
import xml.etree.ElementTree as X

options = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
name, version, family, vendor, launcher = (options[k] for k in ("name", "version", "family", "manufacturer", "launcher"))
identity = lambda text: str(uuid.uuid5(uuid.NAMESPACE_URL, vendor + "/" + text)).upper()
node = lambda parent, tag, **attrs: X.SubElement(parent, tag, attrs)
wix = X.Element("Wix", xmlns="http://schemas.microsoft.com/wix/2006/wi")
product = node(wix, "Product", Id=identity(name + "/" + version + "/" + str(root)), Name=name, Language="1033",
               Version=re.match(r"\d+\.\d+\.\d+", version)[0], Manufacturer=vendor, UpgradeCode=identity(family))
node(product, "Package", InstallerVersion="500", Compressed="yes", InstallScope="perMachine")
node(product, "MajorUpgrade", AllowSameVersionUpgrades="yes", DowngradeErrorMessage="Uninstall the newer version before downgrading.")
node(product, "Media", Id="1", Cabinet="payload.cab", EmbedCab="yes")
node(product, "Condition", Message="Requires 64-bit Windows and per-machine installation.").text = "VersionNT64 AND ALLUSERS=1"
target = node(product, "Directory", Id="TARGETDIR", Name="SourceDir")
programs = node(target, "Directory", Id="ProgramFiles64Folder")
vendor_dir = node(programs, "Directory", Id="Vendor", Name=vendor)
directories = {Path('.'): node(vendor_dir, "Directory", Id="INSTALLDIR", Name=family)}
feature = node(product, "Feature", Id="Complete", Title=name, Level="1")
files = sorted(root.rglob('*'))
if not any(p.is_file() for p in files):
    raise SystemExit("MSI payload must contain files")
if launcher and (Path(launcher).is_absolute() or ".." in Path(launcher).parts or not (root / launcher).is_file()):
    raise SystemExit("MSI launcher must refer to a payload file")
for path in files:
    relative = path.relative_to(root)
    ident = 'F' + hashlib.sha256(str(relative).encode()).hexdigest()[:24]
    parent = directories[relative.parent]
    if path.is_dir():
        directories[relative] = node(parent, "Directory", Id=ident, Name=path.name)
        continue
    if path.is_symlink():
        raise SystemExit(f"MSI payload must contain regular files, not symlinks: {relative}")
    component = node(parent, "Component", Id='C' + ident, Guid=identity(family + '/' + str(relative)), Win64="yes")
    node(component, "File", Id=ident, Name=path.name, Source=str(path), KeyPath="yes")
    if str(relative) == launcher:
        node(component, "Shortcut", Id="StartMenu", Directory="ProgramMenuFolder", Name=name,
             Target="[INSTALLDIR]" + launcher.replace('/', '\\'), WorkingDirectory="INSTALLDIR")
    node(feature, "ComponentRef", Id='C' + ident)
if launcher:
    node(target, "Directory", Id="ProgramMenuFolder")
if options['registry']:
    component = node(directories[Path('.')], "Component", Id="Configuration", Guid=identity(family + '/registry'), Win64="yes")
    for index, entry in enumerate(options['registry']):
        attributes = dict(Id=f"Registry{index}", Root=entry.get('root', 'HKLM'), Key=entry['key'],
                          Type=entry.get('type', 'string'), Value=entry['value'])
        if 'name' in entry:
            attributes['Name'] = entry['name']
        if index == 0:
            attributes['KeyPath'] = 'yes'
        node(component, "RegistryValue", **attributes)
    node(feature, "ComponentRef", Id="Configuration")
X.ElementTree(wix).write("installer.wxs", encoding="utf-8", xml_declaration=True)
