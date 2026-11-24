# Shell aliases and update functions.
# Loaded from ~/.bashrc.d/ by the managed block in ~/.bashrc; see docs/bashrc.md.

# laravel artisan
alias art='[ -f artisan ] && php artisan'

# laravel sail alias
alias sail='sh $([ -f sail ] && echo sail || echo vendor/bin/sail)'

# update-dev-tools: update every developer tool installed on this machine.
# Usage: update-dev-tools [-v|--verbose]
# Missing tools are reported as skipped; see docs/bashrc.md.
update-dev-tools() {
  local verbose=0
  case "${1:-}" in -v|--verbose) verbose=1 ;; esac

  if [ "$(id -u)" -eq 0 ]; then
    printf 'update-dev-tools: run as your user, not root (it updates tools under %s)\n' "$HOME" >&2
    return 1
  fi

  local dim='' grn='' red='' rst=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    dim=$'\033[2m' grn=$'\033[32m' red=$'\033[31m' rst=$'\033[0m'
  fi

  printf '\n%s==> update-dev-tools%s\n' "$dim" "$rst"

  _udt_ver() {
    if [ "$1" = herdr-plugins ]; then
      # herdr has no per-plugin --version; the registry JSON carries them all
      herdr plugin list --json 2>/dev/null |
        grep -o '"version":"[^"]*"' | cut -d'"' -f4 | paste -sd, -
    elif [ "$1" = global-skills ]; then
      # skills have no version; the lock hash moves when one is updated
      md5sum "$HOME/.agents/.skill-lock.json" 2>/dev/null | cut -c1-7
    elif [ "$1" = impeccable ]; then
      # the installed SKILL.md carries the compiled skill version
      local skill="$HOME/.config/opencode/skills/impeccable/SKILL.md"
      [ -f "$skill" ] || skill="$HOME/.agents/skills/impeccable/SKILL.md"
      sed -n 's/^[[:space:]]*version:[[:space:]]*//p' "$skill" 2>/dev/null |
        head -n1 | tr -d "\"'"
    elif [ "$1" = opencode-gui ]; then
      # the desktop app is a .deb, so its version lives in dpkg
      dpkg-query -W -f='${Version}' opencode 2>/dev/null
    elif [ "$1" = gitkraken ]; then
      dpkg-query -W -f='${Version}' gitkraken 2>/dev/null
    else
      "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
    fi
  }

  # a tool is present when the command its update path needs exists
  _udt_present() {
    case $1 in
      node|npm)      command -v nvm >/dev/null 2>&1 ;;
      opencode-gui)  dpkg-query -W opencode >/dev/null 2>&1 ;;
      gitkraken)     dpkg-query -W gitkraken >/dev/null 2>&1 ;;
      herdr-plugins) command -v herdr >/dev/null 2>&1 ;;
      impeccable)
        command -v bunx >/dev/null 2>&1 &&
          { [ -f "$HOME/.config/opencode/skills/impeccable/SKILL.md" ] ||
            [ -f "$HOME/.agents/skills/impeccable/SKILL.md" ]; }
        ;;
      global-skills) command -v bun >/dev/null 2>&1 ;;
      *)             command -v "$1" >/dev/null 2>&1 ;;
    esac
  }

  local logdir
  logdir=$(mktemp -d "${TMPDIR:-/tmp}/update-dev-tools.XXXXXX") || return 1
  local arch
  arch=$(dpkg --print-architecture 2>/dev/null) || arch=amd64
  local tool label cmd before after rc failed=0 skip latest
  for tool in node npm bun lerd opencode opencode-gui herdr-core herdr herdr-app herdr-plugins impeccable global-skills gitkraken; do
    label=$tool
    if [ "$tool" = herdr ]; then label=herdr-cli; fi
    if ! _udt_present "$tool"; then
      if [ "$verbose" = 1 ]; then
        printf '\n%s==> %s%s\n' "$dim" "$label" "$rst"
      fi
      printf '%-32s %s· skipped (not installed)%s\n' "$label" "$dim" "$rst"
      continue
    fi

    before=$(_udt_ver "$tool")
    skip=0
    case $tool in
      node)       cmd=(nvm install --lts) ;;
      npm)        cmd=(nvm install-latest-npm) ;;
      herdr)      cmd=(herdr update) ;;
      herdr-core) cmd=(herdr-core update) ;;
      herdr-app)
        # The app has no update command of its own; its official installer
        # updates it. It always downloads, so only run it when behind.
        latest=$(curl -fsSL https://releases.herdr.dev/app/latest.json 2>/dev/null |
          sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
        [ -n "$latest" ] && [ "$latest" = "$before" ] && skip=1
        cmd=(bash -o pipefail -c 'curl -fsSL https://releases.herdr.dev/app/install.sh | sh')
        ;;
      bun)
        # bun upgrade goes through api.github.com, which 403s when rate
        # limited; the official installer works. It always downloads, so only
        # run it when behind.
        latest=$(curl -fsSL https://registry.npmjs.org/bun/latest 2>/dev/null |
          grep -o '"version":"[^"]*"' | head -n1 | cut -d'"' -f4)
        [ -n "$latest" ] && [ "$latest" = "$before" ] && skip=1
        cmd=(bash -o pipefail -c 'curl -fsSL https://bun.sh/install | bash')
        ;;
      lerd)       cmd=(lerd update) ;;
      opencode)   cmd=(opencode upgrade) ;;
      opencode-gui)
        # The desktop app is a .deb from a versioned URL with no apt repo, so
        # installing it needs root; sudo -n fails fast when there is none
        # rather than prompting inside the batch. It always downloads ~250MB.
        latest=$(curl -fsSL https://opencode.ai/update/api/latest/desktop/opencode/latest-linux.yml 2>/dev/null |
          sed -n 's/^version:[[:space:]]*//p' | head -n1)
        # unknown latest, not installed, or already current: leave it alone
        if [ -z "$latest" ] || [ -z "$before" ] || [ "$latest" = "$before" ]; then skip=1; fi
        cmd=(bash -o pipefail -c "curl -fsSL https://opencode.ai/files/bin/$latest/opencode-desktop-linux-$arch.deb -o /tmp/opencode-desktop.deb && sudo -n apt-get install -y /tmp/opencode-desktop.deb && rm -f /tmp/opencode-desktop.deb")
        ;;
      # last, so plugins update against the herdr CLI installed just above
      herdr-plugins) cmd=(herdr plugin update --yes) ;;
      # Impeccable's CLI updates both the skill and the /impeccable command
      impeccable)
        latest=$(bun info impeccable version 2>/dev/null)
        [ -n "$latest" ] && [ "$latest" = "$before" ] && skip=1
        cmd=(timeout 600 bunx impeccable@latest update -y --global)
        ;;
      # -g keeps it to ~/.agents/skills, -y so it never stops on a prompt
      global-skills) cmd=(bunx skills update -g -y) ;;
      gitkraken)
        # Same shape as opencode-gui: a .deb, no apt repo, so root is needed
        # and sudo -n fails fast rather than prompting. The download URL
        # redirects to a versioned path, so the latest version costs no
        # download: read the Location header and ask for one byte.
        latest=$(curl -s -o /dev/null -D - --max-time 20 -r 0-0 \
            https://release.gitkraken.com/linux/gitkraken-amd64.deb 2>/dev/null |
          sed -n 's#.*/linux/x64/\([^/]*\)/.*#\1#p' | head -n1)
        # unknown latest, not installed, or not newer: leave it alone
        if [ -z "$latest" ] || [ -z "$before" ] ||
           ! dpkg --compare-versions "$latest" gt "$before"; then skip=1; fi
        cmd=(bash -o pipefail -c 'curl -fsSL https://release.gitkraken.com/linux/gitkraken-amd64.deb -o /tmp/gitkraken-amd64.deb && sudo -n dpkg -i /tmp/gitkraken-amd64.deb && rm -f /tmp/gitkraken-amd64.deb')
        ;;
    esac

    if [ "$verbose" = 1 ]; then
      printf '\n%s==> %s%s\n' "$dim" "$label" "$rst"
    fi
    if [ "$skip" = 1 ]; then
      rc=0
    elif [ "$verbose" = 1 ]; then
      "${cmd[@]}" </dev/null 2>&1 | tee "$logdir/$tool.log"
      rc=${PIPESTATUS[0]}
    else
      printf '%s%-32s ...%s' "$dim" "$label" "$rst"
      # stdin closed so a tool that asks a question fails instead of waiting
      # forever on a prompt hidden in the log (lerd update asks on a tty)
      "${cmd[@]}" </dev/null >"$logdir/$tool.log" 2>&1
      rc=$?
      printf '\r\033[K'
    fi
    after=$(_udt_ver "$tool")

    if [ "$rc" -ne 0 ]; then
      printf '%-32s %sx failed (exit %s)%s\n' "$label" "$red" "$rc" "$rst"
      failed=1
    elif [ -n "$before" ] && [ "$after" != "$before" ]; then
      printf '%-32s %s↑ updated %s => %s%s\n' "$label" "$grn" "$before" "$after" "$rst"
    elif [ -n "$after" ]; then
      printf '%-32s %s· already latest (%s)%s\n' "$label" "$dim" "$after" "$rst"
    else
      printf '%-32s %s✓ done%s\n' "$label" "$grn" "$rst"
    fi
  done

  if [ "$failed" = 1 ]; then
    printf '\n%slogs: %s%s\n' "$dim" "$logdir" "$rst"
    return 1
  fi
  rm -rf "$logdir"
}

