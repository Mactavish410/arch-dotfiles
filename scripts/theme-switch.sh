#!/usr/bin/env bash
# Apply / list EndeavourOS Hyprland themes (cyberpunk default).
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
THEMES_DIR="${DOTFILES_DIR}/themes"
WALLPAPERS_DIR="${DOTFILES_DIR}/wallpapers"
CURRENT_FILE="${THEMES_DIR}/.current"
DRY_RUN="${THEME_SWITCH_DRY_RUN:-0}"

log() { printf '[theme] %s\n' "$*"; }
warn() { printf '[theme] WARN: %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [list|apply <theme>|rofi]

  list           print available theme names
  apply <name>   copy theme files, set wallpaper, reload UI
  (no args)      rofi picker (falls back to list)
EOF
}

list_themes() {
  [[ -d "${THEMES_DIR}" ]] || return 0
  local d
  for d in "${THEMES_DIR}"/*/; do
    [[ -d "${d}" ]] || continue
    basename "${d}"
  done | sort
}

pick_theme() {
  local themes
  themes="$(list_themes)"
  [[ -n "${themes}" ]] || { warn "no themes in ${THEMES_DIR}"; exit 1; }
  if command -v rofi >/dev/null 2>&1 && [[ "${DRY_RUN}" != "1" ]]; then
    printf '%s\n' "${themes}" | rofi -dmenu -p "Theme" -i
  else
    printf '%s\n' "${themes}" | head -n1
  fi
}

copy_if_exists() {
  local src="$1" dest="$2"
  [[ -f "${src}" ]] || return 0
  mkdir -p "$(dirname "${dest}")"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY copy ${src} → ${dest}"
    return 0
  fi
  cp -f "${src}" "${dest}"
  log "copied $(basename "${src}") → ${dest}"
}

apply_gtk_qt() {
  local theme="$1"
  local tdir="${THEMES_DIR}/${theme}"
  local gtk_dir="${HOME}/.config/gtk-3.0"
  local gtk4_dir="${HOME}/.config/gtk-4.0"
  local qt5="${HOME}/.config/qt5ct/qt5ct.conf"
  local qt6="${HOME}/.config/qt6ct/qt6ct.conf"

  # Optional theme-provided GTK/Qt fragments
  copy_if_exists "${tdir}/gtk-settings.ini" "${gtk_dir}/settings.ini"
  copy_if_exists "${tdir}/gtk4-settings.ini" "${gtk4_dir}/settings.ini"
  copy_if_exists "${tdir}/qt5ct.conf" "${qt5}"
  copy_if_exists "${tdir}/qt6ct.conf" "${qt6}"

  # Sensible defaults when theme ships no GTK file
  if [[ ! -f "${tdir}/gtk-settings.ini" && "${DRY_RUN}" != "1" ]]; then
    mkdir -p "${gtk_dir}"
    local gtk_theme="Adwaita-dark"
    local icon_theme="Papirus-Dark"
    local cursor_theme="Bibata-Modern-Classic"
    case "${theme}" in
      gruvbox-dark) gtk_theme="gruvbox-dark"; icon_theme="gruvbox-dark-icons-gtk" ;;
      *) ;;
    esac
    cat > "${gtk_dir}/settings.ini" <<EOF
[Settings]
gtk-theme-name=${gtk_theme}
gtk-icon-theme-name=${icon_theme}
gtk-cursor-theme-name=${cursor_theme}
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-application-prefer-dark-theme=1
EOF
    mkdir -p "${gtk4_dir}"
    cp -f "${gtk_dir}/settings.ini" "${gtk4_dir}/settings.ini"
  fi

  if [[ ! -f "${tdir}/qt5ct.conf" && "${DRY_RUN}" != "1" ]]; then
    mkdir -p "$(dirname "${qt5}")" "$(dirname "${qt6}")"
    for qconf in "${qt5}" "${qt6}"; do
      if [[ ! -f "${qconf}" ]]; then
        cat > "${qconf}" <<'EOF'
[Appearance]
style=Fusion
color_scheme_path=
custom_palette=false
icon_theme=Papirus-Dark
standard_dialogs=default
style_sheets=

[Fonts]
fixed=@Variant(\0\0\0@\0\0\0\x12\0J\0\x65\0t\0B\0r\0\x61\0i\0n\0s\0M\0o\0n\0o\0 \0N\0\x65\0r\0\x64\0 \0F\0o\0n\0t@\0\0\0\0\0\0\0\x16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0)
general=@Variant(\0\0\0@\0\0\0\x12\0J\0\x65\0t\0B\0r\0\x61\0i\0n\0s\0M\0o\0n\0o\0 \0N\0\x65\0r\0\x64\0 \0F\0o\0n\0t@\0\0\0\0\0\0\0\x16\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0)
EOF
      fi
    done
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    mkdir -p "${HOME}/.config"
    cat > "${HOME}/.config/kdeglobals" <<EOF || true
[General]
ColorScheme=
[Icons]
Theme=Papirus-Dark
EOF
  fi
}

set_wallpaper() {
  local theme="$1"
  local img=""
  local candidate

  # Prefer stable wallpaper.jpg (symlink from fetch-wallpapers.sh), then any image in folder.
  for candidate in \
    "${WALLPAPERS_DIR}/${theme}/wallpaper.jpg" \
    "${WALLPAPERS_DIR}/${theme}/wallpaper.png" \
    "${WALLPAPERS_DIR}/${theme}/"* \
    "${THEMES_DIR}/${theme}/wallpaper.png" \
    "${THEMES_DIR}/${theme}/wallpaper.jpg" \
    "${THEMES_DIR}/${theme}/wallpaper.jpeg" \
    "${THEMES_DIR}/${theme}/wallpaper.webp"
  do
    [[ -e "${candidate}" ]] || continue
    [[ -f "${candidate}" || -L "${candidate}" ]] || continue
    case "${candidate}" in
      *.png|*.jpg|*.jpeg|*.webp|*.PNG|*.JPG|*.JPEG|*.WEBP)
        img="${candidate}"
        break
        ;;
    esac
  done

  [[ -n "${img}" ]] || { warn "no wallpaper for ${theme}"; return 0; }
  [[ "${DRY_RUN}" == "1" ]] && { log "DRY wallpaper ${img}"; return 0; }

  if command -v swww >/dev/null 2>&1; then
    if ! pgrep -x swww-daemon >/dev/null 2>&1; then
      swww-daemon &
      sleep 0.4
    fi
    swww img "${img}" --transition-type fade --transition-duration 0.8 || \
      swww img "${img}" || warn "swww failed"
  elif command -v hyprctl >/dev/null 2>&1; then
    warn "swww missing — set wallpaper manually: ${img}"
  fi
}

reload_ui() {
  [[ "${DRY_RUN}" == "1" ]] && { log "DRY reload skipped"; return 0; }

  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || warn "hyprctl reload failed"
  fi

  if pgrep -x waybar >/dev/null 2>&1; then
    killall -SIGUSR2 waybar 2>/dev/null || {
      killall waybar 2>/dev/null || true
      waybar >/dev/null 2>&1 &
    }
  fi

  if command -v dunst >/dev/null 2>&1; then
    killall dunst 2>/dev/null || true
    dunst >/dev/null 2>&1 &
  fi

  if command -v kitten >/dev/null 2>&1; then
    kitten @ load-config-file >/dev/null 2>&1 || true
  fi
}

apply_theme() {
  local theme="$1"
  local tdir="${THEMES_DIR}/${theme}"

  [[ -d "${tdir}" ]] || { echo "theme not found: ${theme}" >&2; exit 1; }

  copy_if_exists "${tdir}/hypr.conf" "${HOME}/.config/hypr/colors.conf"
  copy_if_exists "${tdir}/palette.conf" "${HOME}/.config/hypr/palette.conf"
  copy_if_exists "${tdir}/waybar.css" "${HOME}/.config/waybar/style.css"
  copy_if_exists "${tdir}/rofi.rasi" "${HOME}/.config/rofi/theme.rasi"
  copy_if_exists "${tdir}/kitty.conf" "${HOME}/.config/kitty/theme.conf"
  copy_if_exists "${tdir}/dunst.conf" "${HOME}/.config/dunst/dunstrc"
  # Themes ship a full hyprlock.conf (not a fragment) — overwrite the live config.
  copy_if_exists "${tdir}/hyprlock.conf" "${HOME}/.config/hypr/hyprlock.conf"
  copy_if_exists "${tdir}/starship.toml" "${HOME}/.config/starship.toml"
  copy_if_exists "${tdir}/wlogout.css" "${HOME}/.config/wlogout/style.css"
  copy_if_exists "${tdir}/gtk.css" "${HOME}/.config/gtk-3.0/gtk.css"
  copy_if_exists "${tdir}/gtk.css" "${HOME}/.config/gtk-4.0/gtk.css"

  apply_gtk_qt "${theme}"
  set_wallpaper "${theme}"

  if [[ "${DRY_RUN}" != "1" ]]; then
    mkdir -p "${THEMES_DIR}"
    printf '%s\n' "${theme}" > "${CURRENT_FILE}"
  else
    log "DRY would write ${CURRENT_FILE} = ${theme}"
  fi

  reload_ui
  log "applied theme: ${theme}"
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    list)
      list_themes
      ;;
    apply)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      apply_theme "$2"
      ;;
    -h|--help)
      usage
      ;;
    "")
      local picked
      picked="$(pick_theme)"
      [[ -n "${picked}" ]] || exit 1
      apply_theme "${picked}"
      ;;
    *)
      # Convenience: theme-switch cyberpunk
      if [[ -d "${THEMES_DIR}/${cmd}" ]]; then
        apply_theme "${cmd}"
      else
        usage
        exit 1
      fi
      ;;
  esac
}

main "$@"
