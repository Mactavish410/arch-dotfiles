#!/usr/bin/env bash
# Shared helpers for EndeavourOS shell scripts.
# shellcheck shell=bash

load_dotfiles_env() {
  local env_file="${1:-}"
  if [[ -z "${env_file}" ]]; then
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    env_file="${here}/.env"
  fi
  [[ -f "${env_file}" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
}

dotfiles_root() {
  if [[ -n "${DOTFILES_DIR:-}" ]]; then
    printf '%s\n' "${DOTFILES_DIR}"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
