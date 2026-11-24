# dotfiles

My dotfiles, shell scripts and configuration files, kept in one repository so that any Ubuntu machine I use can be set up the same way every time.

## Goal

Make a fresh Ubuntu installation feel like home in one step:

- **Reproducible** — the same files, settings and tools on every machine, every time.
- **Installable** — a single command to apply the repository to a new installation.
- **Portable** — safe to run on a machine that already has some of these files; nothing is lost silently.

## What belongs here

| Path | Contents |
| --- | --- |
| Shell config | `.bashrc`, `.profile`, aliases, prompt |
| Editor and tool config | Git, SSH, tmux, and other tools' dotfiles |
| `bin/` or `scripts/` | Bash scripts and helpers, made available on `PATH` |
| Packages | Lists of apt packages and other tooling each machine should have |

## Installation

There is no installer yet. The intended flow is:

```bash
git clone <repository-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer will symlink the configuration files into `$HOME`, install the packages the repository declares, and keep backups of anything it replaces.

## Status

Work in progress. The repository is being built up piece by piece; this README describes the target, and each piece lands as it is added.

## Notes

- Target platform: Ubuntu.
- Machine-specific settings (secrets, hostnames, hardware tweaks) should stay out of the repository.
