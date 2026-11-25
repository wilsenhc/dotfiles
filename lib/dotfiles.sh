# Shared helpers for install.sh, bin/dotfiles and the update functions.
# Sourced, not executed; keep this file quiet.

DOTFILES_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
DOTFILES_STATE_FILE="$DOTFILES_STATE_DIR/state.json"
DOTFILES_BACKUP_DIR="$DOTFILES_STATE_DIR/backups"
DOTFILES_BACKUP_KEEP="${DOTFILES_BACKUP_KEEP:-10}"

dotfiles_now() { date -u +%FT%TZ; }

dotfiles_repo_root() {
  if [ -n "${DOTFILES_REPO_ROOT:-}" ] && [ -d "$DOTFILES_REPO_ROOT" ]; then
    printf '%s\n' "$DOTFILES_REPO_ROOT"
    return 0
  fi
  local link
  link=$(readlink -f "$HOME/.bashrc.d" 2>/dev/null) || link=
  if [ -n "$link" ] && [ -d "$link" ]; then
    dirname "$link"
    return 0
  fi
  return 1
}

dotfiles_sha256() {
  [ -f "$1" ] || return 1
  sha256sum "$1" | cut -d' ' -f1
}

# Verify a file against an expected SHA-256. Returns 0 on match, 1 on mismatch.
dotfiles_verify_sha256() {
  local file=$1 expected=$2 actual
  [ -n "$expected" ] && [ -f "$file" ] || return 1
  actual=$(dotfiles_sha256 "$file") || return 1
  [ "$actual" = "$expected" ]
}

# Print the published opencode desktop .deb SHA-256 for amd64 or arm64.
dotfiles_opencode_deb_sha256() {
  local arch=$1
  curl -fsSL --max-time 20 https://opencode.ai/update/api/latest/desktop/opencode 2>/dev/null |
    jq -r --arg key "opencode-desktop-linux-$arch.deb" '.metadata.files[$key].sha256 // empty' 2>/dev/null
}

# --- state -----------------------------------------------------------------

dotfiles_state_init() {
  command -v jq >/dev/null 2>&1 || return 1
  mkdir -p "$DOTFILES_STATE_DIR" || return 1
  chmod 700 "$DOTFILES_STATE_DIR" 2>/dev/null || true
  [ -f "$DOTFILES_STATE_FILE" ] && return 0
  jq -n --arg host "$(hostname 2>/dev/null || echo unknown)" --arg now "$(dotfiles_now)" \
    '{schema:1,host:$host,updated_at:$now,repo:{},managed_files:[],tools:{},backups:[],last_run:{},opencode:{}}' \
    >"$DOTFILES_STATE_FILE" || return 1
  chmod 600 "$DOTFILES_STATE_FILE" 2>/dev/null || true
}

# Usage: dotfiles_state_merge <filter> [jq options...]
dotfiles_state_merge() {
  local filter=$1
  shift
  dotfiles_state_init || return 1
  local tmp
  tmp=$(mktemp "${DOTFILES_STATE_DIR}/state.XXXXXX") || return 1
  if jq "$@" "$filter" "$DOTFILES_STATE_FILE" >"$tmp"; then
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$DOTFILES_STATE_FILE"
  else
    rm -f "$tmp"
    return 1
  fi
}

dotfiles_state_repo() {
  local root=${1:-} commit remote
  [ -n "$root" ] || root=$(dotfiles_repo_root) || return 1
  commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)
  remote=$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)
  dotfiles_state_merge '.repo={path:$root,commit:$commit,remote:$remote} | .updated_at=$now' \
    --arg root "$root" --arg commit "$commit" --arg remote "$remote" --arg now "$(dotfiles_now)"
}

# Usage: dotfiles_state_file <target> [source] [kind] [sha] [backup] [existed] [restore]
dotfiles_state_file() {
  local target=$1 source=${2:-} kind=${3:-file} sha=${4:-} backup=${5:-} existed=${6:-1} restore=${7:-1}
  dotfiles_state_merge '
    .managed_files = ((.managed_files // []) | map(select(.target != $target)) + [{
      target:$target, source:$source, kind:$kind, sha256:$sha, backup:$backup,
      existed:($existed == "1"), restore:($restore == "1")
    }]) | .updated_at=$now
  ' --arg target "$target" --arg source "$source" --arg kind "$kind" --arg sha "$sha" \
    --arg backup "$backup" --arg existed "$existed" --arg restore "$restore" --arg now "$(dotfiles_now)"
}

dotfiles_state_tool() {
  local name=$1 version=${2:-} source=${3:-}
  dotfiles_state_merge '.tools[$name]={version:$version,source:$source,checked_at:$now} | .updated_at=$now' \
    --arg name "$name" --arg version "$version" --arg source "$source" --arg now "$(dotfiles_now)"
}

