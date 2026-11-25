# Configuration

## Git

`home/gitconfig` holds the shared Git settings:

- `init.defaultBranch=main`
- `pull.ff=only`
- `fetch.prune=true`
- `push.autoSetupRemote=true`
- `color.ui=auto`
- aliases `st`, `co`, `br`, `lg`, `last`, `unstage`

`install.sh` adds a managed `[include]` block to `~/.gitconfig` rather than symlinking the file, so `git config --global` never writes into the repository. The managed file includes `~/.gitconfig.local`, which is where the machine-specific identity belongs:

```ini
[user]
    name = Your Name
    email = you@example.com
```

The repository itself contains no name or email, and `~/.gitconfig.local` is not managed or backed up as part of the repo.

## Login environment

`~/.profile` is read by login shells: TTY logins, SSH logins, and some display-manager sessions. It is not read by every GUI application or by non-login interactive shells; those read `~/.bashrc`.

`install.sh` appends a marker block to `~/.profile` that sources `~/.profile.d/*.sh`. `~/.profile.d` points at the repository's `profile/` directory, the same pattern as `~/.bashrc.d` and `bash/`.

- `profile/00-env.sh` sources `bash/00-env.sh`, keeping the login and interactive environments identical.
- `profile/99-local.sh` sources `~/.profile.local` if it exists.
- `bash/99-local.sh` sources `~/.bashrc.local` if it exists.

`bash/00-env.sh` adds these directories to `PATH` when they exist:

- `~/.local/bin`
- `~/.bun/bin`
- `~/.opencode/bin`
- `~/.config/composer/vendor/bin`
- `~/.local/share/lerd/bin`

It also sets `PAGER=less` and `LESS=-R` unless already set. `EDITOR` and `BROWSER` are deliberately left to `~/.profile.local`.

If a GUI application needs an environment variable that it does not inherit from `.profile`, use `~/.config/environment.d/*.conf`; that directory is not managed by this repository.

## Host-local files

Machine-specific, non-secret values live in:

- `~/.gitconfig.local`
- `~/.profile.local`
- `~/.bashrc.local`

These files are not tracked and are not stored in the backup manifest. Secrets, API keys, passwords and tokens belong in a password manager, not these files.

## OpenCode

`install.sh` snapshots the user-authored OpenCode configuration before installing or updating tools. The snapshot is stored in the normal backup set but is redacted and excluded from `dotfiles restore`:

- included: `opencode.jsonc`, `tui.jsonc`, `cli.json`, `AGENTS.md`, `commands/`, `plugins/`, `herdr-tui-session.js`, `herdr-opencode/`
- excluded: `node_modules/`, installed skills, `service.json`, `auth.json`, the OpenCode database and logs
- redacted: keys whose names match `env`, `apiKey`, `token`, `secret` or `password`, including `x-api-key` headers

Because the snapshot has no credentials, restoring it would silently lose access tokens and service passwords. `dotfiles restore` reports it as a skipped snapshot instead. Plugin code may still reference environment variable names (for example `process.env.HERDR_PANE_ID`); only values and credential-bearing keys are excluded.
