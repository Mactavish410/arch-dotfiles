#!/usr/bin/env bash
# TUI helpers for Mactavish410 / arch-dotfiles installer.
# shellcheck shell=bash

# Cyberpunk-ish palette (no purple glow spam)
UI_RESET=$'\033[0m'
UI_BOLD=$'\033[1m'
UI_DIM=$'\033[2m'
UI_CYAN=$'\033[38;2;0;240;255m'
UI_PINK=$'\033[38;2;255;42;109m'
UI_YELLOW=$'\033[38;2;252;238;10m'
UI_GREEN=$'\033[38;2;57;255;136m'
UI_RED=$'\033[38;2;255;70;70m'
UI_FG=$'\033[38;2;220;220;230m'
UI_MUTED=$'\033[38;2;120;130;150m'

UI_STEP=0
UI_STEPS_TOTAL=10
UI_PROFILE="${UI_PROFILE:-}"
UI_AUTHOR="Mactavish410"
UI_REPO="arch-dotfiles"

ui_supports_color() {
  [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]] && [[ "${TERM:-}" != "dumb" ]]
}

if ! ui_supports_color; then
  UI_RESET="" UI_BOLD="" UI_DIM="" UI_CYAN="" UI_PINK="" UI_YELLOW=""
  UI_GREEN="" UI_RED="" UI_FG="" UI_MUTED=""
fi

ui_clear() {
  [[ -t 1 ]] || return 0
  printf '\033[2J\033[H'
}

ui_line() {
  local w="${1:-56}"
  local i
  printf '%s' "${UI_MUTED}"
  for ((i = 0; i < w; i++)); do printf '─'; done
  printf '%s\n' "${UI_RESET}"
}

ui_banner() {
  cat <<EOF
${UI_CYAN}${UI_BOLD}
    ╔══════════════════════════════════════════════════════╗
    ║                                                      ║
    ║   ${UI_PINK}◆${UI_CYAN}  ${UI_YELLOW}EndeavourOS${UI_CYAN} · Hyprland · Night City           ║
    ║                                                      ║
    ║      ${UI_FG}dotfiles by ${UI_PINK}${UI_BOLD}${UI_AUTHOR}${UI_CYAN}${UI_BOLD}                          ║
    ║      ${UI_MUTED}github.com/${UI_AUTHOR}/${UI_REPO}${UI_CYAN}${UI_BOLD}          ║
    ║                                                      ║
    ╚══════════════════════════════════════════════════════╝
${UI_RESET}
EOF
}

# Progress bar: ui_bar CURRENT TOTAL [label] [width]
ui_bar() {
  local cur="$1" total="$2" label="${3:-}" width="${4:-36}"
  local filled empty pct i
  (( total < 1 )) && total=1
  (( cur < 0 )) && cur=0
  (( cur > total )) && cur="${total}"
  pct=$((cur * 100 / total))
  filled=$((cur * width / total))
  empty=$((width - filled))
  printf '  %s[' "${UI_MUTED}"
  printf '%s' "${UI_CYAN}${UI_BOLD}"
  for ((i = 0; i < filled; i++)); do printf '█'; done
  printf '%s' "${UI_MUTED}"
  for ((i = 0; i < empty; i++)); do printf '░'; done
  printf '%s] %s%3d%%%s' "${UI_MUTED}" "${UI_YELLOW}${UI_BOLD}" "${pct}" "${UI_RESET}"
  if [[ -n "${label}" ]]; then
    printf '  %s%s%s' "${UI_FG}" "${label}" "${UI_RESET}"
  fi
  printf '\n'
}

ui_set_total() {
  UI_STEPS_TOTAL="$1"
  UI_STEP=0
}

ui_step_begin() {
  local title="$1"
  UI_STEP=$((UI_STEP + 1))
  printf '\n'
  ui_bar "${UI_STEP}" "${UI_STEPS_TOTAL}" "${title}"
  printf '  %s▸%s %s%s%s\n' "${UI_PINK}" "${UI_RESET}" "${UI_BOLD}${UI_FG}" "${title}" "${UI_RESET}"
}

ui_ok() {
  printf '  %s✓%s %s\n' "${UI_GREEN}${UI_BOLD}" "${UI_RESET}" "$*"
}

ui_warn() {
  printf '  %s!%s %s\n' "${UI_YELLOW}${UI_BOLD}" "${UI_RESET}" "$*" >&2
}

ui_err() {
  printf '  %s✗%s %s\n' "${UI_RED}${UI_BOLD}" "${UI_RESET}" "$*" >&2
}

