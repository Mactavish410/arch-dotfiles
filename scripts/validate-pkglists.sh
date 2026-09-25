#!/usr/bin/env bash
# Validate pkglist.txt / pkglist_aur.txt against Arch official repos + AUR.
#
# Modes:
#   pacman/yay present (EndeavourOS) → strict, exit 1 on bad names
#   curl API only (Windows/CI) → strict on confirmed miss; network blips = WARN
#
# Exit 1 if confirmed bad package names.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OFFICIAL_LIST="${ROOT}/pkglist.txt"
AUR_LIST="${ROOT}/pkglist_aur.txt"
FAIL=0
WARN=0

log()  { printf '[pkg-validate] %s\n' "$*"; }
warn() { printf '[pkg-validate] WARN: %s\n' "$*" >&2; WARN=$((WARN + 1)); }
fail() { printf '[pkg-validate] FAIL: %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

read_pkgs() {
  grep -E '^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$' "$1" 2>/dev/null || true
}

have_pacman=0
have_yay=0
have_curl=0
command -v pacman >/dev/null 2>&1 && have_pacman=1
command -v yay >/dev/null 2>&1 && have_yay=1
command -v curl >/dev/null 2>&1 && have_curl=1

# 0 = found, 1 = confirmed missing, 2 = could not verify (network)
official_check() {
  local pkg="$1" attempt json code tmp
  if [[ "${have_pacman}" -eq 1 ]]; then
    pacman -Si "${pkg}" >/dev/null 2>&1 && return 0
    pacman -Sg "${pkg}" >/dev/null 2>&1 && return 0
    return 1
  fi
  if [[ "${have_curl}" -ne 1 ]]; then
    return 2
  fi
  tmp="$(mktemp)"
  for attempt in 1 2 3; do
    code="$(curl -sS -L --connect-timeout 10 --max-time 30 \
      -o "${tmp}" -w '%{http_code}' \
      "https://archlinux.org/packages/search/json/?name=${pkg}" 2>/dev/null || echo 000)"
    json="$(cat "${tmp}" 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
      if printf '%s' "${json}" | grep -qE "\"pkgname\"[[:space:]]*:[[:space:]]*\"${pkg}\""; then
        rm -f "${tmp}"
        return 0
      fi
      # 200 but no exact name → confirmed missing (API returns [] or other hits)
      if printf '%s' "${json}" | grep -qE '"valid"[[:space:]]*:[[:space:]]*true'; then
        rm -f "${tmp}"
        return 1
      fi
    fi
    sleep $((attempt * 2))
  done
  rm -f "${tmp}"
  return 2
}

# 0 = found, 1 = confirmed missing, 2 = could not verify
aur_check() {
  local pkg="$1" attempt json code tmp
  if [[ "${have_yay}" -eq 1 ]]; then
    yay -Si "${pkg}" >/dev/null 2>&1 && return 0
    return 1
  fi
  if [[ "${have_curl}" -ne 1 ]]; then
    return 2
  fi
  tmp="$(mktemp)"
  for attempt in 1 2 3; do
    code="$(curl -sS -L --connect-timeout 10 --max-time 30 \
      -o "${tmp}" -w '%{http_code}' \
      "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=${pkg}" 2>/dev/null || echo 000)"
    json="$(cat "${tmp}" 2>/dev/null || true)"
    if [[ "${code}" == "200" ]]; then
      if printf '%s' "${json}" | grep -qE '"resultcount"[[:space:]]*:[[:space:]]*[1-9]'; then
        rm -f "${tmp}"
        return 0
      fi
      if printf '%s' "${json}" | grep -qE '"resultcount"[[:space:]]*:[[:space:]]*0'; then
        rm -f "${tmp}"
        return 1
      fi
    fi
    sleep $((attempt * 2))
  done
  rm -f "${tmp}"
  return 2
}

assert_not_in_official() {
  local pkg="$1" reason="$2"
  if grep -qxF "${pkg}" "${OFFICIAL_LIST}" 2>/dev/null; then
    fail "${pkg} is in pkglist.txt but ${reason}"
  fi
}

log "ROOT=${ROOT} pacman=${have_pacman} yay=${have_yay} curl=${have_curl}"

assert_not_in_official "wlogout" "AUR-only — use pkglist_aur.txt"
assert_not_in_official "swww" "renamed to awww (extra)"
assert_not_in_official "rofi-wayland" "use rofi (extra)"
assert_not_in_official "zapret" "AUR name is zapret-git"
assert_not_in_official "nvidia-dkms" "conflicts with nvidia-open* on EOS"
assert_not_in_official "cuda" "heavy — use pkglist_ai.txt + INSTALL_HEAVY_AI=1"
assert_not_in_official "cudnn" "heavy — use pkglist_ai.txt + INSTALL_HEAVY_AI=1"
assert_not_in_official "ollama-cuda" "heavy — use pkglist_ai.txt + INSTALL_HEAVY_AI=1"
assert_not_in_official "cursor-bin" "AUR-only"
assert_not_in_official "sunshine" "AUR-only"
assert_not_in_official "nekobox" "AUR-only"

log "checking official packages…"
while IFS= read -r pkg; do
  [[ -n "${pkg}" ]] || continue
  rc=0
  official_check "${pkg}" || rc=$?
  case "${rc}" in
    0) log "OK official: ${pkg}" ;;
    1) fail "not in official repos: ${pkg}" ;;
    2) warn "could not verify official: ${pkg} (network) — re-run on EOS with pacman" ;;
  esac
done < <(read_pkgs "${OFFICIAL_LIST}")

log "checking AUR packages…"
for list in "${AUR_LIST}" "${ROOT}/pkglist_aur_extra.txt"; do
  [[ -f "${list}" ]] || continue
  log "— $(basename "${list}")"
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    rc=0
    aur_check "${pkg}" || rc=$?
    case "${rc}" in
      0) log "OK AUR: ${pkg}" ;;
      1) fail "not found in AUR: ${pkg}" ;;
      2) warn "could not verify AUR: ${pkg} (network)" ;;
    esac
  done < <(read_pkgs "${list}")
done

if [[ "${have_pacman}" -eq 1 ]]; then
  if pacman -Qq nvidia-open-dkms nvidia-open 2>/dev/null | grep -q .; then
    log "NVIDIA open driver present — install will skip nvidia-dkms"
  fi
fi

echo
if [[ "${FAIL}" -gt 0 ]]; then
  log "FAILED=${FAIL} WARN=${WARN}"
  exit 1
fi
log "all package names OK (WARN=${WARN})"
exit 0
