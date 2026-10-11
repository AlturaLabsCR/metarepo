# Metarepo

Reusable Nix library and project template for building APT, DNF and Pacman
package repositories.

Use `lib.mkPackages` to export packages and the repository builder from another
flake, or `lib.forPkgs` for `mkPublication` and `mkPackage`. See
[the library API and template guide](doc/library.md). Platforms live in `packages/` and distribution aliases in `repository.nix`; adding packages or releases requires no changes elsewhere.

The [generated API reference](public/doc/api.md) documents each library function.

The examples include C, Python, `fastfetch` and `fastfetch-git`. Fastfetch
snapshots pin commits and hashes, with build options and dependencies per version.

## Build

```sh
nix flake show
nix run .#hello
nix profile add .#hello
nix run .#build-public
```

This generates the repository in `public/`, including `install.sh` and the
nixdoc reference in `public/doc/`. Set
`GPG_KEY_ID` to sign packages and repository metadata.

Build documentation separately and refresh the tracked files with:

```sh
nix build .#docs
mkdir -p public/doc
cp -R result/. public/doc/
chmod -R u+w public/doc/
```

Format Nix files with `nix fmt` and run the tests with `nix flake check`.
The documentation check detects stale generated files.

## Staging validation

The **Validate staging repository** workflow runs on pushes to `staging`, pull
requests targeting `main` or `staging`, and manual runs. It checks formatting,
the library tests and generated documentation, then verifies that
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