ui_info() {
  printf '  %s·%s %s\n' "${UI_CYAN}" "${UI_RESET}" "$*"
}

ui_pkg_progress() {
  # ui_pkg_progress index total pkgname
  local i="$1" n="$2" pkg="$3"
  printf '\r'
  ui_bar "${i}" "${n}" "${pkg}" 28
  # move cursor up one line next time? keep simple: one line overwrite via \r only works for single line
}

# Interactive profile picker. Sets UI_PROFILE=light|full|full-ai
ui_pick_profile() {
  local choice disk_mib
  disk_mib="$(df -Pk / 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024}')"
  disk_mib="${disk_mib:-0}"

  if [[ -n "${UI_PROFILE}" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    UI_PROFILE="light"
    return 0
  fi

  printf '\n  %sВыбери профиль установки%s  %s(свободно ≈ %s MiB)%s\n\n' \
    "${UI_BOLD}${UI_FG}" "${UI_RESET}" "${UI_MUTED}" "${disk_mib}" "${UI_RESET}"

  printf '  %s[1]%s  %sЛёгкая%s     — минимум места, VM / тест\n' \
    "${UI_CYAN}${UI_BOLD}" "${UI_RESET}" "${UI_BOLD}" "${UI_RESET}"
  printf '       %sHyprland, темы, Firefox, без Docker/Cursor/CUDA/OBS%s\n\n' "${UI_MUTED}" "${UI_RESET}"

  printf '  %s[2]%s  %sПолная%s     — боевой rice + extras\n' \
    "${UI_PINK}${UI_BOLD}" "${UI_RESET}" "${UI_BOLD}" "${UI_RESET}"
  printf '       %s+ Docker, Ollama, Cursor, Sunshine, NekoBox, zapret%s\n\n' "${UI_MUTED}" "${UI_RESET}"

  printf '  %s[3]%s  %sПолная + AI%s — как полная + CUDA / ollama-cuda\n' \
    "${UI_YELLOW}${UI_BOLD}" "${UI_RESET}" "${UI_BOLD}" "${UI_RESET}"
  printf '       %sнужно ≥20 GiB свободно и NVIDIA%s\n\n' "${UI_MUTED}" "${UI_RESET}"

  while true; do
    printf '  %sПрофиль [1/2/3]%s (Enter = 1 лёгкая): ' "${UI_CYAN}" "${UI_RESET}"
    read -r choice || choice="1"
    choice="${choice:-1}"
    case "${choice}" in
      1|l|L|light) UI_PROFILE="light"; break ;;
      2|f|F|full) UI_PROFILE="full"; break ;;
      3|a|A|ai|full-ai) UI_PROFILE="full-ai"; break ;;
      *) printf '  %sвведи 1, 2 или 3%s\n' "${UI_YELLOW}" "${UI_RESET}" ;;
    esac
  done

  printf '\n  %sВыбрано:%s %s%s%s\n' \
    "${UI_MUTED}" "${UI_RESET}" "${UI_BOLD}${UI_CYAN}" "${UI_PROFILE}" "${UI_RESET}"
}

ui_apply_profile_flags() {
  case "${UI_PROFILE}" in
    light)
      INSTALL_HEAVY_AI=0
      INSTALL_EXTRAS=0
      INSTALL_PROFILE=light
      ;;
    full)
      INSTALL_HEAVY_AI=0
      INSTALL_EXTRAS=1
      INSTALL_PROFILE=full
      ;;
    full-ai)
      INSTALL_HEAVY_AI=1
      INSTALL_EXTRAS=1
      INSTALL_PROFILE=full
      ;;
    *)
      INSTALL_PROFILE="${INSTALL_PROFILE:-full}"
      ;;
  esac
  export INSTALL_HEAVY_AI INSTALL_EXTRAS INSTALL_PROFILE UI_PROFILE
}

ui_finish_banner() {
  local profile="${UI_PROFILE:-unknown}"
  cat <<EOF

${UI_CYAN}${UI_BOLD}
    ╔══════════════════════════════════════════════════════╗
    ║  ${UI_GREEN}✓${UI_CYAN}  Установка завершена · профиль ${UI_YELLOW}${profile}${UI_CYAN}              ║
    ║     ${UI_FG}by ${UI_PINK}${UI_AUTHOR}${UI_CYAN} · reboot → Hyprland (SDDM)           ║
    ╚══════════════════════════════════════════════════════╝
${UI_RESET}
EOF
}
