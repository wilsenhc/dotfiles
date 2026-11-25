# dotfiles

My dotfiles, shell scripts and configuration files, kept in one repository so that any Ubuntu machine I use can be set up the same way every time.

## Goal

- **Repeatable** — the same packages, tools and managed configuration on every machine. Versions are not pinned; see [Versioning](#versioning).
- **Installable** — one script applies the repository to a fresh Ubuntu installation.
- **Safe to re-run** — anything the installer replaces is backed up first and can be restored.

## Status

Implemented:

- apt package installation and removal, plus the vendor repositories listed below
- shell fragments loaded from `~/.bashrc.d`, with aliases and the update commands
- Git config, login environment, host-local `.local` includes, and OpenCode config snapshots
- backup sets, state manifest, `dotfiles doctor`, restore, and the weekly update check
- non-apt developer/user tools, global AI skills, and the PIA + lerd DNS helper
- best-effort checksum verification and CI for ShellCheck and installer flags

Not managed by this repository yet:

- SSH configuration (intentionally left manual)
- prompt, history and completion customization
- editor and application configs such as VS Code, Ghostty and tmux
- credential stores and secrets
- a general linker for arbitrary application configs (only Git, profile and OpenCode are managed)
- unattended autoinstall and full checksum coverage for every vendor

## Layout

```
dotfiles/
├── install.sh           applies this repository to the current machine
├── bash/                shell fragments, linked to ~/.bashrc.d
├── bin/                 dotfiles CLI and helpers installed into ~/.local/bin
├── home/                managed config files (Git)
├── lib/                 shared state and backup helpers
├── profile/             login fragments, linked to ~/.profile.d
├── packages/apt.txt     apt packages install.sh installs
├── packages/apt-remove.txt  apt packages install.sh purges
├── packages/skills.txt  global AI/agent skills install.sh installs
├── systemd/user/        user units installed into ~/.config/systemd/user
├── docs/bashrc.md       what every alias, function and hook does
├── docs/configuration.md  Git, login environment and host-local files
├── docs/operations.md   backups, state, doctor, checksums and update checks
├── docs/pia-lerd.md     the PIA VPN + lerd DNS compatibility setup
├── docs/post-install.md manual sign-in checklist
├── .shellcheckrc        ShellCheck policy used locally and in CI
├── .github/workflows/   syntax and ShellCheck CI
├── LICENSE
└── README.md
```

## Install

```bash
git clone https://github.com/wilsenhc/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Any clone location works; the script resolves paths from its own directory.

`install.sh --help` lists the flags; `--dry-run` prints the packages it would purge and exits without changing anything.

`install.sh`:

1. Refuses to run as root or on anything but Ubuntu.
2. Purges the packages listed in `packages/apt-remove.txt` (LibreOffice by default).
3. Installs the packages listed in `packages/apt.txt` (the Microsoft-fonts EULA is preseeded so the run stays unattended).
4. Links `~/.bashrc.d` to `bash/` and `~/.profile.d` to `profile/`, moving existing directories aside through the backup system.
5. Replaces the marker block in `~/.bashrc` with a loop that sources `~/.bashrc.d/*.sh`; everything outside the markers is untouched.
6. Appends a marker block to `~/.profile` that sources `~/.profile.d/*.sh`.
7. Adds a managed `[include]` block to `~/.gitconfig`, preserving user settings and keeping identity in `~/.gitconfig.local`.
8. Removes `~/.bash_aliases` after backing it up, since its contents now live in the repo.
9. Installs the `dotfiles` CLI, snapshots OpenCode configs, and enables the weekly update-check timer.
10. Adds the vendor repositories below and installs their apps.
11. Installs the non-apt developer/user tools (nvm, Bun, lerd, opencode, herdr, WinBox, PIA VPN, GitKraken), the global skills manifest, and Impeccable's OpenCode skill and `/impeccable` command. When lerd is also present, it installs the PIA DNS helper and zone pin.

Files it replaces under `$HOME` are copied to `~/.local/state/dotfiles/backups/<timestamp>/` with a manifest; the last ten sets are kept. `dotfiles restore <timestamp>` puts a set back. Conflicting apt source files keep a `.bak-<timestamp>` beside the original. Running the installer again is safe: completed steps are repeated idempotently, and the tool installers may pick up newer upstream releases. Open a new shell afterwards, or run `source ~/.bashrc`.

## Updating

`update-all` runs the four updaters in order:

```bash
update-all          # summary only
update-all -v       # full command output
```

It runs `update-dotfiles`, `update-apt-all`, `update-dev-tools` and `update-user-tools`, and each can also be run alone. See [docs/bashrc.md](docs/bashrc.md) for the per-tool behavior.

`dotfiles update-check` reports repository commits and tool updates without installing anything. The weekly user timer runs it on Monday at 10:00, sends a desktop notification when something is pending, and logs to `~/.local/state/dotfiles/update-check.log`.

## Versioning

Every installer fetches the latest available version. There is no lockfile, no apt snapshot and no version matrix: two installs on different dates can produce different versions. That is intentional. `update-all` is the supported way to keep an existing machine current, and the backup sets cover managed files, not package or tool versions.

## Shell

| Fragment | Contains |
| --- | --- |
| `bash/00-env.sh` | shared `PATH`, `PAGER` and `LESS` for login and interactive shells |
| `bash/10-aliases.sh` | `art`, `sail`, and the update functions: `update-dotfiles`, `update-apt-all`, `update-dev-tools`, `update-user-tools`, `update-all`, plus state recording |
| `bash/30-xone-pair.sh` | `xone-pair`, the Xbox Wireless Adapter pairing helper |
| `bash/90-herdr-hook.sh` | herdr live tab-naming hook |
| `bash/99-local.sh` | sources `~/.bashrc.local` |

See [docs/bashrc.md](docs/bashrc.md) for what each one does and the tools it depends on.

## Configuration, state and backups

- Git settings, login environment, host-local files and OpenCode snapshots: [docs/configuration.md](docs/configuration.md)
- Backups, restore, state manifest, doctor, checksums and the update timer: [docs/operations.md](docs/operations.md)
- Manual sign-in steps after install: [docs/post-install.md](docs/post-install.md)

`dotfiles doctor` checks the machine, `dotfiles backups` lists restore points, and `dotfiles state` prints the inventory at `~/.local/state/dotfiles/state.json`.

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

Because ArtCraft now comes from an apt repository, `update-apt-all` keeps its launcher and apps current; `update-user-tools` is reduced to WinBox and PIA VPN.

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
| PIA VPN | official Linux `.run` from the `pia-foss/desktop` release into `/opt/piavpn`; `update-user-tools` keeps it current |
| GitKraken | current official `.deb` (amd64) |
| Impeccable | `bunx impeccable install --providers=opencode -y --global`, then `bunx impeccable update -y --global` |
| Global AI/agent skills | `bunx skills add <source> -g --all` for every entry in `packages/skills.txt` |

Impeccable has its own installer because it registers the `/impeccable` command as well as the skill, so it is not in `packages/skills.txt`.

PIA VPN publishes no apt repository. `install.sh` runs the official `.run` installer, which sets up the `/opt/piavpn` install and its systemd service; `update-user-tools` downloads and reruns a newer one over the existing install, keeping settings and account data. On machines with lerd, `install.sh` also installs the PIA DNS helper and pins the PIA API zone in lerd's dnsmasq; see [docs/pia-lerd.md](docs/pia-lerd.md).

## Unattended install

The longer-term goal is an unattended setup for a clean Ubuntu installation, so a fresh machine gets the packages and shell configuration without interactive steps. The installer itself only needs the sudo password; a full autoinstall/cloud-init file is not implemented yet.

Ubuntu's autoinstall reference, for when it is:
<https://canonical-subiquity.readthedocs-hosted.com/en/latest/intro-to-autoinstall.html>

## Notes

- Target platform: Ubuntu only. `install.sh` refuses other distributions because several packages and all vendor repositories are Ubuntu-specific.
- SSH configuration is intentionally not managed; keys and host rules stay manual.
- Machine-specific non-secret values belong in `~/.gitconfig.local`, `~/.profile.local` or `~/.bashrc.local`. Secrets belong in a password manager.
- The xone-pair helper and the PIA + lerd DNS workaround are portable, checked-in exceptions to the “hardware stays out” rule; general hardware quirks still stay out.
- Versions are latest-by-design; see [Versioning](#versioning).

## License

MIT. See [LICENSE](LICENSE).
