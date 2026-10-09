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

An optional `public.nix` receives `package` and `metarepo`, alongside normal
`callPackage` dependencies. Its only required interface is the returned
`{ channels = { ... }; }` set. The `mkApt`, `mkDnf`, and `mkPacman` builders are
conveniences; a package can instead build archives however it needs and declare
them directly:

```nix
{ customDeb }:
{
  channels.stable = {
    architecture = "amd64";
    package = customDeb; # A derivation containing valid .deb package files.
  };
}
```

When using a Metarepo builder, the channel can omit `format` and `architecture`;
the builder records them on its derivation. Custom derivations can either
provide the same `passthru.metarepo` metadata or declare `architecture` on the
channel as above. The format defaults to the configured channel format; an
explicit format or builder metadata must match it. The C and Python packages
show the convenience pattern; each package owns its `public.nix` and can replace
it with its own composition.
A package without `public.nix` remains usable through Nix.

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

- `mkApt`, `mkDnf`, `mkPacman`: functions taking `name`, `version`, `payload`,
  `architecture`, `description`, `homepage`, `maintainer`, `license`,
  optional `depends` and `recommends` (both default to `[]`), and optional
  `release` (default `"1"`).
  `recommends` maps to APT `Recommends`, RPM `Recommends`, and pacman
  `optdepends`. `payload` is a derivation with a native
  filesystem tree such as `usr/bin/`, not a Nix store closure.
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
