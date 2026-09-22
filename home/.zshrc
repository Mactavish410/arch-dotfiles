# EndeavourOS Hyprland — home/.zshrc
export DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
[[ -f "${DOTFILES_DIR}/.env" ]] && set -a && source "${DOTFILES_DIR}/.env" && set +a

export DATA_ROOT="${DATA_ROOT:-/mnt/data}"
export DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${DATA_ROOT}/docker}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-${DATA_ROOT}/ollama}"
export OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
export PATH="${HOME}/.local/bin:${DOTFILES_DIR}/bin:${PATH}"

# Qt / GTK theming helpers
export QT_QPA_PLATFORMTHEME=qt6ct
export GTK_THEME="${GTK_THEME:-Adwaita-dark}"

alias cdproj='cd "${HOME}/Projects"'
alias cddata='cd "${DATA_ROOT}"'
alias cddot='cd "${DOTFILES_DIR}"'
# `theme` and `vpn` come from ~/.local/bin (see bin/)

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# History
HISTFILE="${HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Completion
autoload -Uz compinit && compinit

# Prefer neovim/cursor when set later
export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-${EDITOR}}"
