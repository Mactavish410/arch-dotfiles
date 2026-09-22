#!/usr/bin/env bash
# Create XDG home layout + DATA_ROOT media links.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${DOTFILES_DIR}/scripts/lib.sh"
load_dotfiles_env "${DOTFILES_DIR}/.env"

DATA_ROOT="${DATA_ROOT:-/mnt/data}"
LINK_VIDEOS_TO_DATA="${LINK_VIDEOS_TO_DATA:-0}"

log() { printf '[home-dirs] %s\n' "$*"; }

mkdir -p \
  "${HOME}/Documents" \
  "${HOME}/Downloads" \
  "${HOME}/Pictures/Screenshots" \
  "${HOME}/Music" \
  "${HOME}/Videos" \
  "${HOME}/Projects/work" \
  "${HOME}/Projects/personal"

if [[ -d "${DATA_ROOT}" ]]; then
  mkdir -p \
    "${DATA_ROOT}/media/movies" \
    "${DATA_ROOT}/media/series" \
    "${DATA_ROOT}/media/torrents" \
    "${DATA_ROOT}/ai/comfyui" \
    "${DATA_ROOT}/ai/datasets" \
    "${DATA_ROOT}/ai/open-webui" \
    "${DATA_ROOT}/backups"
fi

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  xdg-user-dirs-update || true
fi

if [[ "${LINK_VIDEOS_TO_DATA}" == "1" && -d "${DATA_ROOT}/media/movies" ]]; then
  if [[ -L "${HOME}/Videos" ]]; then
    ln -snf "${DATA_ROOT}/media/movies" "${HOME}/Videos"
  elif [[ -d "${HOME}/Videos" ]] && [[ -z "$(ls -A "${HOME}/Videos" 2>/dev/null || true)" ]]; then
    rmdir "${HOME}/Videos"
    ln -snf "${DATA_ROOT}/media/movies" "${HOME}/Videos"
  else
    log "skip LINK_VIDEOS_TO_DATA — ~/Videos not empty"
  fi
fi

# Optional convenience link to the repo
if [[ ! -e "${HOME}/Dotfiles" && ! -L "${HOME}/Dotfiles" ]]; then
  ln -snf "${DOTFILES_DIR}" "${HOME}/Dotfiles"
  log "linked ~/Dotfiles → ${DOTFILES_DIR}"
fi

log "home directories ready (Documents, Projects, Pictures/Screenshots, …)"
