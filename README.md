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
2. Installs the packages listed in `packages/apt.txt`.
3. Links `~/.bashrc.d` to `bash/` in the repo, moving aside any existing `~/.bashrc.d`.
4. Replaces the marker block in `~/.bashrc` with a loop that sources `~/.bashrc.d/*.sh`; everything outside the markers is untouched.
5. Moves `~/.bash_aliases` to a timestamped backup, since its contents now live in the repo.

Files it replaces are kept as `<name>.bak-<timestamp>`. Running it again is safe and changes nothing when everything is current. Open a new shell afterwards, or run `source ~/.bashrc`.

## Shell

| Fragment | Contains |
| --- | --- |
| `bash/10-aliases.sh` | `art`, `sail`, and the update functions: `update-apt-all`, `update-dev-tools`, `update-user-tools`, and `update-all` |
| `bash/30-xone-pair.sh` | `xone-pair`, the Xbox Wireless Adapter pairing helper |
| `bash/90-herdr-hook.sh` | herdr live tab-naming hook |

See [docs/bashrc.md](docs/bashrc.md) for what each one does and the tools it depends on.

## Packages

`packages/apt.txt` is the apt package list, one per line; comments and blank lines are ignored. The current list is deliberately small and grows as gaps appear on fresh installs.

## Notes

- Target platform: Ubuntu. `install.sh` accepts Debian as well, since the package list is apt-based.
- Machine-specific settings, secrets and hardware helpers stay out of the repository.