# internal: print the apt change rows from two dpkg snapshots and the
# upgradable list captured before the upgrade.
# Usage: _update_apt_rows <before> <after> <upgradable>
_update_apt_rows() {
  awk '
    FNR==NR {
      old[$1] = $2
      next
    }
    FILENAME==ARGV[2] {
      new[$1] = $2
      next
    }
    {
      if (($1 in old) && old[$1] == new[$1]) kept[$1] = new[$1]
      next
    }
    END {
      for (p in new) {
        if (!(p in old)) print "2\t" p "\t" new[p] "\t"
        else if (old[p] != new[p]) print "1\t" p "\t" old[p] "\t" new[p]
      }
      for (p in old) {
        if (!(p in new)) print "3\t" p "\t" old[p] "\t"
      }
      for (p in kept) print "4\t" p "\t" kept[p] "\t"
    }
  ' "$1" "$2" "$3" | sort -t $'\t' -k1,1n -k2,2 |
    while IFS=$'\t' read -r group pkg v1 v2; do
      case $group in
        1) printf '%-32s %s↑ updated %s => %s%s\n' "$pkg" "$grn" "$v1" "$v2" "$rst" ;;
        2) printf '%-32s %s+ added (%s)%s\n' "$pkg" "$grn" "$v1" "$rst" ;;
        3) printf '%-32s %s- removed (%s)%s\n' "$pkg" "$red" "$v1" "$rst" ;;
        4) printf '%-32s %s· kept back (%s)%s\n' "$pkg" "$dim" "$v1" "$rst" ;;
      esac
    done
}

