#!/usr/bin/env bash
# Download 4K wallpapers into wallpapers/<theme>/ (binaries not committed).
# Called automatically from install.sh before theme-switch.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WALL_ROOT="${DOTFILES_DIR}/wallpapers"
FAILS=0

log() { printf '[wallpapers] %s\n' "$*"; }
warn() { printf '[wallpapers] WARN: %s\n' "$*" >&2; }

download() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  if [[ -f "${dest}" ]] && [[ "$(stat -c%s "${dest}" 2>/dev/null || stat -f%z "${dest}" 2>/dev/null || echo 0)" -gt 50000 ]]; then
    log "exists $(basename "${dest}")"
    return 0
  fi
  log "fetch $(basename "${dest}")"
  rm -f "${dest}" "${dest}.partial"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --retry-delay 2 -A "EndeavourOSDotfiles/1.0" -o "${dest}.partial" "${url}" \
      || { warn "curl failed $(basename "${dest}")"; FAILS=$((FAILS + 1)); return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${dest}.partial" "${url}" \
      || { warn "wget failed $(basename "${dest}")"; FAILS=$((FAILS + 1)); return 1; }
  else
    warn "curl/wget missing"
    FAILS=$((FAILS + 1))
    return 1
  fi
  local size
  size="$(stat -c%s "${dest}.partial" 2>/dev/null || stat -f%z "${dest}.partial" 2>/dev/null || echo 0)"
  if [[ "${size}" -lt 50000 ]]; then
    warn "too small (${size} B), skip $(basename "${dest}")"
    rm -f "${dest}.partial"
    FAILS=$((FAILS + 1))
    return 1
  fi
  mv "${dest}.partial" "${dest}"
}

# Credits: wallpapers/SOURCES.md
# First file of each theme becomes wallpaper.jpg (default for theme-switch).

download_theme() {
  local theme="$1"
  shift
  local url file primary="" dest
  while [[ $# -ge 2 ]]; do
    url="$1"
    file="$2"
    shift 2
    dest="${WALL_ROOT}/${theme}/${file}"
    if download "${url}" "${dest}"; then
      if [[ -z "${primary}" ]]; then
        primary="${dest}"
      fi
    else
      warn "failed ${theme}/${file}"
    fi
  done
  if [[ -n "${primary}" ]]; then
    # Stable name for theme-switch / swww
    ln -sfn "$(basename "${primary}")" "${WALL_ROOT}/${theme}/wallpaper.jpg"
    log "default ${theme} → $(basename "${primary}")"
  else
    warn "no wallpaper downloaded for ${theme}"
    FAILS=$((FAILS + 1))
  fi
}

mkdir -p "${WALL_ROOT}"/{cyberpunk,gruvbox-dark,catppuccin-mocha,tokyo-night,dracula,nord,rose-pine,everforest-dark}

# cyberpunk — neon city 4K (Pixnio 3854×2160 + wallhaven)
download_theme cyberpunk \
  "https://pixnio.com/free-images/2026/08/30/2026-08-30-16-03-37.jpg" "pixnio-cyberpunk-3854x2160.jpg" \
  "https://w.wallhaven.cc/full/6d/wallhaven-6d1v5q.jpg" "night-city-neon.jpg" \
  "https://w.wallhaven.cc/full/xe/wallhaven-xe86w3.jpg" "aerial-neon-towers.jpg" \
  "https://w.wallhaven.cc/full/o5/wallhaven-o5r1e9.png" "neon-crowd-city-4k.png"

# gruvbox-dark — warm landscapes
download_theme gruvbox-dark \
  "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "warm-peaks.jpg" \
  "https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "foggy-hills.jpg" \
  "https://images.unsplash.com/photo-1469474968028-56623f02e42e?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "sunlit-valley.jpg"

# catppuccin-mocha — soft mauve / rain neon
download_theme catppuccin-mocha \
  "https://images.unsplash.com/photo-1519681393784-d120267933ba?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "starry-mountains.jpg" \
  "https://images.unsplash.com/photo-1507400492013-162706c8be01?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "soft-dusk-clouds.jpg"

# tokyo-night — cold city night
download_theme tokyo-night \
  "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "tokyo-crossing.jpg" \
  "https://images.unsplash.com/photo-1513407030348-c983a97b98d8?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "tokyo-tower-night.jpg" \
  "https://w.wallhaven.cc/full/96/wallhaven-96pd3x.jpg" "neon-futuristic-night.jpg"

# dracula — purple contrast night
download_theme dracula \
  "https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "purple-milky-way.jpg" \
  "https://w.wallhaven.cc/full/57/wallhaven-57d315.jpg" "cyber-high-angle.jpg"

# nord — arctic / aurora
download_theme nord \
  "https://images.unsplash.com/photo-1483347756197-71ef80e95f73?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "aurora-over-snow.jpg" \
  "https://images.unsplash.com/photo-1531366936337-7c912a45b4d9?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "northern-lights.jpg"

# rose-pine — soft dusk / pink clouds
download_theme rose-pine \
  "https://images.unsplash.com/photo-1495616811223-4d98c6e9c869?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "pastel-dusk.jpg" \
  "https://images.unsplash.com/photo-1507400492013-162706c8be01?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "rose-clouds.jpg"

# everforest-dark — forest canopy
download_theme everforest-dark \
  "https://images.unsplash.com/photo-1441974231531-c6227db76b6e?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "sunlit-forest.jpg" \
  "https://images.unsplash.com/photo-1448376561459-e1c2ad95b255?ixlib=rb-4.0.3&w=3840&q=90&fm=jpg" "deep-woods.jpg"

for t in cyberpunk gruvbox-dark catppuccin-mocha tokyo-night dracula nord rose-pine everforest-dark; do
  touch "${WALL_ROOT}/${t}/.gitkeep"
done

if [[ ! -e "${WALL_ROOT}/cyberpunk/wallpaper.jpg" ]]; then
  warn "cyberpunk default wallpaper missing — check network and re-run: ./scripts/fetch-wallpapers.sh"
  exit 1
fi

log "done — ${FAILS} fail(s); credits in wallpapers/SOURCES.md"
exit 0
