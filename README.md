# Metarepo

Reusable Nix library and project template for building APT, DNF and Pacman
package repositories.

Use `lib.mkPackages` to export packages and the repository builder from another
flake, or `lib.forPkgs` for individual native package builders. See
[the library API and template guide](doc/library.md). Platforms and distribution aliases live
in `packages/`; adding packages or releases requires no changes elsewhere.

The example packages are `metarepo-hello-c` and `metarepo-hello-python`.

## Build

```sh
nix flake show
nix run .#hello
nix profile add .#hello
nix run .#build-public
```

This generates the repository in `public/`, including `install.sh`. Set
`GPG_KEY_ID` to sign packages and repository metadata.

## Publish

Set the public repository URL in `repository.nix`, then sync `public/` to a
static web server:

```sh
rsync -a --delete public/ deploy@packages.example.org:/srv/www/metarepo/
```

The GitHub Actions workflow also publishes `public/` to GitHub Pages on pushes
to `main`. Set the URL in `repository.nix` to the Pages address and select
**GitHub Actions** as the Pages deployment source. To sign the repository, set
both the `GPG_PRIVATE_KEY` and `GPG_KEY_ID` repository secrets.

## Install

```sh
curl -fsSL https://alturalabscr.github.io/metarepo/install.sh | sudo sh
```

For manual client configuration, see [doc/install.md](doc/install.md).
