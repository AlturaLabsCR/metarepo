# Use Metarepo as a library

Add Metarepo as a flake input. Your project owns `packages/` and the repository
identity in `repository.nix`; you do not need to copy or edit `lib/`. Package
platforms, native builds, channels and release aliases live in `packages/`.

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
    format = "apt";
    architecture = "amd64";
    package = customDeb; # A derivation containing valid .deb package files.
    releases = [ "ubuntu2404" ];
  };
}
```

When using a Metarepo builder, the channel can omit `format` and `architecture`;
the builder records them on its derivation. Custom derivations can either
provide the same `passthru.metarepo` metadata or declare those fields on the
channel as above. The C and Python packages show the convenience pattern; each
package owns its `public.nix` and can replace it with its own composition.
A package without `public.nix` remains usable through Nix.

## Project configuration

```nix
{
  id = "my-project";
  origin = "My Project";
  label = "My Project packages";
  url = "https://packages.example.org";
}
```

This file contains only repository identity and hosting information. Package
support belongs entirely in `packages/<name>/public.nix`, for example:

```nix
channels.stable = {
  package = apt;
  releases = [ "ubuntu2404" ];
};
```

After evaluating the packages available for a system, `mkPublic` groups their
channels and combines their `releases` aliases, removing duplicates. Removing a
package also removes aliases contributed only by that package. No global
channel or release registry is needed.

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
  `architecture`, `description`, `homepage`, `maintainer`, `depends`, `license`,
  and optional `release` (default `"1"`). `payload` is a derivation with a native
  filesystem tree such as `usr/bin/`, not a Nix store closure.
- `mkPublic { publications; repository; }`: an unsigned repository derivation.
  Its `builder` attribute is the executable derivation that generates `public/`
  in the working directory, with optional signing through `GPG_KEY_ID`.
  Its `installScript` attribute contains the generated installer.

No directory discovery is required by these builders. Custom package derivations
can provide `passthru.metarepo` metadata for `mkPublic`, or set `format` and
`architecture` explicitly in a channel entry.

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
