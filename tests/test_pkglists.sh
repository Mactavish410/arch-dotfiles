#!/usr/bin/env bash
# Validate pkglist names via Arch/AUR APIs (or pacman if present).
# Skip (77) when offline / no curl.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v curl >/dev/null 2>&1 && ! command -v pacman >/dev/null 2>&1; then
  echo "SKIP: no curl/pacman to validate packages"
  exit 77
fi

# Quick connectivity probe (API mode)
if ! command -v pacman >/dev/null 2>&1; then
  if ! curl -fsSIL --max-time 8 https://archlinux.org >/dev/null 2>&1; then
    echo "SKIP: no network to archlinux.org"
    exit 77
  fi
fi

bash "${ROOT}/scripts/validate-pkglists.sh"
