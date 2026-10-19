# Use Metarepo as a library

See the [generated function reference](index.html) for types, arguments
and examples.

Add Metarepo as a flake input. Your project owns `packages/` and the repository
identity and channel/release configuration in `repository.nix`; you do not
need to copy or edit `lib/`. Package platforms and native builds live in
`packages/`.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    metarepo.url = "github:alturalabscr/metarepo";
    metarepo.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, metarepo, ... }: {
    packages = metarepo.lib.mkPackages {
      packagesDir = ./packages;
      repository = import ./repository.nix;
      # Optional: provide package sets with your own overlays/configuration.
      # pkgsFor = system: import nixpkgs { inherit system; };
    };
  };
}
```

`mkPackages` discovers `packages/<name>/package.nix`. Each package declares its
supported systems in an adjacent `systems.nix`:

```nix
[ "x86_64-linux" "aarch64-linux" ]
```

Reuse this declaration in `package.nix` with
`meta.platforms = import ./systems.nix;`. The helper reads these lists before
calling `pkgs.callPackage`, so a package is evaluated only on its declared
systems. These are native build/host systems, not cross-compilation targets.

To add a package, create its directory with `package.nix` and `systems.nix`;
no flake changes are needed. The helper exports it under its directory name.
An empty packages directory produces `{ }`. `build-public` is only exported
on systems with at least one `public.nix`, and that name is reserved.

To include documentation in `public/doc`, pass `documentation = ./my-docs;`
to `mkPackages`, or a function such as
`documentation = pkgs: pkgs.callPackage ./doc { };` to build it for each system.
`mkPublic` also accepts a documentation directory directly. The channel name
`doc` is reserved when documentation is supplied. Unknown publication channels
are rejected rather than silently omitted.

An optional `public.nix` receives `package`, `metarepo`, and `repository`,
alongside normal `callPackage` dependencies. Use `mkPublication` to create
artifacts for the repository's configured channels:

```nix
{ metarepo, repository, package }:
metarepo.mkPublication {
  inherit repository package;
  payload = metarepo.mkPayload { inherit package; };
  maintainer = "Example Authors <hello@example.invalid>";
  formats.apt.depends = [ "libc6" ];
  formats.dnf.depends = [ "glibc" ];
  formats.pacman.depends = [ "glibc" ];
}
```

`mkPublication` reads the name, version, description, homepage, and SPDX license
from the Nix package. It derives architecture names from the host platform
(APT supports x86_64 and aarch64), or uses `independent = true` for architecture-independent
payloads. Common package options are passed through to `mkPackage`.
Use `channels = [ "noble" "fedora" ];` to select channels, `formats.<format>`
for format-specific options, and `overrides.<channel>` for channel-specific
options. Options are merged in this order: inferred metadata, common options,
snapshot publication options, format options, channel overrides. The configured
channel always determines the format.

`mkPayload { package; paths ? [ "bin" "share" ]; prefix ? "usr"; }` copies
selected directories into a native filesystem layout. It does not relocate
binaries, wrappers or Nix store dependencies. Use a portable build, or provide a
custom payload. The Python example assembles its source and system interpreter
launcher explicitly. Fastfetch uses a static musl build with optional graphical
integrations disabled. A package without `public.nix` remains usable through Nix.

`mkPublication` returns channel lists and automatically publishes every snapshot
when `package.passthru.snapshots` exists. `mkPublic` accepts a single artifact or
a list for each channel. Custom builders can return records directly:

```nix
{ customDeb }:
{ channels.stable = { architecture = "amd64"; package = customDeb; }; }
```

Builder derivations record `format` and `architecture` in `passthru.metarepo`.
Custom records may omit `format`; it defaults to the channel's configured format.
Explicit formats must match the channel.

## Declarative system integration

Declare files alongside the package options, in `mkPackage` or `mkPublication`:

```nix
certificates."company.crt" = ./company.crt;
systemd = {
  units."example.service" = ./example.service;
  sysusers."example.conf" = ./sysusers.conf;
  tmpfiles."example.conf" = ./tmpfiles.conf;
};
```

Values are source files (Nix paths or file derivations such as `writeText`).
Keys are plain file basenames; sysusers/tmpfiles names must end in `.conf`.
The library adds them to the payload and infers dependencies and installation
scripts from the declarations. The payload is optional for packages consisting
only of these resources. File declarations activate resource setup without extra flags.
Each action runs once per package event, regardless of how many files it installs.
Explicit `refreshCertificates = true` remains supported for custom payloads.

Certificates must have `.crt` names and contain one PEM certificate per file.
Names are prefixed with the package name to avoid clashes. APT uses
`/usr/local/share/ca-certificates`, DNF `/usr/share/pki/ca-trust-source/anchors`,
and Pacman `/usr/share/ca-certificates/trust-source/anchors`. Trust is refreshed
on installation, upgrades and removal. Dependencies are `ca-certificates` for
APT/DNF and `ca-certificates-utils` for Pacman. These paths and refresh commands
follow the [Debian certificate documentation](https://manpages.debian.org/unstable/ca-certificates/update-ca-certificates.8.en.html)
and [Arch trust documentation](https://man.archlinux.org/man/update-ca-trust.8).

Systemd declarations install vendor files under `/usr/lib/systemd/system`,
`/usr/lib/sysusers.d`, and `/usr/lib/tmpfiles.d`, and add a `systemd` dependency.
On installation and upgrades, sysusers creates the declared users, then tmpfiles
creates directories/files, certificate declarations refresh trust, and unit
installation reloads the systemd manager before requesting service actions.
Only the package's configuration basenames are passed to sysusers/tmpfiles,
allowing administrator overrides in `/etc` to take precedence. Removal reloads
the manager after units disappear; users and service data remain.
Reload is skipped when systemd is not running (for example in an offline root).
Plain unit source files only install the unit. To request lifecycle actions,
use a record for that unit:

```nix
systemd.units."example.service" = {
  source = ./example.service;
  enable = true;
  start = true;
  restartOnUpgrade = true;
};
```

`enable`, `start` and `restartOnUpgrade` default to `false`. `enable` requests
boot activation and `start` requests immediate activation on the first install.
Neither is repeated on upgrades, preserving administrator choices. An upgrade
with `restartOnUpgrade = true` only restarts a unit that is already running.
`stopOnRemove` defaults to `true` when any of these flags is true, otherwise
`false`; it can be overridden. Before actual removal, units are stopped when
requested and units with `enable = true` are disabled. Upgrades never run these
removal actions. Users and service data are preserved.

Runtime actions are skipped when systemd is not running; enable/disable may
still update boot configuration in an offline root. Lifecycle command failures
are visible but do not abort package installation or removal. APT uses
`deb-systemd-helper` for boot configuration and `deb-systemd-invoke` for runtime
requests, adding `init-system-helpers` to dependencies. Its runtime requests
respect Debian's [policy-rc.d](https://manpages.debian.org/unstable/init-system-helpers/deb-systemd-invoke.1p.en.html)
and disabled/masked services. APT purge also cleans the helper's bookkeeping.
DNF and Pacman use systemctl. Masked units are never unmasked by the library.
See [systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/systemd-tmpfiles.html).

Raw `hooks.postInstall`, `hooks.preRemove` and `hooks.postRemove` are available for custom shell
actions and run after the inferred actions. The declarative options describe
what the package installs; hooks describe actions on the target system.
The library centralizes action selection, dependencies and hook composition in
`lib/hooks.nix`; `lib/systemd-units.nix` handles unit policies and lifecycle
scripts, and `lib/package-integrations.nix` handles file layout and installation.

## Installation hooks

The generic package interface is `mkPackage { format; ...; }`. It dispatches to
APT, DNF or Pacman and accepts `hooks.postInstall`, `hooks.preRemove` and `hooks.postRemove`, all
shell script strings running on the target system. For example, add these options
to `mkPublication`:

```nix
refreshCertificates = true;
hooks.postInstall = "echo 'Certificates installed'";
```

`refreshCertificates` adds the certificate tooling to dependencies and refreshes
trust on installation, upgrades and removal using `update-ca-certificates` for
APT and `update-ca-trust extract` for DNF/Pacman. Put certificates in the target
format's trust input directory; the helper does not move them. Custom hooks run
after the refresh. `postInstall` runs on installation and upgrades; `preRemove`
runs before files are removed, and `postRemove` afterwards. Removal hooks skip
upgrades and failed/aborted APT operations. APT `postRemove` also runs on purge.
Native wrappers set `METAREPO_ACTION` to `install`, `upgrade`, `remove` or `purge`
so custom hooks can distinguish events without interpreting manager arguments.
APT uses `postinst`/`prerm`/`postrm`, RPM `%post`/`%preun`/`%postun`, and Pacman
`post_install`/`post_upgrade`/`pre_remove`/`post_remove`.
Hooks should be idempotent; each package manager controls failure
handling. No hooks run while building the Nix derivation.

## Snapshots by commit

`mkSnapshots { snapshots; default; source; build; }` creates the default Nix
package with all versions available under `passthru.snapshots`. `source` receives
the snapshot record (including `rev` and `hash`); `build` receives its other build
options plus the fetched `src`. A snapshot's optional `publication` record
supplies native package options for that version, such as `depends`, `recommends`,
`release`, or hooks. The helper imposes no upstream or build-system convention.

See `packages/fastfetch/snapshots.nix` and `packages/fastfetch-git/snapshots.nix`:
add a named record with a unique `version`, immutable commit `rev`, archive hash,
build options, and publication options. Change `default` in `package.nix` to select
the version exported for Nix users. All snapshots are published to subscribed
channels. These deliberately historical examples use two release commits and
two development commits; they demonstrate pinning rather than tracking latest releases.

The examples use flat archive hashes from `fetchurl`. Compute a new hash with
`nix store prefetch-file --json https://codeload.github.com/fastfetch-cli/fastfetch/tar.gz/<commit>`.
The shared Fastfetch build recipe belongs to the example; snapshot orchestration,
filesystem layout, channel selection and package hooks belong to the library.
`fastfetch-git` provides `fastfetch`; the two packages conflict because they
install the same executable. Their static builds vary threading options and
recommended runtime tools by snapshot.

