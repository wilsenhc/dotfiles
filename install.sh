#!/usr/bin/env bash
# Apply this repository to the current machine. Safe to re-run.
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stamp=$(date +%Y%m%d-%H%M%S)

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# shellcheck source=lib/dotfiles.sh
. "$repo_dir/lib/dotfiles.sh"
DOTFILES_REPO_ROOT="$repo_dir"

# Install a repo file, backing up a differing target and recording it in state.
install_tracked() {
  local source=$1 target=$2 mode=$3 existed=1
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -f "$target" ] && cmp -s "$source" "$target"; then
      dotfiles_state_file "$target" "${source#"$repo_dir"/}" file \
        "$(dotfiles_sha256 "$source")" "${DOTFILES_BACKUP_SET:-}" 1 1 || true
      return 0
    fi
    dotfiles_backup_file "$target" 1 || return 1
  else
    existed=0
    dotfiles_backup_missing "$target" 1 || return 1
  fi
  install -D -m "$mode" "$source" "$target" || return 1
  dotfiles_state_file "$target" "${source#"$repo_dir"/}" file \
    "$(dotfiles_sha256 "$source")" "${DOTFILES_BACKUP_SET:-}" "$existed" 1 || true
}

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run]

Applies this dotfiles repository to the current Ubuntu machine. Safe to re-run.

  -n, --dry-run  show the packages that would be purged, then exit
  -h, --help     show this help
EOF
}

dry_run=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -n|--dry-run) dry_run=1 ;;
  "") ;;
  *) die "unknown argument: $1 (try --help)" ;;
esac
[ "$#" -le 1 ] || die "too many arguments (try --help)"

step=preflight
trap 'printf "\ninstall.sh: %s failed (line %s). Completed steps are safe to re-run.\n" "$step" "$LINENO" >&2' ERR

# --- guards ----------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || die "run as your user, not root (apt asks for sudo when needed)"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "unsupported OS: ${PRETTY_NAME:-unknown} (Ubuntu only)"

# --- removals --------------------------------------------------------------
step=removals
mapfile -t remove_patterns < <(grep -vE '^[[:space:]]*(#|$)' "$repo_dir/packages/apt-remove.txt" || true)
remove_pkgs=()
for pattern in "${remove_patterns[@]}"; do
  while read -r status pkg; do
    if [ "$status" = installed ] && [ -n "$pkg" ]; then remove_pkgs+=("$pkg"); fi
  done < <(dpkg-query -W -f='${db:Status-Status} ${binary:Package}\n' "$pattern" 2>/dev/null || true)
done
if [ "${#remove_pkgs[@]}" -gt 0 ]; then
  mapfile -t remove_pkgs < <(printf '%s\n' "${remove_pkgs[@]}" | sort -u)
fi

if [ "$dry_run" = 1 ]; then
  if [ "${#remove_pkgs[@]}" -gt 0 ]; then
    say "Would remove ${#remove_pkgs[@]} package(s): ${remove_pkgs[*]}"
  else
    say "No packages to remove."
  fi
  say "Dry run: no changes made."
  exit 0
fi

if [ "${#remove_pkgs[@]}" -gt 0 ]; then
  say "Removing ${#remove_pkgs[@]} packages from packages/apt-remove.txt..."
  sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${remove_pkgs[@]}"
else
  say "No packages to remove."
fi

# --- packages --------------------------------------------------------------
step="apt packages"
mapfile -t packages < <(grep -vE '^[[:space:]]*(#|$)' "$repo_dir/packages/apt.txt" || true)
if [ "${#packages[@]}" -gt 0 ]; then
  say "Installing ${#packages[@]} packages from packages/apt.txt..."
  # ttf-mscorefonts-installer stops on the EULA prompt otherwise
  printf '%s\n' 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' |
    sudo debconf-set-selections
  sudo apt-get update || say "warning: some apt sources failed; continuing so the third-party repositories can be repaired"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
else
  say "packages/apt.txt has no entries; skipping apt"
fi

dotfiles_state_init || say "warning: could not initialize the state manifest"
dotfiles_state_repo "$repo_dir" || true
trap 'dotfiles_backup_finish >/dev/null 2>&1 || true' EXIT

# --- shell fragments -------------------------------------------------------
step="shell fragments"
bashrc_d="$HOME/.bashrc.d"
fragments=$(readlink -f "$repo_dir/bash")
bashrc_d_existed=1
if [ -L "$bashrc_d" ] && [ "$(readlink -f "$bashrc_d")" = "$fragments" ]; then
  say "~/.bashrc.d already points at $repo_dir/bash"
