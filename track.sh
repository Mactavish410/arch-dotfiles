#!/usr/bin/env bash
# Move a ~/.config path (or file) into ~/dotfiles/config and symlink back; refresh pkglists.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <path>

Track a config file or directory under ~/.config into the EndeavourOS repo:
  mv → ${DOTFILES_DIR}/config/<name>
  ln -snf back to the original location
  refresh pkglist.txt / pkglist_aur.txt
  git add the new path + pkglists
EOF
  exit 1
}

[[ $# -ge 1 ]] || usage
[[ "$1" == "-h" || "$1" == "--help" ]] && usage

TARGET="$1"
[[ -e "${TARGET}" ]] || { echo "path not found: ${TARGET}" >&2; exit 1; }

ABS="$(realpath "${TARGET}")"
HOME_ABS="$(realpath "${HOME}")"
CONFIG_ABS="$(realpath "${HOME}/.config")"

NAME=""
if [[ "${ABS}" == "${CONFIG_ABS}"/* ]]; then
  NAME="${ABS#"${CONFIG_ABS}/"}"
elif [[ "${ABS}" == "${HOME_ABS}/."* ]]; then
  NAME="$(basename "${ABS}")"
else
  NAME="$(basename "${ABS}")"
fi

# Flatten nested paths: use top-level name under config/
TOP="${NAME%%/*}"
DEST_DIR="${DOTFILES_DIR}/config"
DEST="${DEST_DIR}/${NAME}"

mkdir -p "$(dirname "${DEST}")"

if [[ -e "${DEST}" || -L "${DEST}" ]]; then
  echo "already tracked: ${DEST}" >&2
  exit 1
fi

echo "[track] moving ${ABS} → ${DEST}"
mv "${ABS}" "${DEST}"
ln -snf "${DEST}" "${ABS}"
echo "[track] linked ${ABS} → ${DEST}"

if command -v pacman >/dev/null 2>&1; then
  pacman -Qqen > "${DOTFILES_DIR}/pkglist.txt"
  pacman -Qqem > "${DOTFILES_DIR}/pkglist_aur.txt"
  echo "[track] refreshed pkglist.txt / pkglist_aur.txt"
fi

if command -v git >/dev/null 2>&1 && git -C "${DOTFILES_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "${DOTFILES_DIR}" add "${DEST}" "${DOTFILES_DIR}/pkglist.txt" "${DOTFILES_DIR}/pkglist_aur.txt"
  echo "[track] staged in git — commit when ready"
fi
