# Metarepo library reference

Generated from Nix doc-comments with nixdoc. See the [library guide](library.html) and [installation guide](install.html). Entries under metarepo.internal describe implementation helpers.

## `metarepo.forPkgs`

Bind the package and repository builders to a Nixpkgs package set.
The builders use that set's overlays, configuration and host platform.

### Type

```
forPkgs :: AttrSet -> AttrSet
```

### Inputs

`pkgs`
: A Nixpkgs package set. Native package builders require Linux.

### Examples

```nix
metarepo = inputs.metarepo.lib.forPkgs pkgs;
# metarepo.mkPackage, mkPublication, mkPayload, mkSnapshots,
# mkPublic, mkApt, mkDnf and mkPacman are now available.
```

## `metarepo.internal.hooks`

Internal composer for package installation and removal actions.
Enable actions from declared files, infer dependencies and append custom hooks.
Sysusers runs before tmpfiles, unit reloads and certificate trust refresh.
No action enables or starts services or deletes users or service data.

### Type

```
hooks :: AttrSet -> { depends :: [String], hooks :: AttrSet }
```

### Inputs

`format`
: Package format: `apt`, `dnf` or `pacman`.

`certificates`, `systemd`, `refreshCertificates`
: Integration declarations from `mkPackage`; these inputs are required here.

`hooks`
: Optional `postInstall` and `postRemove` shell strings; defaults to `{ }`.
  Other hook names are rejected.

### Examples

```nix
actions = import ./lib/hooks.nix { inherit lib; } {
  format = "apt";
  certificates = { };
  systemd = { };
  refreshCertificates = true;
  hooks.postInstall = "echo refreshed";
};
# actions.depends == [ "ca-certificates" ]
```

## `metarepo.internal.mkRepository`

Internal repository builder used by `mkPublic`.
Generate APT indexes, RPM metadata and Pacman databases from staged artifacts.

### Type

```
mkRepository :: AttrSet -> Derivation
```

### Inputs

`packages`
: Directory containing per-channel artifacts and an `install.sh`.

`repositories`
: APT configuration (`suites`, fallback `architectures`, optional
  `architecturesBySuite`), and lists of `dnf` and `pacman` channel names.

`repository`
: Repository identity containing `id`, `origin` and `label`.

The result is unsigned. Its `builder` executable stages a replacement of
`public/` and uses `GPG_KEY_ID` for signing, including values loaded from `.env`.

### Examples

```nix
public = pkgs.callPackage ./lib/mk-repository.nix { } {
  inherit packages repositories repository;
};
```

## `metarepo.internal.packageIntegrations`

Internal payload assembler for certificate and systemd resources.
Validate plain basenames and file extensions, install vendor files and combine
inferred dependencies and hooks. Preserve the original payload when no files
are declared.

### Type

```
packageIntegrations :: AttrSet -> { payload :: Derivation, depends :: [String], hooks :: AttrSet }
```

### Inputs

`name`
: Package name, used to prefix certificate filenames.

`format`, `payload`, `certificates`, `systemd`, `refreshCertificates`
: Required integration inputs as documented in `mkPackage`.

`hooks`
: Optional custom installation/removal scripts; defaults to `{ }`.

Return `payload`, `depends` and `hooks` for the native format builder.

### Examples

```nix
integration = pkgs.callPackage ./lib/package-integrations.nix { } {
  name = "example";
  format = "apt";
  payload = pkgs.emptyDirectory;
  certificates."example.crt" = ./example.crt;
  systemd = { };
  refreshCertificates = false;
};
```

## `metarepo.mkApt`

Build a Debian .deb artifact directly, bypassing declarative integrations.
Prefer `mkPackage` to infer certificate/systemd dependencies and actions.

### Type

```
mkApt :: AttrSet -> Derivation
```

### Inputs

`name`, `version`, `payload`, `architecture`, `description`, `homepage`, `maintainer`, `license`
: Required native package inputs, as documented in `mkPackage`.
  Here `payload` is required.

