# Shared environment for interactive shells and login sessions.
# The PATH additions are idempotent: .profile and .bashrc both source this.

_dotfiles_path_add() {
  case ":${PATH}:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

_dotfiles_path_add "$HOME/.local/bin"
[ -d "$HOME/.bun/bin" ] && _dotfiles_path_add "$HOME/.bun/bin"
[ -d "$HOME/.opencode/bin" ] && _dotfiles_path_add "$HOME/.opencode/bin"
[ -d "$HOME/.config/composer/vendor/bin" ] && _dotfiles_path_add "$HOME/.config/composer/vendor/bin"
[ -d "$HOME/.local/share/lerd/bin" ] && _dotfiles_path_add "$HOME/.local/share/lerd/bin"

export PAGER="${PAGER:-less}"
export LESS="${LESS:--R}"

unset -f _dotfiles_path_add
