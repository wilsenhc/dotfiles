# Operations

## The `dotfiles` command

`install.sh` installs `bin/dotfiles` to `~/.local/bin/dotfiles`.

```bash
dotfiles doctor                 # check the machine against the expected setup
dotfiles backups                # list backup sets
dotfiles restore <timestamp>    # restore a set; keeps installer-created files
dotfiles restore <timestamp> --delete-created
dotfiles state                  # pretty-print the state manifest
dotfiles state --path           # print the manifest path
dotfiles update-check           # check repo and tool updates (what the timer runs)
```

## Backups

Every file the installer replaces or edits is copied first to:

```
~/.local/state/dotfiles/backups/<timestamp>/
```

The set has a `manifest.json` recording each target, whether it existed, its SHA-256, mode, and whether it is restorable. Directories are copied recursively; symlinks are preserved. The directory is mode `700` and the manifest is mode `600`.

Only the ten most recent sets are kept. A set with no entries is discarded.

`dotfiles restore <timestamp>` restores files that existed before install and overwrites their current contents. Files that the installer created are reported and kept unless `--delete-created` is passed. OpenCode snapshots are always skipped because they are redacted.

## State

`~/.local/state/dotfiles/state.json` is a machine-readable inventory:

- schema version and hostname
- repository path, commit and remote
- managed files with source, kind, SHA-256, backup set and whether they existed
- tool versions and the last check time
- backup sets and the last one written
- last run of each update/install command

`install.sh` writes the full manifest. `update-*` functions refresh the tool rows and last-run entries through `lib/dotfiles.sh`. The file is atomically replaced with `jq` and is never committed.

## Doctor

`dotfiles doctor` reports:

- Git identity (including includes)
- GitHub CLI authentication
- SSH keys
- Docker group membership
- PIA installation and service state
- OpenCode auth file
- state manifest presence
- update-check timer state

`ok` means the check passed, `manual` is a step only you can complete, and `missing` is a missing installed component. The command exits `1` when anything is `missing`; `manual` does not fail.

## Update checks

The weekly user timer runs `dotfiles update-check` on Monday at 10:00 with a randomized delay:

- `systemd/user/dotfiles-update-check.timer`
- `systemd/user/dotfiles-update-check.service`

The check runs `git fetch` in the repository, compares `HEAD` with its upstream, and calls `update-dev-tools --check` and `update-user-tools --check`. It never installs anything and never asks for sudo.

When something is pending it sends a desktop notification through `notify-send`. Every run also appends a line to `~/.local/state/dotfiles/update-check.log`, which is the fallback when no desktop session is available.

`--check` reuses each tool's published-version lookup. Tools without a separate latest-version endpoint report `? check unavailable`; `update-dev-tools` and `update-user-tools` still perform those updates when run normally.

Check the timer with:

```bash
systemctl --user status dotfiles-update-check.timer
systemctl --user list-timers dotfiles-update-check.timer
```

## Checksums

Verification is best-effort because publishers differ:

| Artifact | Verification |
| --- | --- |
| apt packages and vendor repositories | APT `InRelease` signatures and package hashes |
| Impeccable | npm registry integrity verified by Bun |
| opencode desktop | SHA-256 from the desktop manifest |
| WinBox | SHA-256 from MikroTik's `.sha256` sidecar |
| herdr | its official installer verifies the published SHA-256 |
| Bun, lerd | published sums/signatures exist, but the current install path pipes the vendor script; not yet verified |
| nvm | signed Git tag, but the installer script itself is not verified |
| PIA VPN | no publisher checksum; the makeself archive only self-checks its MD5 |
| GitKraken | no publisher checksum found |

A checksum mismatch stops that install or update. An unavailable checksum prints a warning and continues. PIA, GitKraken and nvm are therefore HTTPS-only and documented as such.

## Versioning

This repository installs the latest available version of every tool by design. There is no lockfile, no pinned apt snapshot and no version matrix: two installs on different dates can produce different versions. `update-all` is the supported way to keep an existing machine current.

The ten backup sets provide rollback for managed files, not for package or tool versions.