else
  if [ -L "$bashrc_d" ] || [ -e "$bashrc_d" ]; then
    dotfiles_backup_file "$bashrc_d" 1
    rm -rf "$bashrc_d"
  else
    bashrc_d_existed=0
    dotfiles_backup_missing "$bashrc_d" 1
  fi
  ln -s "$repo_dir/bash" "$bashrc_d"
  say "linked ~/.bashrc.d -> $repo_dir/bash"
fi
dotfiles_state_file "$bashrc_d" "bash" symlink "" "${DOTFILES_BACKUP_SET:-}" "$bashrc_d_existed" 1 || true

# --- ~/.bashrc marker block ------------------------------------------------
step="~/.bashrc marker block"
bashrc="$HOME/.bashrc"
bashrc_existed=1
if [ ! -e "$bashrc" ]; then
  bashrc_existed=0
  dotfiles_backup_missing "$bashrc"
fi
block_start='### START: User Specific Aliases and Functions ###'
block_end='### END: User Specific Aliases and Functions ###'
block_content=$(cat <<'EOF'
# Managed by install.sh from the dotfiles repo; edit ~/.bashrc.d/*.sh instead.
if [ -d "$HOME/.bashrc.d" ]; then
  for _f in "$HOME"/.bashrc.d/*.sh; do
    [ -r "$_f" ] && . "$_f"
  done
  unset _f
fi
EOF
)
if ! dotfiles_upsert_block "$bashrc" "$block_start" "$block_end" "$block_content" "$bashrc_existed"; then
  die "~/.bashrc has an unmatched marker block; fix it by hand first"
fi
say "~/.bashrc marker block is up to date"
dotfiles_state_file "$bashrc" "install.sh" marker-block \
  "$(dotfiles_sha256 "$bashrc")" "${DOTFILES_BACKUP_SET:-}" "$bashrc_existed" 1 || true

# --- ~/.profile.d fragments ------------------------------------------------
step="~/.profile.d"
profile_d="$HOME/.profile.d"
profile_fragments="$repo_dir/profile"
profile_existed=1
if [ -L "$profile_d" ] && [ "$(readlink -f "$profile_d")" = "$profile_fragments" ]; then
  say "~/.profile.d already points at $profile_fragments"
else
  if [ -L "$profile_d" ] || [ -e "$profile_d" ]; then
    dotfiles_backup_file "$profile_d" 1
    rm -rf "$profile_d"
  else
    profile_existed=0
    dotfiles_backup_missing "$profile_d" 1
  fi
  ln -s "$profile_fragments" "$profile_d"
  say "linked ~/.profile.d -> $profile_fragments"
fi
dotfiles_state_file "$profile_d" "profile" symlink "" "${DOTFILES_BACKUP_SET:-}" "$profile_existed" 1 || true

# --- ~/.profile marker block ------------------------------------------------
step="~/.profile marker block"
profile="$HOME/.profile"
profile_existed=1
if [ ! -e "$profile" ]; then
  profile_existed=0
  dotfiles_backup_missing "$profile"
fi
profile_start='### START: dotfiles login environment ###'
profile_end='### END: dotfiles login environment ###'
profile_content=$(cat <<'EOF'
# Managed by install.sh from the dotfiles repo; edit ~/.profile.d/*.sh instead.
if [ -d "$HOME/.profile.d" ]; then
  for _f in "$HOME"/.profile.d/*.sh; do
    [ -r "$_f" ] && . "$_f"
  done
  unset _f
fi
EOF
)
if ! dotfiles_upsert_block "$profile" "$profile_start" "$profile_end" "$profile_content" "$profile_existed"; then
  die "~/.profile has an unmatched marker block; fix it by hand first"
fi
say "~/.profile marker block is up to date"
dotfiles_state_file "$profile" "install.sh" marker-block \
  "$(dotfiles_sha256 "$profile")" "${DOTFILES_BACKUP_SET:-}" "$profile_existed" 1 || true

# --- ~/.gitconfig include ---------------------------------------------------
step="~/.gitconfig"
gitconfig="$HOME/.gitconfig"
gitconfig_existed=1
if [ ! -e "$gitconfig" ]; then
  gitconfig_existed=0
  dotfiles_backup_missing "$gitconfig"
fi
git_start='# >>> dotfiles managed include >>>'
git_end='# <<< dotfiles managed include <<<'
git_content=$(printf '[include]\n    path = "%s"\n' "$repo_dir/home/gitconfig")
if ! dotfiles_upsert_block "$gitconfig" "$git_start" "$git_end" "$git_content" "$gitconfig_existed"; then
  die "~/.gitconfig has an unmatched marker block; fix it by hand first"
fi
say "~/.gitconfig includes $repo_dir/home/gitconfig"
dotfiles_state_file "$gitconfig" "home/gitconfig" include-block \
  "$(dotfiles_sha256 "$repo_dir/home/gitconfig")" "${DOTFILES_BACKUP_SET:-}" "$gitconfig_existed" 1 || true

# --- retired ~/.bash_aliases -----------------------------------------------
step="~/.bash_aliases"
aliases="$HOME/.bash_aliases"
if [ -e "$aliases" ] || [ -L "$aliases" ]; then
  dotfiles_backup_file "$aliases" 1
  rm -f "$aliases"
  say "removed ~/.bash_aliases (backup kept)"
  dotfiles_state_file "$aliases" "retired" file "" "${DOTFILES_BACKUP_SET:-}" 1 1 || true
fi

# --- dotfiles CLI and update-check timer ------------------------------------
step="dotfiles CLI"
install_tracked "$repo_dir/bin/dotfiles" "$HOME/.local/bin/dotfiles" 755

step="OpenCode config snapshot"
if [ -d "$HOME/.config/opencode" ]; then
  if dotfiles_backup_opencode; then
    say "snapshotted OpenCode configs (redacted)"
    if [ -n "${DOTFILES_BACKUP_SET:-}" ]; then
      dotfiles_state_merge '.opencode={snapshot:$path,redacted:true} | .updated_at=$now' \
        --arg path "$DOTFILES_BACKUP_SET" --arg now "$(dotfiles_now)" || true
    fi
  else
    say "warning: could not snapshot OpenCode configs"
  fi
fi

step="update-check timer"
install_tracked "$repo_dir/systemd/user/dotfiles-update-check.service" \
  "$HOME/.config/systemd/user/dotfiles-update-check.service" 644
install_tracked "$repo_dir/systemd/user/dotfiles-update-check.timer" \
  "$HOME/.config/systemd/user/dotfiles-update-check.timer" 644
if systemctl --user daemon-reload &&
   systemctl --user enable dotfiles-update-check.timer >/dev/null 2>&1 &&
   systemctl --user restart dotfiles-update-check.timer >/dev/null 2>&1; then
  say "update-check timer enabled"
else
  say "warning: could not enable dotfiles-update-check.timer; run systemctl --user enable --now dotfiles-update-check.timer"
fi

# --- third-party repositories and apps -------------------------------------
# Repo-backed apps from the external list. Bitwarden stays out; GitKraken and
# opencode are installed in the non-apt step below.
step="third-party repositories"
if [ "${ID:-}" = ubuntu ]; then
  ubuntu_codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
  ubuntu_major=${VERSION_ID%%.*}
  arch=$(dpkg --print-architecture)
  third_party=()

  # move any other source file that already declares the same URI aside, so
  # apt does not warn about duplicate targets (backup keeps the old file).
  drop_source_uri() {
    local uri=$1 keep=$2 f
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [ -e "$f" ] || continue
      [ "$f" = "$keep" ] && continue
      if grep -qF "$uri" "$f" 2>/dev/null; then
        sudo mv "$f" "$f.bak-$stamp"
      fi
    done
  }

  say "Adding third-party repositories and installing their apps..."
  sudo install -m 0755 -d /etc/apt/keyrings

  # Microsoft: VS Code and Edge share one signing key.
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/microsoft.gpg
  sudo chmod 644 /usr/share/keyrings/microsoft.gpg
  for pair in "vscode|https://packages.microsoft.com/repos/code" \
              "microsoft-edge|https://packages.microsoft.com/repos/edge-stable"; do
    name=${pair%%|*}
    uri=${pair#*|}
    sudo tee "/etc/apt/sources.list.d/$name.sources" >/dev/null <<EOF
Types: deb
URIs: $uri
Suites: stable
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
  done
  third_party+=(code microsoft-edge-stable)

  # Google Chrome is amd64 only.
  if [ "$arch" = amd64 ]; then
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub |
      sudo gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
    sudo chmod 644 /usr/share/keyrings/google-chrome.gpg
    sudo tee /etc/apt/sources.list.d/google-chrome.sources >/dev/null <<EOF
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF
    third_party+=(google-chrome-stable)
  fi

  # Docker: drop conflicting distro packages first, then add the official repo.
  conflicts=()
  for pkg in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
    if dpkg-query -W "$pkg" >/dev/null 2>&1; then conflicts+=("$pkg"); fi
  done
  if [ "${#conflicts[@]}" -gt 0 ]; then
    say "Removing conflicting container packages: ${conflicts[*]}"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${conflicts[@]}"
  fi
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
    sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod 644 /etc/apt/keyrings/docker.asc
  drop_source_uri download.docker.com /etc/apt/sources.list.d/docker.sources
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $ubuntu_codename
Components: stable
Architectures: $arch
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  third_party+=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

  # GitHub CLI: newer than the universe/ESM package.
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo tee /etc/apt/sources.list.d/github-cli.sources >/dev/null <<EOF
Types: deb
URIs: https://cli.github.com/packages/
Suites: stable
Components: main
Architectures: $arch
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg
EOF
  third_party+=(gh)

  # Cloudflare tunnel client.
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg |
    sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  sudo chmod 644 /usr/share/keyrings/cloudflare-main.gpg
  sudo tee /etc/apt/sources.list.d/cloudflared.sources >/dev/null <<EOF
Types: deb
URIs: https://pkg.cloudflare.com/cloudflared/
Suites: any
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/cloudflare-main.gpg
EOF
  third_party+=(cloudflared)

  # Cloudflare WARP client.
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  sudo chmod 644 /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  sudo tee /etc/apt/sources.list.d/cloudflare-client.sources >/dev/null <<EOF
Types: deb
URIs: https://pkg.cloudflareclient.com/
Suites: $ubuntu_codename
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
EOF
  third_party+=(cloudflare-warp)

  # Slack.
  curl -fsSL https://packagecloud.io/slacktechnologies/slack/gpgkey |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/slacktechnologies_slack-archive-keyring.gpg
  sudo chmod 644 /usr/share/keyrings/slacktechnologies_slack-archive-keyring.gpg
  sudo tee /etc/apt/sources.list.d/slack.sources >/dev/null <<EOF
Types: deb
URIs: https://packagecloud.io/slacktechnologies/slack/debian/
Suites: jessie
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/slacktechnologies_slack-archive-keyring.gpg
EOF
  third_party+=(slack-desktop)

  # Spotify.
  drop_source_uri repository.spotify.com /etc/apt/sources.list.d/spotify.sources
  curl -fsSL https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg |
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/spotify.gpg
  sudo chmod 644 /etc/apt/keyrings/spotify.gpg
  sudo tee /etc/apt/sources.list.d/spotify.sources >/dev/null <<EOF
Types: deb
URIs: https://repository.spotify.com/
Suites: stable
Components: non-free
Architectures: $arch
Signed-By: /etc/apt/keyrings/spotify.gpg
EOF
  third_party+=(spotify-client)

  # Steam needs i386 and is amd64 only.
  if [ "$arch" = amd64 ]; then
    curl -fsSL https://repo.steampowered.com/steam/archive/stable/steam.gpg |
      sudo tee /usr/share/keyrings/steam.gpg >/dev/null
    sudo chmod 644 /usr/share/keyrings/steam.gpg
    sudo tee /etc/apt/sources.list.d/steam-stable.sources >/dev/null <<EOF
Types: deb
URIs: https://repo.steampowered.com/steam/
Suites: stable
Components: steam
Architectures: amd64 i386
Signed-By: /usr/share/keyrings/steam.gpg
EOF
    sudo dpkg --add-architecture i386
    third_party+=(steam-launcher)
  fi

  # Bruno (amd64 only). Its vendor key URL has been returning 404, so the same
  # key is fetched from the keyserver by fingerprint when that happens.
  if [ "$arch" = amd64 ]; then
    if ! curl -fsSL https://debian.usebruno.com/bruno-archive-keyring.gpg |
         sudo gpg --dearmor --yes -o /etc/apt/keyrings/bruno.gpg 2>/dev/null; then
      # the vendor URL 404s; Ubuntu's keyserver carries the same key with its UID
      curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xE598552E09C999055FEFA7159FA6017ECABE0266" |
        sudo gpg --dearmor --yes -o /etc/apt/keyrings/bruno.gpg
    fi
    sudo chmod 644 /etc/apt/keyrings/bruno.gpg
    drop_source_uri debian.usebruno.com /etc/apt/sources.list.d/bruno.sources
    sudo tee /etc/apt/sources.list.d/bruno.sources >/dev/null <<EOF
Types: deb
URIs: https://debian.usebruno.com/
Suites: bruno
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/bruno.gpg
EOF
    third_party+=(bruno)
  fi

  # TablePlus: its repo path follows the Ubuntu major version.
  drop_source_uri deb.tableplus.com /etc/apt/sources.list.d/tableplus.sources
  curl -fsSL https://deb.tableplus.com/apt.tableplus.com.gpg.key |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/tableplus-archive-keyring.gpg
  sudo chmod 644 /usr/share/keyrings/tableplus-archive-keyring.gpg
  sudo tee /etc/apt/sources.list.d/tableplus.sources >/dev/null <<EOF
Types: deb
URIs: https://deb.tableplus.com/debian/$ubuntu_major/
Suites: tableplus
Components: main
Architectures: $arch
Signed-By: /usr/share/keyrings/tableplus-archive-keyring.gpg
EOF
  third_party+=(tableplus)

  # ArtCraft: launcher and Craft apps, updated by apt like everything else.
  sudo curl -fsSL https://getartcraft.com/keys/artcraft.gpg -o /etc/apt/keyrings/artcraft.gpg
  sudo chmod 644 /etc/apt/keyrings/artcraft.gpg
  sudo curl -fsSL https://getartcraft.com/apt/artcraft.sources -o /etc/apt/sources.list.d/artcraft.sources
  third_party+=(artcraft-launcher deckcraft gridcraft pdfcraft photocraft vectorcraft wordcraft)

  # Ghostty lives in a PPA.
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
  fi
  sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu >/dev/null
  third_party+=(ghostty)

  sudo apt-get update
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${third_party[@]}"

  # Docker post-install: non-root use requires a fresh login session.
  sudo systemctl enable --now docker
  sudo groupadd --force docker
  sudo usermod -aG docker "$USER"
  if [ -d "$HOME/.docker" ]; then
    sudo chown -R "$USER:$(id -gn)" "$HOME/.docker"
    sudo chmod -R g+rwx "$HOME/.docker"
  fi
else
  say "Skipping third-party apps: their repositories are Ubuntu-specific"
fi

# --- developer and user tools (non-apt) ------------------------------------
step="developer and user tools"
say "Installing developer and user tools..."

# nvm: resolve the latest release first, since the install script URL is versioned.
nvm_tag=$(curl -sIL --max-time 20 -o /dev/null -w '%{url_effective}' https://github.com/nvm-sh/nvm/releases/latest | sed 's|.*/tag/||')
[ -n "$nvm_tag" ] || die "could not resolve the latest nvm release"
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$nvm_tag/install.sh" | bash
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
nvm install-latest-npm

curl -fsSL https://bun.sh/install | bash
export PATH="$HOME/.bun/bin:$PATH"

# lerd also provides the composer shim used by its containers
curl -fsSL https://lerd.sh/install.sh | bash

curl -fsSL https://opencode.ai/v2/install | bash

arch=$(dpkg --print-architecture)
tmpdir=$(mktemp -d)

# opencode desktop: the latest API URL redirects to the current versioned .deb
if [ "$arch" = amd64 ] || [ "$arch" = arm64 ]; then
  curl -fsSL "https://opencode.ai/update/api/latest/desktop/opencode/opencode-desktop-linux-$arch.deb" -o "$tmpdir/opencode-desktop.deb"
  opencode_sha=$(dotfiles_opencode_deb_sha256 "$arch")
  if [ -z "$opencode_sha" ]; then
    say "warning: opencode desktop checksum unavailable; continuing"
  elif ! dotfiles_verify_sha256 "$tmpdir/opencode-desktop.deb" "$opencode_sha"; then
    die "opencode desktop checksum mismatch"
  fi
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmpdir/opencode-desktop.deb"
fi

# GitKraken has no apt repo; install the current .deb like update-dev-tools does
if [ "$arch" = amd64 ]; then
  curl -fsSL https://release.gitkraken.com/linux/gitkraken-amd64.deb -o "$tmpdir/gitkraken.deb"
  sudo dpkg -i "$tmpdir/gitkraken.deb"
fi
rm -rf "$tmpdir"

curl -fsSL https://herdr.dev/install.sh | sh
curl -fsSL https://releases.herdr.dev/app/install.sh | sh

# WinBox: a zip from MikroTik, no package manager. The fragment owns the
# download helpers so this install and update-user-tools share one code path.
step=WinBox
# shellcheck source=bash/10-aliases.sh
. "$repo_dir/bash/10-aliases.sh"
if ! _uut_winbox_install_latest; then
  say "warning: WinBox install failed; update-user-tools will retry it"
fi

# PIA VPN: an official .run installer, also owned by update-user-tools.
step="PIA VPN"
if ! _uut_pia_install_latest; then
  say "warning: PIA install failed; update-user-tools will retry it"
fi

# PIA + Lerd: PIA's resolver and lerd both want 127.0.0.1:5300, and lerd's
# watcher overwrites the tunnel interface's DNS after connect. Install the
# helper that re-asserts PIA's tunnel DNS, and pin the PIA zone in lerd's
# dnsmasq so its API host is not lost to UDP DNS poisoning.
step="PIA + Lerd DNS"
if [ -x /opt/piavpn/bin/piactl ] &&
   { command -v lerd >/dev/null 2>&1 || [ -d "$HOME/.local/share/lerd" ]; }; then
  install_tracked "$repo_dir/bin/pia-dns-helper.sh" "$HOME/.local/bin/pia-dns-helper.sh" 755
  install_tracked "$repo_dir/systemd/user/pia-dns-helper.service" \
    "$HOME/.config/systemd/user/pia-dns-helper.service" 644

  pia_ips=$(curl -fsSL --max-time 8 -H 'accept: application/dns-json' \
      'https://cloudflare-dns.com/dns-query?name=api.privateinternetaccess.com&type=A' 2>/dev/null |
    grep -oE '"data":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | cut -d'"' -f4 |
    sort -u | paste -sd/ - || true)
  if [ -n "$pia_ips" ]; then
    pia_conf="$HOME/.local/share/lerd/dnsmasq/99-pia.conf"
    pia_pin="address=/privateinternetaccess.com/$pia_ips"
    if [ "$(cat "$pia_conf" 2>/dev/null)" != "$pia_pin" ]; then
      mkdir -p "${pia_conf%/*}"
      printf '%s\n' "$pia_pin" >"$pia_conf"
      if systemctl --user is-active --quiet lerd-dns; then
        systemctl --user restart lerd-dns ||
          say "warning: could not restart lerd-dns; the PIA zone pin applies on its next start"
      fi
    fi
  else
    say "warning: could not resolve the PIA zone; lerd DNS pin left unchanged"
  fi

  if [ -n "$(command -v resolvectl)" ] &&
     sudo -n -l "$(command -v resolvectl)" >/dev/null 2>&1; then
    if systemctl --user daemon-reload &&
       systemctl --user enable pia-dns-helper >/dev/null 2>&1 &&
       systemctl --user restart pia-dns-helper >/dev/null 2>&1; then
      say "PIA + Lerd DNS helper enabled."
    else
      say "warning: could not start pia-dns-helper; run: systemctl --user enable --now pia-dns-helper"
    fi
  else
    say "warning: passwordless resolvectl is unavailable; pia-dns-helper not started"
  fi
fi

# global AI/agent skills, installed from the manifest on every run
step="global skills"
while IFS= read -r skill_source; do
  case $skill_source in ''|'#'*) continue ;; esac
  bunx skills add "$skill_source" -g --all
done < "$repo_dir/packages/skills.txt"

# Impeccable ships its own CLI: it installs the OpenCode skill and the
# /impeccable command together. The generic skills list used to install only
# the skill into ~/.agents, so remove that copy before the official install.
step=Impeccable
if [ -f "$HOME/.agents/skills/impeccable/SKILL.md" ]; then
  bunx skills remove -g -y impeccable >/dev/null 2>&1 || true
fi
if [ -f "$HOME/.config/opencode/skills/impeccable/SKILL.md" ]; then
  timeout 600 bunx impeccable@latest update -y --global
else
  bunx impeccable@latest install -y --global --providers=opencode
fi

say "Developer and user tools installed."

dotfiles_state_last_run install || true
say ""
say "Done. Open a new shell or run: source ~/.bashrc"
say "Docker: log out and back in (or run: newgrp docker) to use docker without sudo."
say "Manual sign-in steps: docs/post-install.md"
say "Installed state: ~/.local/state/dotfiles/state.json"