## Project configuration

```nix
{
  id = "my-project";
  origin = "My Project";
  label = "My Project packages";
  url = "https://packages.example.org";
  channels.stable = { format = "apt"; releases = [ "ubuntu2404" ]; };
}
```

This file contains repository identity, hosting information, and supported
channels. A package subscribes by providing its artifact for a channel in
`packages/<name>/public.nix`, for example:

```nix
channels.stable = apt;
```

`mkPublic` groups artifacts by channel. A channel without artifacts is omitted
from publication and installer detection. Add distribution support by updating
the channel's `releases` list in `repository.nix`.

Detection first tries `ID + VERSION_ID` from `os-release`, removing dots, then
`VERSION_CODENAME`. Channel names are also accepted during detection. An alias
cannot select multiple published channels. IDs, channel names, aliases and
architectures must match `[a-zA-Z0-9][a-zA-Z0-9_+-]*`.

A channel is a shared repository: an alias selects all packages published in
that channel. Use separate channels for incompatible distribution builds.

RPM channels use `format = "dnf"`. The shell installer automatically uses
Zypper and `/etc/zypp/repos.d` when `zypper` is available, reusing RPM artifacts
and metadata.

The installer configures the selected channel and checks its architectures.
APT metadata also uses each suite's own architectures. There are no distribution
version defaults in the library. Associations declare compatibility; they do
not rebuild a payload against that distribution's libraries or prove ABI
compatibility. The native payload and dependencies remain the project's
responsibility. Add distribution support for an existing format in the relevant
`packages/<name>/public.nix`; supporting a new package format requires library
code.