dotfiles_state_last_run() {
  local name=$1
  dotfiles_state_merge '.last_run[$name]=$now | .updated_at=$now' \
    --arg name "$name" --arg now "$(dotfiles_now)"
}

# --- marker blocks ---------------------------------------------------------

# Replace a marker block and keep everything outside it. With backup=1, back
# up the file first when the block actually changes.
# Usage: dotfiles_upsert_block <file> <start> <end> <content> [backup]
dotfiles_upsert_block() {
  local file=$1 start=$2 end=$3 content=$4 backup=${5:-0}
  local tmp mode has_start has_end
  [ -e "$file" ] || : >"$file"
  has_start=$(grep -cxF "$start" "$file" 2>/dev/null || true)
  has_end=$(grep -cxF "$end" "$file" 2>/dev/null || true)
  has_start=${has_start:-0}
  has_end=${has_end:-0}
  [ "$has_start" = "$has_end" ] || return 2

  tmp=$(mktemp) || return 1
  awk -v s="$start" -v e="$end" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$file" >"$tmp" || { rm -f "$tmp"; return 1; }
  printf '%s\n%s\n%s\n' "$start" "$content" "$end" >>"$tmp" || { rm -f "$tmp"; return 1; }

  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  if [ "$backup" = 1 ]; then
    dotfiles_backup_file "$file" 1 || return 1
  fi
  mode=$(stat -c '%a' "$file" 2>/dev/null || echo 644)
  chmod "$mode" "$tmp" 2>/dev/null || true
  mv "$tmp" "$file"
}

# --- backups ---------------------------------------------------------------

dotfiles_backup_begin() {
  [ -n "${DOTFILES_BACKUP_SET:-}" ] && return 0
  local stamp
  mkdir -p "$DOTFILES_BACKUP_DIR" || return 1
  chmod 700 "$DOTFILES_BACKUP_DIR" 2>/dev/null || true
  stamp=$(date +%Y%m%d-%H%M%S)
  DOTFILES_BACKUP_SET="$DOTFILES_BACKUP_DIR/$stamp"
  if [ -e "$DOTFILES_BACKUP_SET" ]; then
    DOTFILES_BACKUP_SET="$DOTFILES_BACKUP_DIR/$stamp-$$"
  fi
  mkdir -p "$DOTFILES_BACKUP_SET" || return 1
  chmod 700 "$DOTFILES_BACKUP_SET" 2>/dev/null || true
  DOTFILES_BACKUP_ENTRIES="$DOTFILES_BACKUP_SET/.entries.jsonl"
  : >"$DOTFILES_BACKUP_ENTRIES" || return 1
}

# Usage: dotfiles_backup_record <target> <backup-rel> [kind] [sha] [mode] [existed] [restore] [redacted]
dotfiles_backup_record() {
  local target=$1 backup=$2 kind=${3:-file} sha=${4:-} mode=${5:-} existed=${6:-1} restore=${7:-1} redacted=${8:-0}
  [ -n "${DOTFILES_BACKUP_SET:-}" ] || return 1
  jq -cn --arg target "$target" --arg backup "$backup" --arg kind "$kind" --arg sha "$sha" \
    --arg mode "$mode" --arg existed "$existed" --arg restore "$restore" --arg redacted "$redacted" \
    '{target:$target,backup:$backup,kind:$kind,sha256:$sha,mode:$mode,existed:($existed=="1"),restore:($restore=="1"),redacted:($redacted=="1")}' \
    >>"$DOTFILES_BACKUP_ENTRIES"
}

