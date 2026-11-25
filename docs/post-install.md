# Post-install checklist

`install.sh` leaves authentication and account-bound steps to you. Run this after the installer, then check the result with `dotfiles doctor`.

## Git

- [ ] Create `~/.gitconfig.local` with your identity:

  ```ini
  [user]
      name = Your Name
      email = you@example.com
  ```

- [ ] Or set it directly with `git config --global user.name` and `git config --global user.email`; the managed include stays intact either way.

## GitHub CLI

- [ ] Run `gh auth login`.
- [ ] Confirm with `gh auth status`.

## SSH

- [ ] Add your key under `~/.ssh` with the correct permissions (`600` for the private key, `700` for the directory).
- [ ] Load it with `ssh-add` if you use an agent.

SSH configuration is intentionally not managed by this repository.

## Docker

- [ ] Log out and back in, or run `newgrp docker`, so the `docker` group membership applies.
- [ ] Confirm with `docker run --rm hello-world`.

## PIA VPN

- [ ] Open PIA and sign in.
- [ ] Confirm the daemon is running: `systemctl status piavpn`.
- [ ] If you use lerd, read [pia-lerd.md](pia-lerd.md).

## OpenCode

- [ ] Sign in to your providers so `~/.local/share/opencode/auth.json` is populated.
- [ ] Run `dotfiles doctor` and confirm the OpenCode row is `ok`.

## VS Code

- [ ] Sign in to Settings Sync, or install your extensions manually.
- [ ] VS Code settings and extensions are not managed by this repository.

## Final check

```bash
dotfiles doctor
dotfiles backups
dotfiles state
```

The update-check timer is installed and enabled by `install.sh`; confirm it with `systemctl --user status dotfiles-update-check.timer`.
