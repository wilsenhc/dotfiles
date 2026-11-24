# dotfiles

My dotfiles, shell scripts and configuration files, kept in one repository so that any Ubuntu machine I use can be set up the same way every time.

## Goal

- **Reproducible** — the same files and settings on every machine.
- **Installable** — one script applies the repository to a fresh installation.
- **Safe to re-run** — anything the installer replaces is backed up first.

## Layout

```
dotfiles/
├── install.sh           applies this repository to the current machine
├── bash/                shell fragments, linked to ~/.bashrc.d
├── packages/apt.txt     apt packages install.sh installs
├── packages/skills.txt  global AI/agent skills install.sh installs
├── docs/bashrc.md       what every alias, function and hook does
└── README.md
```

## Install

```bash
git clone <repository-url> ~/dotfiles
~/dotfiles/install.sh
```

Any clone location works; the script resolves paths from its own directory.

`install.sh`:

1. Refuses to run as root or on anything but an Ubuntu/Debian system.
2. Installs the packages listed in `packages/apt.txt` (the Microsoft-fonts EULA is preseeded so the run stays unattended).
3. Links `~/.bashrc.d` to `bash/` in the repo, moving aside any existing `~/.bashrc.d`.
4. Replaces the marker block in `~/.bashrc` with a loop that sources `~/.bashrc.d/*.sh`; everything outside the markers is untouched.
5. Moves `~/.bash_aliases` to a timestamped backup, since its contents now live in the repo.
6. On Ubuntu, adds the vendor repositories below and installs their apps.
7. Installs the non-apt developer/user tools (nvm, Bun, lerd, opencode, herdr, GitKraken) and the global skills manifest.

Files it replaces are kept as `<name>.bak-<timestamp>`. Running it again is safe and changes nothing when everything is current. Open a new shell afterwards, or run `source ~/.bashrc`.

## Shell

| Fragment | Contains |
| --- | --- |
| `bash/10-aliases.sh` | `art`, `sail`, and the update functions: `update-apt-all`, `update-dev-tools`, `update-user-tools`, and `update-all` |
| `bash/30-xone-pair.sh` | `xone-pair`, the Xbox Wireless Adapter pairing helper |
| `bash/90-herdr-hook.sh` | herdr live tab-naming hook |

See [docs/bashrc.md](docs/bashrc.md) for what each one does and the tools it depends on.

## Packages

`packages/apt.txt` is the apt package list, one per line; comments and blank lines are ignored. It holds the dev tools and user apps installed from the Ubuntu repositories.

## Third-party apps

On Ubuntu, `install.sh` also registers these vendor repositories and installs their packages:

| Vendor | Apps |
| --- | --- |
| Microsoft | VS Code, Microsoft Edge |
| Google | Google Chrome (amd64) |
| Docker | Docker Engine, CLI, containerd, buildx, Compose |
| GitHub | GitHub CLI (`gh`) |
| Cloudflare | `cloudflared`, Cloudflare WARP |
| Slack | Slack Desktop |
| Spotify | Spotify |
| Valve | Steam launcher (amd64) |
| Bruno | Bruno (amd64) |
| TablePlus | TablePlus |
| Ghostty | Ghostty (PPA) |
| ArtCraft | Launcher and Craft apps (DeckCraft, GridCraft, PdfCraft, PhotoCraft, VectorCraft, WordCraft) |

Docker follows Docker's Ubuntu instructions: its keyring and `.sources` file, the five engine packages, and the post-install step that adds you to the `docker` group. Group membership only applies to a new session, so log out and back in (or run `newgrp docker`) before using `docker` without `sudo`.

Because ArtCraft now comes from an apt repository, `update-apt-all` keeps its launcher and apps current; `update-user-tools` is reduced to WinBox.

## Developer and user tools

Not everything ships through apt. `install.sh` also installs:

| Tool | Method |
| --- | --- |
| nvm | latest release, then the latest LTS Node, default alias, and latest npm |
| Bun | official installer |
| lerd | official installer; provides the composer shim |
| opencode | official installer for the CLI, plus the latest desktop `.deb` |
| herdr | CLI and desktop-app installers |
| GitKraken | current official `.deb` (amd64) |
| Global AI/agent skills | `bunx skills add <source> -g --all` for every entry in `packages/skills.txt` |

## Unattended install

The longer-term goal is an unattended setup for a clean Ubuntu installation, so a fresh machine gets the packages and shell configuration without interactive steps. This is not implemented yet.

Ubuntu's autoinstall reference, for when it is:
<https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html>

## Notes

- Target platform: Ubuntu. `install.sh` accepts Debian as well, since the package list is apt-based.
- Machine-specific settings, secrets and hardware helpers stay out of the repository.