# update-apt-all: refresh apt, upgrade the system, and summarise what changed.
# Usage: update-apt-all [-v|--verbose]
# apt output is hidden unless -v; the summary comes from dpkg snapshots.
update-apt-all() {
  local verbose=0
  case "${1:-}" in -v|--verbose) verbose=1 ;; esac

  if [ "$(id -u)" -eq 0 ]; then
    printf 'update-apt-all: run as your user, not root (apt asks for sudo when needed)\n' >&2
    return 1
  fi

  local dim='' grn='' red='' rst=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    dim=$'\033[2m' grn=$'\033[32m' red=$'\033[31m' rst=$'\033[0m'
  fi

  printf '\n%s==> update-apt-all%s\n' "$dim" "$rst"

  # authenticate up front, so the prompt never lands in the middle of a row
  if ! sudo -v; then
    printf 'update-apt-all: sudo authentication failed\n' >&2
    return 1
  fi

  local logdir
  logdir=$(mktemp -d "${TMPDIR:-/tmp}/update-apt-all.XXXXXX") || return 1

  local before after upgradable
  before=$logdir/before
  after=$logdir/after
  upgradable=$logdir/upgradable
  dpkg-query -W -f='${binary:Package} ${Version}\n' | sort > "$before"
  : > "$upgradable"

  local rc=0 failed=0
  # conffile prompts would be hidden with the output, so resolve them: keep
  # the existing config unless the package declares a safe default
  local dpkg_opts=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

  if [ "$verbose" = 1 ]; then
    sudo apt update 2>&1 | tee "$logdir/apt-update.log"
    rc=${PIPESTATUS[0]}
  else
    printf '%s%-32s ...%s' "$dim" "apt update" "$rst"
    sudo apt update </dev/null >"$logdir/apt-update.log" 2>&1
    rc=$?
    printf '\r\033[K'
  fi

  if [ "$rc" -ne 0 ]; then
    printf '%-32s %sx failed (exit %s)%s\n' "apt update" "$red" "$rc" "$rst"
    tail -n 10 "$logdir/apt-update.log" | sed 's/^/  /'
    printf '%-32s %s· skipped (update failed)%s\n' "apt upgrade" "$dim" "$rst"
    failed=1
  else
    printf '%-32s %s✓ done%s\n' "apt update" "$grn" "$rst"

    # captured before the upgrade, so packages apt keeps back (held, phased)
    # can be told apart from the ones it actually changed
    LC_ALL=C apt list --upgradable 2>/dev/null |
      sed -n 's|^\([^/]*\)/.*|\1|p' | sort -u > "$upgradable"

    if [ "$verbose" = 1 ]; then
      sudo apt dist-upgrade -y --autoremove --purge "${dpkg_opts[@]}" 2>&1 | tee "$logdir/apt-upgrade.log"
      rc=${PIPESTATUS[0]}
    else
      printf '%s%-32s ...%s' "$dim" "apt upgrade" "$rst"
      sudo apt dist-upgrade -y --autoremove --purge "${dpkg_opts[@]}" </dev/null >"$logdir/apt-upgrade.log" 2>&1
      rc=$?
      printf '\r\033[K'
    fi

    if [ "$rc" -ne 0 ]; then
      printf '%-32s %sx failed (exit %s)%s\n' "apt upgrade" "$red" "$rc" "$rst"
      tail -n 10 "$logdir/apt-upgrade.log" | sed 's/^/  /'
      failed=1
    else
      printf '%-32s %s✓ done%s\n' "apt upgrade" "$grn" "$rst"
    fi

    dpkg-query -W -f='${binary:Package} ${Version}\n' | sort > "$after"
    local rows
    rows=$(_update_apt_rows "$before" "$after" "$upgradable")
    if [ -n "$rows" ]; then
      printf '%s\n' "$rows"
    else
      printf '%-32s %s· nothing changed%s\n' "apt" "$dim" "$rst"
    fi
  fi

  if [ "$failed" = 1 ]; then
    printf '\n%slogs: %s%s\n' "$dim" "$logdir" "$rst"
    return 1
  fi
  rm -rf "$logdir"
}