`depends`, `recommends`, `conflicts`, `provides`
: Optional package-manager dependency lists; each defaults to `[ ]`.

`release`, `hooks`
: Native revision (default `"1"`) and installation/removal scripts
  (default `{ }`), as documented in `mkPackage`.

Return a directory containing the artifact and `passthru.metarepo` metadata.
Only native metadata and filesystem content are packaged.

### Examples

```nix
metarepo.mkApt {
  name = "example";
  version = "1.0";
  architecture = "all";
  inherit payload;
  description = "Example package";
  homepage = "https://example.org";
  maintainer = "Example Authors <hello@example.org>";
  license = "MIT";
}
# Produces "$out/example_1.0-1_all.deb".
```

## `metarepo.mkDnf`

Build a RPM .rpm artifact directly, bypassing declarative integrations.
Prefer `mkPackage` to infer certificate/systemd dependencies and actions.

### Type

```
mkDnf :: AttrSet -> Derivation
```

### Inputs

`name`, `version`, `payload`, `architecture`, `description`, `homepage`, `maintainer`, `license`
: Required native package inputs, as documented in `mkPackage`.
  Here `payload` is required.

`depends`, `recommends`, `conflicts`, `provides`
: Optional package-manager dependency lists; each defaults to `[ ]`.

`release`, `hooks`
: Native revision (default `"1"`) and installation/removal scripts
  (default `{ }`), as documented in `mkPackage`.

Return a directory containing the artifact and `passthru.metarepo` metadata.
Only native metadata and filesystem content are packaged.

### Examples

```nix
metarepo.mkDnf {
  name = "example";
  version = "1.0";
  architecture = "noarch";
  inherit payload;
  description = "Example package";
  homepage = "https://example.org";
  maintainer = "Example Authors <hello@example.org>";
  license = "MIT";
}
# Produces "$out/example-1.0-1.noarch.rpm".
```

## `metarepo.mkPackage`

Build an APT, DNF or Pacman artifact from a native filesystem payload.
Declarative certificate and systemd files extend the payload, dependencies
and hooks before dispatching to the format builder. Hooks run on the target
machine, never during the Nix build.

Return a derivation containing the native package file and
`passthru.metarepo = { format; architecture; }`.

### Type

```
mkPackage :: AttrSet -> Derivation
```

### Inputs

`format`
: One of `"apt"`, `"dnf"` or `"pacman"`.

`name`, `version`, `architecture`
: Native package name, upstream version and format-specific architecture.

`description`, `homepage`, `maintainer`, `license`
: Required metadata strings. `license` is an SPDX identifier; APT accepts
  it for API consistency but does not write it to the control file.

`payload`
: Directory laid out as the target filesystem root. Defaults to an empty
  directory, useful for packages containing only declarative resources.

`depends`, `recommends`, `conflicts`, `provides`
: Lists of strings in the package manager's syntax; default to `[ ]`.
  Pacman uses `optdepends` for `recommends`.

`release`
: Native package revision string; defaults to `"1"`.

`certificates`
: Attribute set from plain `.crt` basenames to PEM source files; defaults
  to `{ }`. Files are prefixed with the package name and trust is refreshed.

`systemd`
: Optional `units`, `sysusers` and `tmpfiles` file maps; defaults to `{ }`.
  Sysusers and tmpfiles basenames must end in `.conf`. Installation creates
  users, applies tmpfiles and reloads units as needed. Services are not started.

`hooks`
: Optional shell strings `postInstall` and `postRemove`; defaults to `{ }`.
  Custom actions run after inferred actions and should be idempotent.

`refreshCertificates`
: Also refresh trust for certificates in a custom payload; defaults to `false`.

### Examples

```nix
metarepo.mkPackage {
  format = "apt";
  name = "example-ca";
  version = "1.0";
  architecture = "all";
  description = "Example trust anchor";
  homepage = "https://example.org";
  maintainer = "Example Authors <hello@example.org>";
  license = "MIT";
  certificates."example.crt" = ./example.crt;
}
```

