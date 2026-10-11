# Metarepo

Reusable Nix library and project template for building APT, DNF and Pacman
package repositories.

Use `lib.mkPackages` to export packages and the repository builder from another
flake, or `lib.forPkgs` for `mkPublication` and `mkPackage`. See
[the library API and template guide](doc/library.md). Platforms live in `packages/` and distribution aliases in `repository.nix`; adding packages or releases requires no changes elsewhere.

The examples include C, Python, `fastfetch` and `fastfetch-git`. Fastfetch
snapshots pin commits and hashes, with build options and dependencies per version.

## Build

```sh
nix flake show
nix run .#hello
nix profile add .#hello
nix run .#build-public
```

This generates the repository in `public/`, including `install.sh`. Set
`GPG_KEY_ID` to sign packages and repository metadata.

## Staging validation

The **Validate staging repository** workflow runs on pushes to `staging`, pull
requests targeting `main` or `staging`, and manual runs. It checks that
`nix run .#build-public` successfully generates `public/`.

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