# Copy an existing path into the current backup set.
# Usage: dotfiles_backup_file <target> [restore] [kind]
dotfiles_backup_file() {
  local target=$1 restore=${2:-1} kind=${3:-} rel dest sha mode
  dotfiles_backup_begin || return 1
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    dotfiles_backup_record "$target" "" "$kind" "" "" 0 "$restore" 0
    return 0
  fi
  if [ -z "$kind" ]; then
    if [ -L "$target" ]; then kind='symlink'
    elif [ -d "$target" ]; then kind='dir'
    else kind='file'
    fi
  fi
  case $target in
    "$HOME"/*) rel=${target#"$HOME"/} ;;
    *) rel="_root$target" ;;
  esac
  dest="$DOTFILES_BACKUP_SET/$rel"
  mkdir -p "$(dirname "$dest")" || return 1
  cp -a -- "$target" "$dest" || return 1
  sha=
  [ "$kind" = file ] && sha=$(dotfiles_sha256 "$target")
  mode=$(stat -c '%a' "$target" 2>/dev/null || true)
  dotfiles_backup_record "$target" "$rel" "$kind" "$sha" "$mode" 1 "$restore" 0
}

# Record a path that did not exist before this run.
dotfiles_backup_missing() {
  local target=$1 restore=${2:-1}
  dotfiles_backup_begin || return 1
  dotfiles_backup_record "$target" "" file "" "" 0 "$restore" 0
}

# Copy an arbitrary source file into the backup set under the target's path.
dotfiles_backup_copy() {
  local target=$1 source=$2 restore=${3:-1} kind=${4:-file}
  local rel dest sha mode
  dotfiles_backup_begin || return 1
  case $target in
    "$HOME"/*) rel=${target#"$HOME"/} ;;
    *) rel="_root$target" ;;
  esac
  dest="$DOTFILES_BACKUP_SET/$rel"
  mkdir -p "$(dirname "$dest")" || return 1
  cp -a -- "$source" "$dest" || return 1
  sha=
  [ "$kind" = file ] && sha=$(dotfiles_sha256 "$dest")
  mode=$(stat -c '%a' "$source" 2>/dev/null || true)
  dotfiles_backup_record "$target" "$rel" "$kind" "$sha" "$mode" 1 "$restore" 0
}

# Snapshot user-authored OpenCode config plus plugin code. JSON values under
# env/apiKey/token/secret/password keys are dropped; credential stores and
# installed skills are never copied. Snapshots are excluded from restore.
dotfiles_backup_opencode() {
  local dir="$HOME/.config/opencode" f d rel
  [ -d "$dir" ] || return 0
  dotfiles_backup_begin || return 1
  for f in opencode.jsonc tui.jsonc cli.json; do
    [ -f "$dir/$f" ] || continue
    jq -e . "$dir/$f" >/dev/null 2>&1 || continue
    rel="opencode/$f"
    mkdir -p "$DOTFILES_BACKUP_SET/opencode" || return 1
    if jq 'walk(if type=="object" then with_entries(select((.key|test("env|api.?key|token|secret|password";"i"))|not)) else . end)' \
      "$dir/$f" >"$DOTFILES_BACKUP_SET/$rel"; then
      dotfiles_backup_record "$dir/$f" "$rel" file "$(dotfiles_sha256 "$DOTFILES_BACKUP_SET/$rel")" 600 1 0 1
    else
      rm -f "$DOTFILES_BACKUP_SET/$rel"
    fi
  done
  for f in AGENTS.md herdr-tui-session.js; do
    [ -f "$dir/$f" ] || continue
    dotfiles_backup_copy "$dir/$f" "$dir/$f" 0 file
  done
  for d in commands plugins herdr-opencode; do
    [ -d "$dir/$d" ] || continue
    dotfiles_backup_copy "$dir/$d" "$dir/$d" 0 dir
  done
}

dotfiles_backup_prune() {
  local keep=${DOTFILES_BACKUP_KEEP:-10}
  case $keep in ''|*[!0-9]*) keep=10 ;; esac
  mapfile -t _dotfiles_sets < <(
    find "$DOTFILES_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null |
      sort -nr | tail -n +$((keep + 1)) | cut -d' ' -f2-
  )
  local d existing
  for d in "${_dotfiles_sets[@]}"; do
    rm -rf -- "$d"
  done
  unset _dotfiles_sets
  existing=$(find "$DOTFILES_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%p\n' 2>/dev/null |
    jq -R -s 'split("\n") | map(select(length > 0))')
  dotfiles_state_merge '.backups = [.backups[] | select(.path as $p | ($existing | index($p)) != null)]' \
    --argjson existing "$existing" || true
}

dotfiles_backup_finish() {
  [ -n "${DOTFILES_BACKUP_SET:-}" ] || return 0
  local set=$DOTFILES_BACKUP_SET entries=$DOTFILES_BACKUP_ENTRIES count=0 created
  if [ -s "$entries" ]; then
    count=$(wc -l <"$entries")
    created=$(dotfiles_now)
    if jq -s --arg created "$created" --arg host "$(hostname 2>/dev/null || echo unknown)" \
      --arg repo "$(dotfiles_repo_root || true)" \
      '{schema:1,created_at:$created,host:$host,repo:$repo,entries:.}' "$entries" \
      >"$set/manifest.json"; then
      chmod 600 "$set/manifest.json" 2>/dev/null || true
      rm -f "$entries"
      dotfiles_state_merge '
        .backups = ((.backups // []) | map(select(.path != $path)) + [{
          path:$path, created_at:$created, entries:($entries|tonumber)
        }]) | .last_backup=$path | .updated_at=$created
      ' --arg path "$set" --arg created "$created" --arg entries "$count" || true
    else
      rm -f "$set/manifest.json"
    fi
  else
    rm -rf -- "$set"
  fi
  if [ "${DOTFILES_BACKUP_NO_PRUNE:-0}" != 1 ]; then
    dotfiles_backup_prune
  fi
  unset DOTFILES_BACKUP_SET DOTFILES_BACKUP_ENTRIES
}
