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
| `opencode-gui` | download + `sudo -n dpkg -i` the latest .deb, only when behind | `dpkg-query` |
| `herdr-core` | `herdr-core update` | `herdr-core --version` |
| `herdr-cli` | `herdr update` | `herdr --version` |
| `herdr-app` | official installer, only when behind | `herdr-app --version` |
| `herdr-plugins` | `herdr plugin update --yes` (runs last) | `herdr plugin list --json` |
| `global-skills` | `bunx skills update -g -y` | hash of `~/.agents/.skill-lock.json` |
| `gitkraken` | download + `sudo -n dpkg -i` the latest .deb, only when newer | `dpkg-query` |

Notes:
- `node` and `npm` need `nvm`; `global-skills` needs `bun`.
- `opencode-gui` and `gitkraken` need passwordless `sudo` for `dpkg` (`sudo -n`); without it the update reports failure instead of prompting.
- The opencode desktop app downloads roughly 250 MB, and only when a newer version exists.
- GitKraken reads the latest version from the download redirect's `Location` header by requesting one byte, so the version check costs no download; the .deb is fetched only when it is actually newer.

### update-apt-all

Refreshes apt, runs a full upgrade, and summarises what changed — one row per package.

```bash
update-apt-all              # summary only; apt output is hidden
update-apt-all -v           # stream apt's output as well
```

```
==> update-apt-all
apt update         ✓ done
apt upgrade        ✓ done
base-files         ↑ updated 13.3 => 13.4
linux-headers      + added (6.8.0-40.40)
old-lib            - removed (1.0)
linux-generic      · kept back (6.8.0-31.31)
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

Updates the user-facing apps that live outside apt: WinBox, the ArtCraft Launcher, and the Craft apps the launcher installed.

```bash
update-user-tools          # summary only; command output is hidden
update-user-tools -v       # stream downloads and installs
```

```
==> update-user-tools
winbox              ↑ updated => 4.5
artcraft-launcher   · already latest (0.19.2-1)
photocraft          · already latest (0.23.1-1)
pdfcraft            ↑ updated 0.21.1-1 => 0.22.0
```

- Refuses to run as root.
- **WinBox**: distributed by MikroTik as a zip, manually unpacked into `~/Applications/WinBox`; there is no package manager. The current version is read from `mikrotik.com/download/winbox` and remembered in `~/Applications/WinBox.version`. When it differs, the zip is downloaded and its binary compared by SHA-256 with the installed one: identical writes the marker, different replaces `WinBox` and `assets/`. Every run also rewrites the desktop entry, both `~/.local/share/applications/winbox.desktop` and the copy inside the install folder, so the paths always match the current location. User data in `~/.local/share/MikroTik/WinBox` is untouched. MikroTik publishes no checksum for the zip, so that download is HTTPS-only.
- **ArtCraft Launcher and apps**: installed as `.deb` packages with no apt repo, so `apt dist-upgrade` never touches them. The latest tag is read from each GitHub repo's `/releases/latest` redirect (no API rate limit), compared with the installed version via `dpkg --compare-versions`. Pending updates are downloaded as `<pkg>-<ver>-linux-<arch>.deb`, checked against the release's `SHA256SUMS.txt`, and installed with `apt-get`.
- Craft apps are discovered through their dpkg `Homepage` (`getartcraft.com/apps/*`), so apps installed later are picked up automatically. A package whose repo cannot be resolved is reported as skipped.
- `sudo` is requested once, and only when an ArtCraft update is actually pending, before the first install row.
- An unsupported CPU architecture (anything but amd64/arm64) skips the ArtCraft half.
- Failures mark the row and keep the log directory, which is printed at the end; exit status is `1` if any item failed.
- Set `NO_COLOR=1` to disable the color output.

### update-all

Runs the three updaters in order: apt, developer tools, then user tools.

```bash
update-all                  # all three, quietly
update-all -v               # all three, with full command output
```

- Every phase always runs, even if the previous one fails; the exit status is `1` if any failed.
- Prints no title of its own — the `==> update-apt-all`, `==> update-dev-tools` and `==> update-user-tools` titles are the steps.
- `-v` is passed to all three.
- Refuses to run as root.

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
