# Use Metarepo as a library

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
only of these resources. No boolean flags are needed to activate their actions.
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
creates directories/files, and unit installation reloads the systemd manager.
Only the package's configuration basenames are passed to sysusers/tmpfiles,
allowing administrator overrides in `/etc` to take precedence. Removal reloads
the manager after units disappear; users and service data remain.
Reload is skipped when systemd is not running (for example in an offline root).
The library does not enable, start, restart or stop services automatically.
See [systemd-tmpfiles](https://www.freedesktop.org/software/systemd/man/systemd-tmpfiles.html).

Raw `hooks.postInstall` and `hooks.postRemove` remain available for custom shell
actions and run after the inferred actions. The declarative options describe
what the package installs; hooks describe actions on the target system.
The library centralizes action selection, dependencies and hook composition in
`lib/hooks.nix`; `lib/package-integrations.nix` handles file layout and installation.

## Installation hooks

The generic package interface is `mkPackage { format; ...; }`. It dispatches to
APT, DNF or Pacman and accepts `hooks.postInstall` and `hooks.postRemove`, both
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
after the refresh. APT hooks run only for configure and remove/purge events;
RPM uses `%post`/`%postun`; Pacman uses `post_install`, `post_upgrade` and
`post_remove`. Hooks should be idempotent; each package manager controls failure
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

The installer configures the selected channel and checks its architectures.
APT metadata also uses each suite's own architectures. There are no distribution
version defaults in the library. Associations declare compatibility; they do
not rebuild a payload against that distribution's libraries or prove ABI
compatibility. The native payload and dependencies remain the project's
responsibility. Add distribution support for an existing format in the relevant
`packages/<name>/public.nix`; supporting a new package format requires library
code.

## Lower-level builders

For projects with a different layout, use `metarepo.lib.forPkgs pkgs`. It exposes:

- `mkPackage`: takes `format` (`"apt"`, `"dnf"`, `"pacman"`), `name`,
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
  Its `installScript` attribute contains the generated installer.

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
