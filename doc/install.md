# Manual repository installation

The generated `public/install.sh` configures the repository automatically for
the supported distribution release and architecture. To configure it manually,
replace `https://packages.example.org/metarepo` below with the `url` from
`repository.nix`. These examples assume repository signing is enabled and the
published key is `metarepo.asc`.

## Ubuntu (`apt`)

Use a suite published by the repository, such as `noble` or `jammy`. Change
`amd64` to `arm64` when that architecture is published.

```sh
BASE_URL=https://packages.example.org/metarepo
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL "$BASE_URL/metarepo.asc" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/metarepo.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/metarepo.gpg] $BASE_URL/noble noble main" \
  | sudo tee /etc/apt/sources.list.d/metarepo.list >/dev/null
sudo apt update
sudo apt install metarepo-hello-c metarepo-hello-python
```

## Fedora (`dnf`)

Create `/etc/yum.repos.d/metarepo.repo`:

```ini
[metarepo]
name=Metarepo Linux packages
baseurl=https://packages.example.org/metarepo/fedora/
enabled=1
gpgcheck=1
# Disable metadata signature checks to avoid the related warning.
repo_gpgcheck=0
gpgkey=https://packages.example.org/metarepo/metarepo.asc
```

Then install the packages:

```sh
sudo dnf install metarepo-hello-c metarepo-hello-python
```

## Arch Linux (`pacman`)

Download and verify the key fingerprint before trusting it:

```sh
tmp="$(mktemp)"
curl -fsSLo "$tmp" https://packages.example.org/metarepo/metarepo.asc
gpg --show-keys --with-fingerprint "$tmp"
fingerprint="$(gpg --show-keys --with-colons "$tmp" |
  sed -n '/^fpr:/ { s/:$//; s/.*://; p; q; }')"
sudo pacman-key --add "$tmp"
sudo pacman-key --lsign-key "$fingerprint"
rm -f "$tmp"
```

Add the repository to `/etc/pacman.conf`:

```ini
[metarepo-arch]
SigLevel = Required
Server = https://packages.example.org/metarepo/arch/
```

Then install the packages:

```sh
sudo pacman -Sy metarepo-hello-c metarepo-hello-python
```

## Nix

The flake also exposes the example packages directly. Install either package
into your Nix profile:

```sh
nix profile install github:AlturaLabsCR/metarepo#hello
nix profile install github:AlturaLabsCR/metarepo#hello-python
```

Or run a package without adding it to the profile:

```sh
nix run github:AlturaLabsCR/metarepo#hello
nix run github:AlturaLabsCR/metarepo#hello-python
```
