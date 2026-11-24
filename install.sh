#!/usr/bin/env bash
# Apply this repository to the current machine. Safe to re-run.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
stamp=$(date +%Y%m%d-%H%M%S)

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# --- guards ----------------------------------------------------------------
[ "$(id -u)" -ne 0 ] || die "run as your user, not root (apt asks for sudo when needed)"
# shellcheck disable=SC1091
. /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in
  *ubuntu*|*debian*) ;;
  *) die "unsupported OS: ${PRETTY_NAME:-unknown} (Ubuntu/Debian only)" ;;
esac

# --- packages --------------------------------------------------------------
mapfile -t packages < <(grep -vE '^[[:space:]]*(#|$)' "$repo_dir/packages/apt.txt")
if [ "${#packages[@]}" -gt 0 ]; then
  say "Installing ${#packages[@]} packages from packages/apt.txt..."
  sudo apt-get update
  sudo apt-get install -y "${packages[@]}"
else
  say "packages/apt.txt has no entries; skipping apt"
fi

# --- shell fragments -------------------------------------------------------
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
aliases="$HOME/.bash_aliases"
if [ -e "$aliases" ] || [ -L "$aliases" ]; then
  mv "$aliases" "$aliases.bak-$stamp"
  say "moved ~/.bash_aliases to ~/.bash_aliases.bak-$stamp (contents live in the repo now)"
fi

say ""
say "Done. Open a new shell or run: source ~/.bashrc"