# internal: versioned path of the current WinBox Linux zip on MikroTik's page
_uut_winbox_zip() {
  curl -fsSL --max-time 20 https://mikrotik.com/download/winbox 2>/dev/null |
    grep -oE 'routeros/winbox/[0-9.]+/WinBox_Linux\.zip' | head -n1
}

# internal: (re)write WinBox's desktop entry, in the menu and in its folder.
# Usage: _uut_winbox_desktop <install dir>
_uut_winbox_desktop() {
  local dir=$1 entry="$HOME/.local/share/applications/winbox.desktop"
  mkdir -p "${entry%/*}" || return 1
  {
    printf '[Desktop Entry]\n'
    printf 'Name=WinBox\n'
    printf 'Comment=MikroTik WinBox Configuration Tool\n'
    printf 'Exec=%s/WinBox\n' "$dir"
    printf 'Icon=%s/assets/img/winbox.png\n' "$dir"
    printf 'Terminal=false\n'
    printf 'Type=Application\n'
    printf 'Categories=Network;Admin;\n'
    printf 'StartupNotify=true\n'
  } > "$entry" || return 1
  cp -f "$entry" "$dir/winbox.desktop" || return 1
}

# internal: replace WinBox's binary and assets, keeping everything else.
# Usage: _uut_winbox_install <unpacked dir> <install dir> <version> <marker>
_uut_winbox_install() {
  local src=$1 dir=$2 version=$3 marker=$4
  install -m 755 "$src/WinBox" "$dir/WinBox.new" || return 1
  mv -f "$dir/WinBox.new" "$dir/WinBox" || return 1
  rm -rf "$dir/assets" || return 1
  cp -a "$src/assets" "$dir/assets" || return 1
  _uut_winbox_desktop "$dir" || return 1
  printf '%s\n' "$version" > "$marker" || return 1
}