APT channels share one repository at `<repository.url>/apt`: suite indexes
live under `apt/dists/<channel>` and binary files under
`apt/pool/main/<sha256>/<filename>`. Identical files across suites are published
once. Different builds with the same filename stay separate, and each suite
indexes only its own packages. This reduces static hosting and Pages artifacts
without depending on filesystem links. The channel name `apt` is reserved.

This changes the APT base URL from `/<channel>` to `/apt`. Existing clients must
rerun the installer or update their source entry, keeping the suite unchanged
(for example, `/apt noble main`). RPM and Pacman URLs are unchanged.

## Lower-level builders

For projects with a different layout, use `metarepo.lib.forPkgs pkgs`. It exposes:

- `mkPackage`: takes `format` (`"apt"`, `"dnf"`, `"pacman"`, `"msi"`), `name`,
  `version`, `architecture`, `description`, `homepage`, `maintainer`,
  `license`, optional `depends`, `recommends`, `conflicts`, `provides` (lists),
  `release` (default `"1"`), optional `payload` (empty by default), `certificates`,
  `systemd`, `hooks` and `refreshCertificates`.
  Dependency strings use the selected format's syntax. `recommends` maps to APT/RPM
  `Recommends` and Pacman `optdepends`.
- `mkPublication`, `mkPayload`, `mkSnapshots`: the composition helpers above.
- `mkApt`, `mkDnf`, `mkPacman`: retained for existing consumers; new code should
  use `mkPackage` or `mkPublication` to share behavior across formats.
- `mkPublic { publications; repository; }`: an unsigned repository derivation.
  Its `builder` attribute is the executable derivation that generates `public/`
  in the working directory, with optional signing through `GPG_KEY_ID`.
  Its `installScript` attribute contains the generated Linux installer;
  `installPowerShell` contains the Windows installer.

No directory discovery is required by these builders. Custom package derivations
can provide `passthru.metarepo` metadata for `mkPublic`, or set `architecture`
explicitly in a channel entry.
A builder derivation can be assigned directly: `channels.stable = apt;`.
The record form, `channels.stable = { package = apt; };`, is also supported.

## Use this repository as a template

Copy or fork this repository, replace the example packages, edit
`repository.nix`, and declare platforms in each package’s `systems.nix`. The
same library API is used by the template itself. To maintain the library
separately, use the input-based flake above and retain your project
configuration, packages and publishing workflow. The input URL must reference a
revision containing this API.

