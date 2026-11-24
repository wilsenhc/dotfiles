# Shell fragments

Everything that used to live between the two marker comments in `~/.bashrc` is now in `bash/`, split by concern.

## How they load

- `~/.bashrc` contains a managed block (written by `install.sh`) that loops over `~/.bashrc.d/*.sh` in lexical order and sources each file.
- `~/.bashrc.d` is a symlink to this repository's `bash/` directory, so a fragment added here loads in every new shell.
- The numeric prefix is load order; the rest of the name says what the fragment is for. Fragments must be quiet when sourced: no output, no prompts.

To add one: create `bash/<number>-<name>.sh`, run `install.sh` (only needed if the symlink is new), open a new shell.

## 10-aliases.sh

### Aliases

| Alias | Expands to | Notes |
| --- | --- | --- |
| `art` | `[ -f artisan ] && php artisan` | Laravel artisan; only works in a project directory. |
| `sail` | `sh $( [ -f sail ] && echo sail \|\| echo vendor/bin/sail)` | Prefers a project-local `sail` script, falls back to `vendor/bin/sail`. |

### update-dev-tools

Upgrades every developer tool installed on the machine and prints one row per tool.

```bash
update-dev-tools            # summary only
update-dev-tools -v         # full command output (--verbose works too)
```

- Starts with a dim `==> update-dev-tools` title, so a chained run shows which step is executing.
- Refuses to run as root: it updates tools under `$HOME`, and root would target `/root`.
- Missing tools are **skipped**: a tool whose command is absent prints `· skipped (not installed)` and the run continues.
- Reinstallers that always download (bun, herdr app, opencode desktop) only run when the published version is newer than the installed one.
- Exit status is `0` when nothing failed, `1` if any update failed; on failure the log directory is printed instead of deleted.
- Set `NO_COLOR=1` to disable the color output.

| Label | Update path | Version read from |
| --- | --- | --- |
| `node` | `nvm install --lts` | `node --version` |
| `npm` | `nvm install-latest-npm` | `npm --version` |
| `bun` | official installer, only when behind | `bun --version` |
| `lerd` | `lerd update` | `lerd --version` |
| `opencode` | `opencode upgrade` | `opencode --version` |
| `opencode-gui` | download + `sudo -n apt-get install` the latest `.deb`, only when behind | `dpkg-query` |
| `herdr-core` | `herdr-core update` | `herdr-core --version` |
| `herdr-cli` | `herdr update` | `herdr --version` |
| `herdr-app` | official installer, only when behind | `herdr-app --version` |
| `herdr-plugins` | `herdr plugin update --yes` (after the herdr CLI) | `herdr plugin list --json` |
| `impeccable` | `timeout 600 bunx impeccable@latest update -y --global`, only when behind | `version:` in the installed `SKILL.md` |
| `global-skills` | `bunx skills update -g -y` | hash of `~/.agents/.skill-lock.json` |
| `gitkraken` | download + `sudo -n dpkg -i` the latest .deb, only when newer | `dpkg-query` |

Notes:
- `node` and `npm` need `nvm`; `impeccable` and `global-skills` need `bunx`. The latest Impeccable version comes from `bun info impeccable version`.
- `impeccable` updates the official OpenCode install, including the `/impeccable` command; it is not part of the `global-skills` set.
- `opencode-gui` and `gitkraken` need passwordless `sudo` for `apt-get`/`dpkg` (`sudo -n`); without it the update reports failure instead of prompting.
- The opencode desktop app downloads roughly 250 MB, and only when a newer version exists.
- GitKraken reads the latest version from the download redirect's `Location` header by requesting one byte, so the version check costs no download; the .deb is fetched only when it is actually newer.

### update-dotfiles

Fast-forwards the repository that owns `~/.bashrc.d` to its upstream branch.

```bash
update-dotfiles             # summary only
update-dotfiles -v          # stream git's output as well
```

```
==> update-dotfiles
dotfiles                         · already latest (a1db2e2)
```

- Finds the repository from the `~/.bashrc.d` symlink, so it works wherever the repo was cloned.
- Refuses to run with modified tracked files; untracked files are left alone.
- Uses `git pull --ff-only`: it never merges, rebases or stashes. A diverged branch or missing upstream fails and prints git's message.
- After an update, open a new shell to load the new fragments.
- Exit status is `0` when the pull succeeds (even if nothing changed), `1` otherwise.
- Set `NO_COLOR=1` to disable the color output.

### update-apt-all

