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
├── packages/apt-remove.txt  apt packages install.sh purges
├── packages/skills.txt  global AI/agent skills install.sh installs
├── docs/bashrc.md       what every alias, function and hook does
├── .shellcheckrc        ShellCheck policy used locally and in CI
├── .github/workflows/   syntax and ShellCheck CI
├── LICENSE
└── README.md
```

## Install

```bash
git clone <repository-url> ~/dotfiles
~/dotfiles/install.sh
```

Any clone location works; the script resolves paths from its own directory.

`install.sh --help` lists the flags; `--dry-run` prints the packages it would purge and exits without changing anything.

`install.sh`:

1. Refuses to run as root or on anything but Ubuntu.
2. Purges the packages listed in `packages/apt-remove.txt` (LibreOffice by default).
3. Installs the packages listed in `packages/apt.txt` (the Microsoft-fonts EULA is preseeded so the run stays unattended).
4. Links `~/.bashrc.d` to `bash/` in the repo, moving aside any existing `~/.bashrc.d`.
5. Replaces the marker block in `~/.bashrc` with a loop that sources `~/.bashrc.d/*.sh`; everything outside the markers is untouched.
6. Moves `~/.bash_aliases` to a timestamped backup, since its contents now live in the repo.
7. Adds the vendor repositories below and installs their apps.
8. Installs the non-apt developer/user tools (nvm, Bun, lerd, opencode, herdr, WinBox, GitKraken) and the global skills manifest.

Files it replaces are kept as `<name>.bak-<timestamp>`. Running it again is safe: completed steps are repeated idempotently, and the tool installers may pick up newer upstream releases. Open a new shell afterwards, or run `source ~/.bashrc`.

## Shell

| Fragment | Contains |
| --- | --- |
| `bash/10-aliases.sh` | `art`, `sail`, and the update functions: `update-dotfiles`, `update-apt-all`, `update-dev-tools`, `update-user-tools`, and `update-all` |
| `bash/30-xone-pair.sh` | `xone-pair`, the Xbox Wireless Adapter pairing helper |
| `bash/90-herdr-hook.sh` | herdr live tab-naming hook |

See [docs/bashrc.md](docs/bashrc.md) for what each one does and the tools it depends on.

## Packages

`packages/apt.txt` is the apt package list, one per line; comments and blank lines are ignored. It holds the dev tools and user apps installed from the Ubuntu repositories.

## Removals

`packages/apt-remove.txt` lists packages `install.sh` purges before installing anything. Entries are shell-style globs expanded against installed packages, so `libreoffice*` removes every installed LibreOffice component. Shared dependencies are left alone; when nothing matches, the step is skipped.

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
| WinBox | latest MikroTik zip into `~/Applications/WinBox`; `update-user-tools` keeps it current |
| GitKraken | current official `.deb` (amd64) |
| Global AI/agent skills | `bunx skills add <source> -g --all` for every entry in `packages/skills.txt` |

## Unattended install

The longer-term goal is an unattended setup for a clean Ubuntu installation, so a fresh machine gets the packages and shell configuration without interactive steps. The installer itself only needs the sudo password; a full autoinstall/cloud-init file is not implemented yet.

Ubuntu's autoinstall reference, for when it is:
<https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html>

## Notes

- Target platform: Ubuntu only. `install.sh` refuses other distributions because several packages and all vendor repositories are Ubuntu-specific.
- Machine-specific settings, secrets and hardware helpers stay out of the repository.

## License

MIT. See [LICENSE](LICENSE).