Both approaches preserve:

```sh
nix run .#hello
nix profile add .#hello
nix run .#hello-python
nix run .#build-public
```

The existing workflow publishes the resulting static `public/` directory to
GitHub Pages. Configure its URL and signing secrets as described in the README.

## Windows MSI publication

MSI publication preserves an existing installer; metarepo does not compile Windows
programs or turn Linux payloads into MSI files. Build the MSI separately and use
a pinned source such as `pkgs.fetchurl` with `hash`.

```nix
repository.channels.win = {
  format = "msi";
  releases = [ "windows11" ];
};

msi = metarepo.mkPackage {
  format = "msi";
  name = "example";
  version = "1.0.0";
  architecture = "x64"; # x86, x64 or arm64; target, not build host
  installer = ./example.msi;
};

public = metarepo.mkPublic {
  inherit repository;
  publications = [ { channels.win = msi; } ];
};
```

`mkMsi` exposes the same MSI-specific interface directly. With `mkPublication`,
select `channels = [ "win" ];`, leave `payload` empty, and provide
`formats.msi.installer` and `formats.msi.architecture`. Descriptive metadata is
inferred as for other formats. Linux hooks, certificates, systemd and dependency
options are rejected: installation and upgrade behavior belong in the MSI.

Each MSI is copied unchanged with a JSON sidecar. Publishing validates the header,
metadata and digest and writes `win/catalog.json`. Header validation checks the
compound-document signature; it does not certify MSI tables or installability.
Conflicting files and ambiguous package/version/release/architecture entries fail
the build. The generated `install.ps1` uses this catalog; `install.sh` only handles
Linux channels. `public.installPowerShell` exposes the PowerShell script directly.
`windows11` is a metarepo alias, not an `os-release` value. Other Windows selectors
can be configured explicitly; no Windows Server release is inferred.

An HTTPS repository is required by the PowerShell installer. SHA-256 verifies the
MSI against the HTTPS catalog; it is not an independent publisher signature.
Authenticode signatures in prebuilt files are preserved. `GPG_KEY_ID` continues
to sign Linux repositories and does not sign MSI files.

WinGet manifests and a WinGet source are not generated. They can be added as a
separate integration using the same installer URLs and hashes.


### Constructing MSI files on Linux

`mkMsiInstaller` turns a Windows payload directory into a machine-wide x64 MSI
using wixl. It does not compile applications. Define each application's Windows
build in its own repository, then pass the resulting files:

```nix
installer = metarepo.mkMsiInstaller {
  name = "example";
  version = "1.2.3";
  manufacturer = "Example";
  payload = windowsFiles;
  launcher = "example.exe"; # optional Start Menu shortcut
  family = "example"; # shared upgrade identity and installation directory
  registry = [
    { key = "Software\\Example"; name = "Path"; value = "[INSTALLDIR]example.exe"; }
  ];
};
```

Pass `installer` to `mkMsi` or `mkPackage { format = "msi"; ...; }` to publish it.
Products sharing a `family` replace one another, including equal MSI versions;
use different families for applications that should coexist. ProductVersion is
the first three numeric version components. Names may include spaces but not
path separators. Installations require administrator permissions. Registry values
and shortcuts are declarative; the builder runs no custom installation actions.
Building or inspecting an MSI on Linux does not verify installation on Windows.


### Per-snapshot publication and inherited channels

`mkPublication` accepts `snapshotOptions = snapshot: { ...; }`. The callback
receives each built snapshot and can choose its channels, payload, architecture
independence, format options, and channel overrides. Structured options can also
be stored in the snapshot's `publication` record. Sources and built packages are
unchanged; a single snapshot can supply several publication formats.

```nix
metarepo.mkPublication {
  inherit repository package;
  maintainer = "Example Authors";
  snapshotOptions = snapshot: snapshot.nativePublication;
  # Alternatively, compute formats or overrides directly from each package:
  formats = snapshot: { apt.description = snapshot.meta.description; };
}
```

Precedence is inferred metadata, common options, snapshot `publication`,
`snapshotOptions`, format options, then channel overrides. `formats` and
`overrides` may be attribute sets or functions from each snapshot to those sets.
A value supplied by `snapshotOptions` replaces the corresponding common option.

A channel may declare `inherits = "parent"`. When its parent is published, the
alias reuses exactly the same artifact, including transitive aliases. Publishing
only an alias does not publish its parent. To build a distinct alias artifact,
select the alias in `channels` and provide an explicit `overrides.<alias>` entry.
Aliases must use their parent's format; missing parents and cycles are errors.
Different snapshots may subscribe to different channels. Channel lists aggregate
only the snapshots that subscribe to them, including their inherited aliases.