Refreshes apt, runs a full upgrade, and summarises what changed — one row per package.

```bash
update-apt-all              # summary only; apt output is hidden
update-apt-all -v           # stream apt's output as well
```

```
==> update-apt-all
apt update                       ✓ done
apt upgrade                      ✓ done
base-files                       ↑ updated 13.3 => 13.4
linux-headers                    + added (6.8.0-40.40)
old-lib                          - removed (1.0)
linux-generic                    · kept back (6.8.0-31.31)
```

- Refuses to run as root; sudo is used only for the apt commands.
- Authenticates sudo up front (`sudo -v`), so the password prompt appears before the first row instead of interrupting it.
- The summary is computed by diffing `dpkg-query` snapshots taken before and after, so dependency installs and removals appear too.
- Row meanings: `↑ updated old => new`, `+ added (version)`, `- removed (version)`, `· kept back (version)`.
- **Kept back** means apt listed the package as upgradable but its version did not change — held packages and Ubuntu's phased updates, the usual reason `apt list -u` shows something the upgrade does not apply.
- With nothing changed, prints `apt · nothing changed`.
- apt's own output is hidden unless `-v`; on failure the last ten log lines are shown and the log directory is kept and printed. On success it is deleted.
- Conffile prompts are resolved with `--force-confdef --force-confold`: existing configuration files win, so a hidden run can never stall waiting for an answer.
- When `apt update` fails, the upgrade is skipped and reported, but the function still returns normally after summarising.
- Exit status is `0` when both phases succeed, `1` otherwise.
- Set `NO_COLOR=1` to disable the color output.

### update-user-tools

Updates the user-facing app that still lives outside apt: WinBox.

```bash
update-user-tools          # summary only; command output is hidden
update-user-tools -v       # stream downloads and installs
```

```
==> update-user-tools
winbox                           · already latest (4.5)
```

- Refuses to run as root.
- **WinBox**: distributed by MikroTik as a zip, manually unpacked into `~/Applications/WinBox`; there is no package manager. `install.sh` installs it when missing; this function updates an existing copy. The current version is read from `mikrotik.com/download/winbox` and remembered in `~/Applications/WinBox.version`. When it differs, the zip is downloaded and its binary compared by SHA-256 with the installed one: identical writes the marker, different replaces `WinBox` and `assets/`. Every run also rewrites the desktop entry, both `~/.local/share/applications/winbox.desktop` and the copy inside the install folder, so the paths always match the current location. User data in `~/.local/share/MikroTik/WinBox` is untouched. MikroTik publishes no checksum for the zip, so that download is HTTPS-only.
- The ArtCraft Launcher and Craft apps are installed from ArtCraft's APT repository by `install.sh`, so `update-apt-all` keeps them current and they no longer need their own updater.
- Failures mark the row and keep the log directory, which is printed at the end; exit status is `1` if any item failed.
- Set `NO_COLOR=1` to disable the color output.

### update-all

Runs the four updaters in order: dotfiles, apt, developer tools, then user tools.

```bash
update-all                  # all four, quietly
update-all -v               # all four, with full command output
```

- Every phase always runs, even if the previous one fails; the exit status is `1` if any failed.
- Each phase prints its own title, so a chained run shows which step is executing.
- `-v` is passed to all four.
- Refuses to run as root.
- If `update-dotfiles` pulls new fragments, the current shell keeps the old functions until a new shell is opened.

## 30-xone-pair.sh

Defines `xone-pair`, which opens the Xbox Wireless Adapter's 60-second pairing window and waits for a controller to connect.

- Needs the `xone-dongle` driver (`/sys/bus/usb/drivers/xone-dongle/`), `journalctl`, and `sudo` for `modprobe` / writing the pairing window.
- Recovers a radio left without firmware by a boot-time probe that raced the root filesystem: it reloads the driver and retries.
- Forces a fresh window by writing `0` then `1`, because writing `1` while it already reads `1` is a no-op in the driver.
- Hardware-specific but harmless on machines without the adapter: it just reports that no adapter is bound.

## 90-herdr-hook.sh

Sources `shell/hook.bash` from the `herdr-automatic-rename` plugin when it is installed (under `~/.config/herdr/plugins/github/`), giving live tab names. A no-op when the plugin is absent.

## ~/.bash_aliases

Retired. Ubuntu's `.bashrc` sources `~/.bash_aliases` if present, but its only content (the `xone-pair` function) now lives in `30-xone-pair.sh`. `install.sh` moves any existing `~/.bash_aliases` to a timestamped backup.