## `metarepo.mkPackages`

Discover packages and publications using the `packages/<name>` convention.
Each package needs `package.nix` and a `systems.nix` list. An optional
`public.nix` receives `package`, `metarepo`, `repository` and Nixpkgs dependencies.
Only packages declared for a system are evaluated on that system.

Return an attribute set indexed by system, suitable for a flake's `packages`.
Systems with publications also export `build-public`. An empty directory
returns `{ }` without evaluating Nixpkgs or repository configuration.

### Type

```
mkPackages :: AttrSet -> AttrSet
```

### Inputs

`packagesDir`
: Path to package directories. `build-public` is a reserved package name.

`repository`
: Repository identity and channels; see `mkPublic`.

`pkgsFor`
: Optional function from system name to package set. Defaults to the input's
  `nixpkgs.legacyPackages`.

`documentation`
: Optional documentation directory, or function from package set to directory.
  Defaults to `null`. Its contents are published under `public/doc`.

### Examples

```nix
packages = metarepo.lib.mkPackages {
  packagesDir = ./packages;
  repository = import ./repository.nix;
  pkgsFor = system: import nixpkgs { inherit system; overlays = [ myOverlay ]; };
};
```

## `metarepo.mkPacman`

Build a Pacman .pkg.tar.zst artifact directly, bypassing declarative integrations.
Prefer `mkPackage` to infer certificate/systemd dependencies and actions.

### Type

```
mkPacman :: AttrSet -> Derivation
```

### Inputs

`name`, `version`, `payload`, `architecture`, `description`, `homepage`, `maintainer`, `license`
: Required native package inputs, as documented in `mkPackage`.
  Here `payload` is required.

`depends`, `recommends`, `conflicts`, `provides`
: Optional package-manager dependency lists; each defaults to `[ ]`.

`release`, `hooks`
: Native revision (default `"1"`) and installation/removal scripts
  (default `{ }`), as documented in `mkPackage`.

Return a directory containing the artifact and `passthru.metarepo` metadata.
Only native metadata and filesystem content are packaged.

### Examples

```nix
metarepo.mkPacman {
  name = "example";
  version = "1.0";
  architecture = "any";
  inherit payload;
  description = "Example package";
  homepage = "https://example.org";
  maintainer = "Example Authors <hello@example.org>";
  license = "MIT";
}
# Produces "$out/example-1.0-1-any.pkg.tar.zst".
```

## `metarepo.mkPayload`

Copy selected package trees into a native filesystem layout.
This copies files without relocating binaries, wrappers or Nix store references.
Use a portable build or assemble a custom payload when relocation is needed.

### Type

```
mkPayload :: AttrSet -> Derivation
```

### Inputs

`package`
: Derivation with `pname` and `version`, whose selected trees will be copied.

`paths`
: Paths relative to the package output; defaults to `[ "bin" "share" ]`.
  Each tree is copied by basename; paths must exist.

`prefix`
: Destination prefix inside the payload; defaults to `"usr"`.

### Examples

```nix
metarepo.mkPayload { inherit package; paths = [ "bin" ]; }
# Result: $out/usr/bin contains the package's bin tree.
```

## `metarepo.mkPublic`

Assemble native artifacts into an unsigned repository and generate its installer.
Configured channels without artifacts are omitted. Unknown publication channels,
mismatched formats, unsafe tokens and ambiguous release selectors are rejected.

Return a repository derivation. Its `builder` is an executable that replaces
`public/` in the working directory and optionally signs using `GPG_KEY_ID`
from the environment or `.env`. Its `installScript` is the generated installer.

### Type

```
mkPublic :: AttrSet -> Derivation
```

### Inputs

`publications`
: List of `mkPublication` results. Each `channels.<name>` accepts one
  artifact or a list. Artifacts need `passthru.metarepo.format` and
  `architecture`, or a record `{ package; architecture; format; }`.
  Record metadata can fall back to the package's metadata; record `format`
  ultimately defaults to the configured channel format.