# internal: install WinBox when it is missing; update-user-tools keeps an
# existing copy current. Called by install.sh after the apt packages exist.
_uut_winbox_install_latest() {
  local dir="$HOME/Applications/WinBox"
  local marker="$HOME/Applications/WinBox.version"
  local zip version tmp rc

  if [ -x "$dir/WinBox" ]; then
    version=$(cat "$marker" 2>/dev/null)
    printf 'winbox already installed%s\n' "${version:+ ($version)}"
    return 0
  fi

  zip=$(_uut_winbox_zip)
  [ -n "$zip" ] || return 1
  version=${zip#routeros/winbox/}
  version=${version%%/*}

  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL --max-time 600 "https://download.mikrotik.com/$zip" -o "$tmp/winbox.zip" ||
     ! unzip -oq "$tmp/winbox.zip" -d "$tmp/winbox"; then
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$dir" || { rm -rf "$tmp"; return 1; }
  if _uut_winbox_install "$tmp/winbox" "$dir" "$version" "$marker"; then
    printf 'winbox installed (%s)\n' "$version"
    rc=0
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# internal: current PIA release for this architecture, as "<version> <url>".
# PIA has no apt repo: the official installer is a makeself .run, and the
# release body carries its versioned download URL.
_uut_pia_release() {
  local arch json tag url build
  arch=$(dpkg --print-architecture 2>/dev/null) || arch=amd64
  case $arch in amd64|arm64) ;; *) return 1 ;; esac

  json=$(curl -fsSL --max-time 20 https://api.github.com/repos/pia-foss/desktop/releases/latest 2>/dev/null) || return 1
  tag=$(printf '%s' "$json" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  if [ "$arch" = arm64 ]; then
    url=$(printf '%s' "$json" | grep -oE 'https://[^"\\]*pia-linux-arm64-[0-9][^"\\]*\.run' | head -n1)
  else
    url=$(printf '%s' "$json" | grep -oE 'https://[^"\\]*pia-linux-[0-9][^"\\]*\.run' | head -n1)
  fi
  [ -n "$tag" ] && [ -n "$url" ] || return 1

  # piactl reports tag+build, e.g. 3.8.0+08539, from pia-linux-3.8-08539.run
  build=${url##*-}
  build=${build%.run}
  printf '%s+%s %s\n' "${tag#v}" "$build" "$url"
}

# internal: installed PIA version, e.g. 3.7.2+08420
_uut_pia_version() {
  local ctl=/opt/piavpn/bin/piactl
  [ -x "$ctl" ] || ctl=$(command -v piactl 2>/dev/null) || return 1
  "$ctl" --version 2>/dev/null
}

# internal: download and run the PIA installer; it upgrades in place.
# Usage: _uut_pia_install <url>
_uut_pia_install() {
  local url=$1 tmp rc
  tmp=$(mktemp -d) || return 1
  if ! curl -fsSL --max-time 600 "$url" -o "$tmp/pia.run"; then
    rm -rf "$tmp"
    return 1
  fi
  chmod +x "$tmp/pia.run" || { rm -rf "$tmp"; return 1; }
  # --nox11 stops makeself from opening an xterm when stdout is a pipe;
  # --systemd is deterministic on Ubuntu. The installer invokes sudo itself.
  DEBIAN_FRONTEND=noninteractive "$tmp/pia.run" --nox11 -- --systemd
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# internal: install PIA when it is missing; update-user-tools keeps it current.
_uut_pia_install_latest() {
  local release version url current
  if [ -x /opt/piavpn/bin/pia-client ]; then
    current=$(_uut_pia_version)
    printf 'pia already installed%s\n' "${current:+ ($current)}"
    return 0
  fi

  release=$(_uut_pia_release) || return 1
  read -r version url <<<"$release"
  sudo -v || return 1
  _uut_pia_install "$url" || return 1
  printf 'pia installed (%s)\n' "$version"
}

# update-user-tools: update the user-facing apps that live outside apt.
# Usage: update-user-tools [-v|--verbose]
update-user-tools() {
  local verbose=0
  case "${1:-}" in -v|--verbose) verbose=1 ;; esac

  if [ "$(id -u)" -eq 0 ]; then
    printf 'update-user-tools: run as your user, not root (it updates files under %s)\n' "$HOME" >&2
    return 1
  fi

  local dim='' grn='' red='' rst=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    dim=$'\033[2m' grn=$'\033[32m' red=$'\033[31m' rst=$'\033[0m'
  fi

  printf '\n%s==> update-user-tools%s\n' "$dim" "$rst"

  local logdir
  logdir=$(mktemp -d "${TMPDIR:-/tmp}/update-user-tools.XXXXXX") || return 1

  local failed=0
  _uut_run() {
    local label=$1
    shift
    local rc
    if [ "$verbose" = 1 ]; then
      "$@" 2>&1 | tee "$logdir/$label.log"
      rc=${PIPESTATUS[0]}
    else
      printf '%s%-32s ...%s' "$dim" "$label" "$rst"
      "$@" </dev/null >"$logdir/$label.log" 2>&1
      rc=$?
      printf '\r\033[K'
    fi
    return "$rc"
  }

  # --- WinBox: a zip from MikroTik, no package manager, no checksum ---
  local wb_dir="$HOME/Applications/WinBox"
  local wb_marker="$HOME/Applications/WinBox.version"
  if [ ! -x "$wb_dir/WinBox" ]; then
    printf '%-32s %s· skipped (not installed)%s\n' winbox "$dim" "$rst"
  else
    local zip latest current
    zip=$(_uut_winbox_zip)
    latest=$zip
    latest=${latest#routeros/winbox/}
    latest=${latest%%/*}
    current=$(cat "$wb_marker" 2>/dev/null)
    if [ -z "$zip" ]; then
      printf '%-32s %sx failed (no release found)%s\n' winbox "$red" "$rst"
      failed=1
    elif [ "$latest" = "$current" ]; then
      if _uut_winbox_desktop "$wb_dir"; then
        printf '%-32s %s· already latest (%s)%s\n' winbox "$dim" "$latest" "$rst"
      else
        printf '%-32s %sx failed (desktop entry)%s\n' winbox "$red" "$rst"
        failed=1
      fi
    elif _uut_run winbox curl -fsSL --max-time 600 "https://download.mikrotik.com/$zip" -o "$logdir/winbox.zip" &&
         _uut_run winbox unzip -oq "$logdir/winbox.zip" -d "$logdir/winbox"; then
      local new_hash old_hash
      new_hash=$(sha256sum "$logdir/winbox/WinBox" | cut -d' ' -f1)
      old_hash=$(sha256sum "$wb_dir/WinBox" | cut -d' ' -f1)
      if [ "$new_hash" = "$old_hash" ]; then
        printf '%s\n' "$latest" > "$wb_marker"
        if _uut_winbox_desktop "$wb_dir"; then
          printf '%-32s %s· already latest (%s)%s\n' winbox "$dim" "$latest" "$rst"
        else
          printf '%-32s %sx failed (desktop entry)%s\n' winbox "$red" "$rst"
          failed=1
        fi
      elif _uut_run winbox _uut_winbox_install "$logdir/winbox" "$wb_dir" "$latest" "$wb_marker"; then
        if [ -n "$current" ]; then
          printf '%-32s %s↑ updated %s => %s%s\n' winbox "$grn" "$current" "$latest" "$rst"
        else
          printf '%-32s %s↑ updated => %s%s\n' winbox "$grn" "$latest" "$rst"
        fi
      else
        printf '%-32s %sx failed (exit %s)%s\n' winbox "$red" "$?" "$rst"
        failed=1
      fi
    else
      printf '%-32s %sx failed (download)%s\n' winbox "$red" "$rst"
      failed=1
    fi
  fi

  # --- PIA VPN: official .run installer, no apt repo, needs root ---
  local pia_ctl=/opt/piavpn/bin/piactl
  if [ ! -x "$pia_ctl" ]; then
    printf '%-32s %s· skipped (not installed)%s\n' pia "$dim" "$rst"
  else
    local pia_current pia_release pia_latest pia_url pia_after
    pia_current=$(_uut_pia_version)
    if ! pia_release=$(_uut_pia_release); then
      printf '%-32s %sx failed (no release found)%s\n' pia "$red" "$rst"
      failed=1
    else
      read -r pia_latest pia_url <<<"$pia_release"
      if [ -z "$pia_current" ] || [ -z "$pia_latest" ]; then
        printf '%-32s %sx failed (version)%s\n' pia "$red" "$rst"
        failed=1
      elif ! dpkg --compare-versions "$pia_latest" gt "$pia_current"; then
        printf '%-32s %s· already latest (%s)%s\n' pia "$dim" "$pia_current" "$rst"
      elif ! sudo -v; then
        printf '%-32s %sx failed (sudo authentication)%s\n' pia "$red" "$rst"
        failed=1
      elif _uut_run pia _uut_pia_install "$pia_url"; then
        pia_after=$(_uut_pia_version)
        printf '%-32s %s↑ updated %s => %s%s\n' pia "$grn" "$pia_current" "$pia_after" "$rst"
      else
        printf '%-32s %sx failed (exit %s)%s\n' pia "$red" "$?" "$rst"
        failed=1
      fi
    fi
  fi

  if [ "$failed" = 1 ]; then
    printf '\n%slogs: %s%s\n' "$dim" "$logdir" "$rst"
    return 1
  fi
  rm -rf "$logdir"
}

# update-dotfiles: fast-forward the repository that owns ~/.bashrc.d.
# Usage: update-dotfiles [-v|--verbose]
update-dotfiles() {
  local verbose=0
  case "${1:-}" in -v|--verbose) verbose=1 ;; esac

  if [ "$(id -u)" -eq 0 ]; then
    printf 'update-dotfiles: run as your user, not root\n' >&2
    return 1
  fi

  local dim='' grn='' red='' rst=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    dim=$'\033[2m' grn=$'\033[32m' red=$'\033[31m' rst=$'\033[0m'
  fi

  printf '\n%s==> update-dotfiles%s\n' "$dim" "$rst"

  local link repo before after log rc
  link=$(readlink -f "$HOME/.bashrc.d" 2>/dev/null) || link=
  repo=
  [ -n "$link" ] && repo=$(dirname "$link")
  if [ -z "$repo" ] || ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%-32s %sx failed (dotfiles repo not found)%s\n' dotfiles "$red" "$rst"
    return 1
  fi
  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    printf '%-32s %sx failed (uncommitted changes)%s\n' dotfiles "$red" "$rst"
    return 1
  fi

  before=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null) || before=
  if [ -z "$before" ]; then
    printf '%-32s %sx failed (not a git checkout)%s\n' dotfiles "$red" "$rst"
    return 1
  fi

  log=$(mktemp) || return 1
  if [ "$verbose" = 1 ]; then
    git -C "$repo" pull --ff-only 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
  else
    git -C "$repo" pull --ff-only >"$log" 2>&1
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%-32s %sx failed (git pull)%s\n' dotfiles "$red" "$rst"
    sed 's/^/  /' "$log"
    rm -f "$log"
    return 1
  fi
  rm -f "$log"

  after=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null) || after=$before
  if [ "$after" = "$before" ]; then
    printf '%-32s %s· already latest (%s)%s\n' dotfiles "$dim" "$after" "$rst"
  else
    printf '%-32s %s↑ updated %s => %s%s\n' dotfiles "$grn" "$before" "$after" "$rst"
    printf '%sopen a new shell to load the updated fragments%s\n' "$dim" "$rst"
  fi
}

# update-all: dotfiles first, then the apt upgrade, developer tools and user tools.
# Usage: update-all [-v|--verbose]
# Every phase runs even if the previous one fails; exit status is non-zero if any did.
update-all() {
  local verbose=0
  case "${1:-}" in -v|--verbose) verbose=1 ;; esac

  if [ "$(id -u)" -eq 0 ]; then
    printf 'update-all: run as your user, not root (it updates your home and apt)\n' >&2
    return 1
  fi

  local rc=0
  if [ "$verbose" = 1 ]; then
    update-dotfiles -v || rc=1
    update-apt-all -v || rc=1
    update-dev-tools -v || rc=1
    update-user-tools -v || rc=1
  else
    update-dotfiles || rc=1
    update-apt-all || rc=1
    update-dev-tools || rc=1
    update-user-tools || rc=1
  fi
  return "$rc"
}
