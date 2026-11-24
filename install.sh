#!/usr/bin/env bash
# Apply this repository to the current machine. Safe to re-run.
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stamp=$(date +%Y%m%d-%H%M%S)

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

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

# --- shell fragments -------------------------------------------------------
step="shell fragments"
bashrc_d="$HOME/.bashrc.d"
fragments=$(readlink -f "$repo_dir/bash")
if [ -L "$bashrc_d" ] && [ "$(readlink -f "$bashrc_d")" = "$fragments" ]; then
  say "~/.bashrc.d already points at $repo_dir/bash"
elif [ -L "$bashrc_d" ] || [ -e "$bashrc_d" ]; then
  mv "$bashrc_d" "$bashrc_d.bak-$stamp"
  ln -s "$repo_dir/bash" "$bashrc_d"
  say "moved the old ~/.bashrc.d to ~/.bashrc.d.bak-$stamp and linked $repo_dir/bash"
else
  ln -s "$repo_dir/bash" "$bashrc_d"
  say "linked ~/.bashrc.d -> $repo_dir/bash"
fi

# --- ~/.bashrc marker block ------------------------------------------------
step="~/.bashrc marker block"
bashrc="$HOME/.bashrc"
[ -e "$bashrc" ] || : > "$bashrc"
block_start='### START: User Specific Aliases and Functions ###'
block_end='### END: User Specific Aliases and Functions ###'

render_block() {
  cat <<'EOF'
### START: User Specific Aliases and Functions ###
# Managed by install.sh from the dotfiles repo; edit ~/.bashrc.d/*.sh instead.
if [ -d "$HOME/.bashrc.d" ]; then
  for _f in "$HOME"/.bashrc.d/*.sh; do
    [ -r "$_f" ] && . "$_f"
  done
  unset _f
fi
### END: User Specific Aliases and Functions ###
EOF
}

has_start=0
has_end=0
if grep -qxF "$block_start" "$bashrc"; then has_start=1; fi
if grep -qxF "$block_end" "$bashrc"; then has_end=1; fi
[ "$has_start" = "$has_end" ] || die "~/.bashrc has an unmatched marker block; fix it by hand first"
if [ "$has_start" = 1 ]; then
  start_line=$(grep -nxF "$block_start" "$bashrc" | head -1 | cut -d: -f1)
  end_line=$(grep -nxF "$block_end" "$bashrc" | head -1 | cut -d: -f1)
  [ "$start_line" -lt "$end_line" ] || die "~/.bashrc has END before START in its marker block; fix it by hand first"
fi

tmp=$(mktemp)
if [ "$has_start" = 1 ]; then
  {
    awk -v s="$block_start" '$0==s{exit} {print}' "$bashrc"
    render_block
    awk -v e="$block_end" 'p{print} $0==e{p=1}' "$bashrc"
  } > "$tmp"
else
  {
    cat "$bashrc"
    printf '\n'
    render_block
  } > "$tmp"
fi

if cmp -s "$tmp" "$bashrc"; then
  say "~/.bashrc already up to date"
else
  cp -p "$bashrc" "$bashrc.bak-$stamp"
  cat "$tmp" > "$bashrc"
  say "updated the marker block in ~/.bashrc (backup: ~/.bashrc.bak-$stamp)"
fi
rm -f "$tmp"

# --- retired ~/.bash_aliases -----------------------------------------------
step="~/.bash_aliases"
aliases="$HOME/.bash_aliases"
if [ -e "$aliases" ] || [ -L "$aliases" ]; then
  mv "$aliases" "$aliases.bak-$stamp"
  say "moved ~/.bash_aliases to ~/.bash_aliases.bak-$stamp (contents live in the repo now)"
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

# global AI/agent skills, installed from the manifest on every run
step="global skills"
while IFS= read -r skill_source; do
  case $skill_source in ''|'#'*) continue ;; esac
  bunx skills add "$skill_source" -g --all
done < "$repo_dir/packages/skills.txt"

say "Developer and user tools installed."

say ""
say "Done. Open a new shell or run: source ~/.bashrc"
say "Docker: log out and back in (or run: newgrp docker) to use docker without sudo."