`repository`
: Attribute set with `id`, `origin`, `label`, `url` and `channels`.
  Each channel specifies `format` (`apt`, `dnf` or `pacman`) and optional
  `releases` (installer aliases, default `[ ]`). The installer also accepts
  channel names. IDs, published channels, release aliases and architectures
  must match `[a-zA-Z0-9][a-zA-Z0-9_+-]*`.

`documentation`
: Optional directory copied under `public/doc`; defaults to `null`.
  When supplied, the channel name `doc` is reserved.

### Examples

```nix
public = metarepo.mkPublic {
  publications = [ publication ];
  repository = {
    id = "example";
    origin = "Example";
    label = "Example packages";
    url = "https://packages.example.org";
    channels.stable = { format = "apt"; releases = [ "ubuntu2404" ]; };
  };
};
# public.builder generates public/; public itself is an unsigned Nix output.
```

## `metarepo.mkPublication`

Publish a Nix package, or all its snapshots, to configured repository channels.
Infer native metadata from `pname`, `version` and `meta`, and infer architecture
from the host platform. APT inference supports x86_64-linux and aarch64-linux.

Options merge in this order: inferred metadata, common package options,
snapshot `passthru.publication`, format options, channel overrides.
The repository channel always determines the final format.

Return `{ channels.<name> = [ artifact ... ]; }` for `mkPublic`.
When `package.passthru.snapshots` exists, every snapshot is published.

### Type

```
mkPublication :: AttrSet -> AttrSet
```

### Inputs

`repository`
: Repository configuration with a `channels` attribute set; see `mkPublic`.

`package`
: Nix derivation. Inferred metadata uses `pname`, `version`,
  `meta.description`, `meta.homepage` and `meta.license.spdxId`.
  Override missing or unsuitable metadata through common package options.

`payload`
: Native filesystem directory, or function from each snapshot package to
  its directory. Defaults to an empty directory. Use a function when the
  payload depends on a snapshot's contents.

`channels`
: Channel names to subscribe to; defaults to all configured channels.
  Unknown names are rejected.

`independent`
: Defaults to `false`. When true, use APT `all`, RPM `noarch` and Pacman `any`.

`formats`
: Package option overrides indexed by format; defaults to `{ }`.

`overrides`
: Package option overrides indexed by channel; defaults to `{ }`.

Additional attributes are common `mkPackage` options. Supply `maintainer`,
which cannot be inferred from the Nix package.

### Examples

```nix
metarepo.mkPublication {
  inherit repository package;
  payload = package: metarepo.mkPayload { inherit package; };
  maintainer = "Example Authors <hello@example.org>";
  formats.apt.depends = [ "libc6" ];
  formats.dnf.depends = [ "glibc" ];
  formats.pacman.depends = [ "glibc" ];
}
```

## `metarepo.mkSnapshots`

Build named snapshots and return the selected default package.
Attach every built package under `passthru.snapshots`, and attach each
snapshot's native publication options under `passthru.publication`.
Existing passthru attributes are preserved.

### Type

```
mkSnapshots :: AttrSet -> Derivation
```

### Inputs

`snapshots`
: Attribute set of snapshot records. Records contain source fields such as
  `rev` and `hash`, arbitrary build options, and optional `publication`.

`default`
: Name of the snapshot returned for Nix users. Must exist in `snapshots`.

`source`
: Function receiving the entire snapshot record and returning its source.

`build`
: Function receiving the snapshot minus `rev`, `hash` and `publication`,
  plus `src = source snapshot`. Must return a derivation with `overrideAttrs`.

### Examples

```nix
metarepo.mkSnapshots {
  snapshots.release = { version = "1.0"; rev = "immutable-commit"; hash = sourceHash; };
  default = "release";
  source = snapshot: fetchurl {
    url = "https://example.org/archive/${snapshot.rev}.tar.gz";
    inherit (snapshot) hash;
  };
  build = { version, src }: stdenv.mkDerivation {
    pname = "example";
    inherit version src;
  };
}
```
