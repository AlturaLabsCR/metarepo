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
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/metarepo.gpg] $BASE_URL/apt noble main" \
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

## openSUSE Leap 16.0 and Tumbleweed (`zypper`)

Both releases use the `suse` RPM channel:

```sh
BASE_URL="https://packages.example.org/metarepo"
sudo rpm --import "$BASE_URL/metarepo.asc"
sudo tee /etc/zypp/repos.d/metarepo.repo >/dev/null <<EOF
[metarepo]
name=Metarepo (openSUSE)
baseurl=$BASE_URL/suse/
enabled=1
autorefresh=1
gpgcheck=1
pkg_gpgcheck=1
repo_gpgcheck=0
gpgkey=$BASE_URL/metarepo.asc
EOF
sudo zypper refresh metarepo
sudo zypper install metarepo-hello-c metarepo-hello-python
```

Package signatures are required; metadata signature checks are disabled, as in
Fedora's configuration. See the [Zypper documentation](https://manpages.opensuse.org/Tumbleweed/zypper/zypper.8.en.html).

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
[metarepo]
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

## Windows MSI

For repositories publishing an MSI channel, download their generated script:

```powershell
Invoke-WebRequest -Uri 'https://packages.example.org/metarepo/install.ps1' -OutFile install.ps1
.\install.ps1 -Package example
.\install.ps1 -Package example -Version 1.0.0 -Architecture x64 -Silent
.\install.ps1 -Package example -Scope User
```

Requires Windows PowerShell 5.1 or PowerShell 7 on Windows. Local execution policy
must allow the downloaded script; it does not change execution policies.
The default release alias `windows11` checks for a workstation with build 22000
or newer. `-Release` can select another configured Windows alias or channel.
Architecture detection uses the native OS architecture, including when PowerShell
runs as a 32-bit process. `-Architecture` overrides it explicitly.

The script downloads the catalog over HTTPS, selects the matching MSI, verifies
SHA-256, and invokes `msiexec`. With multiple versions it requires `-Version`;
with multiple package revisions it also requires `-PackageRelease`. It does not
silently select a version by filename order.

The default `-Scope Machine` requests installation for all users and prompts for
administrator elevation when needed. `-Scope User` requests per-user installation
with `ALLUSERS=2 MSIINSTALLPERUSER=1` and does not explicitly elevate. This only
works when the MSI supports per-user installation; the script cannot make a
machine-only MSI install without the permissions it needs. See Microsoft's
[MSIINSTALLPERUSER documentation](https://learn.microsoft.com/en-us/windows/win32/msi/msiinstallperuser).

`-Silent` passes `/qn` to MSI; elevation may still display a UAC prompt.
`-WhatIf` resolves the catalog entry without downloading or executing the MSI.
All installations pass `/norestart`. The script reports installer failures and
restart-required results, preserves the installation log in the temporary
folder, and removes the downloaded MSI. It does not automatically uninstall
other products, configure WinGet, or schedule future updates. Upgrade and
uninstall behavior are defined by the MSI itself.
