#!/usr/bin/env bash
# EndeavourOS / Hyprland installer — Mactavish410/arch-dotfiles
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${DOTFILES_DIR}/scripts/lib.sh"
# shellcheck source=scripts/ui.sh
source "${DOTFILES_DIR}/scripts/ui.sh"

log()  { ui_ok "$*"; }
warn() { ui_warn "$*"; }
die()  { ui_err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "нет команды: $1"
}

parse_args() {
  local a
  for a in "$@"; do
    case "${a}" in
      --light|-l) UI_PROFILE="light" ;;
      --full|-f) UI_PROFILE="full" ;;
      --full-ai|--ai) UI_PROFILE="full-ai" ;;
      --help|-h)
        cat <<EOF
Usage: ./install.sh [--light|--full|--full-ai]

  --light     минимальный rice (VM)
  --full      полный desktop + extras
  --full-ai   полный + CUDA / ollama-cuda

Без флага — интерактивный выбор.
EOF
        exit 0
        ;;
    esac
  done
}

ensure_env() {
  if [[ ! -f "${DOTFILES_DIR}/.env" ]]; then
    cp "${DOTFILES_DIR}/.env.example" "${DOTFILES_DIR}/.env"
    ui_info "создан .env из .env.example"
  fi
  load_dotfiles_env "${DOTFILES_DIR}/.env"
  DATA_ROOT="${DATA_ROOT:-/mnt/data}"
  DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${DATA_ROOT}/docker}"
  OLLAMA_MODELS="${OLLAMA_MODELS:-${DATA_ROOT}/ollama}"
  INSTALL_HEAVY_AI="${INSTALL_HEAVY_AI:-0}"
  INSTALL_EXTRAS="${INSTALL_EXTRAS:-0}"
  INSTALL_PROFILE="${INSTALL_PROFILE:-}"
  # CLI / picker override .env
  if [[ -n "${UI_PROFILE}" ]]; then
    ui_apply_profile_flags
  elif [[ -n "${INSTALL_PROFILE}" ]]; then
    UI_PROFILE="${INSTALL_PROFILE}"
    ui_apply_profile_flags
  fi
  export DATA_ROOT DOCKER_DATA_ROOT OLLAMA_MODELS INSTALL_HEAVY_AI INSTALL_EXTRAS INSTALL_PROFILE
}

persist_profile_to_env() {
  local envf="${DOTFILES_DIR}/.env"
  [[ -f "${envf}" ]] || return 0
  grep -q '^INSTALL_PROFILE=' "${envf}" 2>/dev/null \
    && sed -i "s/^INSTALL_PROFILE=.*/INSTALL_PROFILE=${INSTALL_PROFILE}/" "${envf}" \
    || printf '\nINSTALL_PROFILE=%s\n' "${INSTALL_PROFILE}" >> "${envf}"
  grep -q '^INSTALL_HEAVY_AI=' "${envf}" 2>/dev/null \
    && sed -i "s/^INSTALL_HEAVY_AI=.*/INSTALL_HEAVY_AI=${INSTALL_HEAVY_AI}/" "${envf}" \
    || printf 'INSTALL_HEAVY_AI=%s\n' "${INSTALL_HEAVY_AI}" >> "${envf}"
  grep -q '^INSTALL_EXTRAS=' "${envf}" 2>/dev/null \
    && sed -i "s/^INSTALL_EXTRAS=.*/INSTALL_EXTRAS=${INSTALL_EXTRAS}/" "${envf}" \
    || printf 'INSTALL_EXTRAS=%s\n' "${INSTALL_EXTRAS}" >> "${envf}"
}

fs_avail_kib() {
  local path="$1"
  df -Pk "${path}" 2>/dev/null | awk 'NR==2 {print $4}'
}

check_disk_space() {
  local cache_avail root_avail
  cache_avail="$(fs_avail_kib /var/cache/pacman/pkg 2>/dev/null || fs_avail_kib /)"
  root_avail="$(fs_avail_kib /)"
  cache_avail="${cache_avail:-0}"
  root_avail="${root_avail:-0}"

  ui_info "свободно: / ≈ $((root_avail / 1024)) MiB · cache ≈ $((cache_avail / 1024)) MiB"

  if [[ "${root_avail}" -lt $((512 * 1024)) ]]; then
    die "диск почти полный (<512 MiB). df -h · sudo pacman -Scc · rm -rf ~/.cache/yay"
  fi

  if [[ "${cache_avail}" -lt $((3 * 1024 * 1024)) ]]; then
    warn "мало места (<3 GiB) — тяжёлые пакеты могут упасть"
    if [[ "${INSTALL_HEAVY_AI}" == "1" || "${INSTALL_EXTRAS}" == "1" ]]; then
      if [[ "${UI_PROFILE}" != "light" ]]; then
        warn "рекомендуется профиль light или увеличить диск VM"
      fi
    fi
    if [[ "${INSTALL_HEAVY_AI}" == "1" ]]; then
      die "full-ai нужен запас места — освободи диск или выбери --full / --light"
    fi
  fi
}

install_yay() {
  if command -v yay >/dev/null 2>&1; then
    ui_ok "yay уже установлен"
    return 0
  fi
  need_cmd git
  need_cmd makepkg
  local tmp
  tmp="$(mktemp -d)"
  ui_info "ставим yay из AUR…"
  git clone https://aur.archlinux.org/yay.git "${tmp}/yay"
  (cd "${tmp}/yay" && makepkg -si --noconfirm)
  rm -rf "${tmp}"
  ui_ok "yay готов"
}

install_nvidia_drivers() {
  if pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia 2>/dev/null | grep -q .; then
    ui_ok "NVIDIA уже есть: $(pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia 2>/dev/null | tr '\n' ' ')"
    return 0
  fi
  if [[ "${INSTALL_PROFILE}" == "light" ]]; then
    ui_info "light: пропускаем установку NVIDIA (оставь драйвер из EOS)"
    return 0
  fi
  ui_info "ставим nvidia-open-dkms…"
  if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils || \
      warn "nvidia-open-dkms не встал"
  else
    sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils || \
      warn "nvidia-dkms не встал"
  fi
}

want_heavy_ai() {
  case "${INSTALL_HEAVY_AI:-0}" in
    1|yes|true|TRUE|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

pacman_install_list() {
  local list_file="$1"
  local -a want=() have=() missing=()
  local pkg i n

  need_cmd pacman
  mapfile -t want < <(grep -E '^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$' "${list_file}" || true)
  [[ ${#want[@]} -gt 0 ]] || { warn "пустой список: ${list_file}"; return 0; }

  sudo pacman -Sy --noconfirm >/dev/null

  for pkg in "${want[@]}"; do
    if pacman -Si "${pkg}" >/dev/null 2>&1 || pacman -Sg "${pkg}" >/dev/null 2>&1; then
      have+=("${pkg}")
    else
      missing+=("${pkg}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "нет в repos: ${missing[*]}"
  fi
  [[ ${#have[@]} -gt 0 ]] || { warn "нечего ставить из $(basename "${list_file}")"; return 0; }

  n="${#have[@]}"
  ui_info "official: ${n} пакетов ← $(basename "${list_file}")"
  if sudo pacman -S --needed --noconfirm "${have[@]}"; then
    ui_ok "пакеты установлены (${n})"
    return 0
  fi

  warn "батч упал — по одному…"
  i=0
  for pkg in "${have[@]}"; do
    i=$((i + 1))
    printf '  '
    ui_bar "${i}" "${n}" "${pkg}" 24
    sudo pacman -S --needed --noconfirm "${pkg}" || warn "fail: ${pkg}"
  done
}

aur_install_list() {
  local list_file="$1"
  local -a want=()
  local pkg i n avail

  need_cmd yay
  mapfile -t want < <(grep -E '^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$' "${list_file}" || true)
  [[ ${#want[@]} -gt 0 ]] || return 0

  avail="$(fs_avail_kib /home 2>/dev/null || fs_avail_kib /)"
  avail="${avail:-0}"
  if [[ "${avail}" -lt $((1024 * 1024)) ]]; then
    warn "skip AUR — <1 GiB (нужен ~/.cache/yay)"
    return 0
  fi

  n="${#want[@]}"
  ui_info "AUR: ${n} ← $(basename "${list_file}")"
  i=0
  for pkg in "${want[@]}"; do
    i=$((i + 1))
    printf '  '
    ui_bar "${i}" "${n}" "${pkg}" 24
    if yay -Si "${pkg}" >/dev/null 2>&1; then
      yay -S --needed --noconfirm "${pkg}" || warn "AUR fail: ${pkg}"
    else
      warn "AUR не найден: ${pkg}"
    fi
  done
}

install_ai_stack() {
  if ! want_heavy_ai; then
    ui_info "CUDA/AI stack пропущен"
    return 0
  fi
  [[ -f "${DOTFILES_DIR}/pkglist_ai.txt" ]] || return 0
  if pacman -Qq ollama >/dev/null 2>&1 && ! pacman -Qq ollama-cuda >/dev/null 2>&1; then
    sudo pacman -Rdd --noconfirm ollama 2>/dev/null || true
  fi
  pacman_install_list "${DOTFILES_DIR}/pkglist_ai.txt"
}

install_packages() {
  local official_list aur_list

  check_disk_space

  if command -v pacman >/dev/null 2>&1; then
    if ! bash "${DOTFILES_DIR}/scripts/validate-pkglists.sh"; then
      die "validate-pkglists.sh failed — поправь pkglist*.txt"
    fi
  fi

  if [[ "${INSTALL_PROFILE}" == "light" ]]; then
    official_list="${DOTFILES_DIR}/pkglist_light.txt"
    aur_list="${DOTFILES_DIR}/pkglist_aur_light.txt"
  else
    official_list="${DOTFILES_DIR}/pkglist.txt"
    aur_list="${DOTFILES_DIR}/pkglist_aur.txt"
  fi

  pacman_install_list "${official_list}"
  install_nvidia_drivers
  install_ai_stack
  aur_install_list "${aur_list}"

  if [[ "${INSTALL_EXTRAS}" == "1" && -f "${DOTFILES_DIR}/pkglist_aur_extra.txt" ]]; then
    aur_install_list "${DOTFILES_DIR}/pkglist_aur_extra.txt"
  else
    ui_info "extras (Cursor/Sunshine/NekoBox) пропущены"
  fi
}

link_tree() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    if [[ -L "${dest}" ]]; then
      rm -f "${dest}"
    elif [[ -d "${dest}" && ! -L "${dest}" ]]; then
      warn "backup ${dest} → ${dest}.bak.endeavouros"
      mv "${dest}" "${dest}.bak.endeavouros"
    else
      warn "backup ${dest} → ${dest}.bak.endeavouros"
      mv "${dest}" "${dest}.bak.endeavouros"
    fi
  fi
  ln -snf "${src}" "${dest}"
}

symlink_configs() {
  local item name child cname
  if [[ -d "${DOTFILES_DIR}/config" ]]; then
    shopt -s nullglob
    for item in "${DOTFILES_DIR}/config"/*; do
      name="$(basename "${item}")"
      [[ "${name}" == *.example ]] && continue
      if [[ -d "${item}" ]]; then
        mkdir -p "${HOME}/.config/${name}"
        for child in "${item}"/*; do
          [[ -e "${child}" ]] || continue
          cname="$(basename "${child}")"
          [[ "${cname}" == *.example ]] && continue
          link_tree "${child}" "${HOME}/.config/${name}/${cname}"
        done
      else
        link_tree "${item}" "${HOME}/.config/${name}"
      fi
    done
    shopt -u nullglob
  fi

  if [[ -d "${DOTFILES_DIR}/home" ]]; then
    shopt -s nullglob dotglob
    for item in "${DOTFILES_DIR}/home"/.* "${DOTFILES_DIR}/home"/*; do
      [[ -e "${item}" ]] || continue
      name="$(basename "${item}")"
      [[ "${name}" == "." || "${name}" == ".." ]] && continue
      link_tree "${item}" "${HOME}/${name}"
    done
    shopt -u nullglob dotglob
  fi

  mkdir -p "${HOME}/.config/systemd/user"
  if [[ -d "${DOTFILES_DIR}/systemd/user" ]]; then
    shopt -s nullglob
    for item in "${DOTFILES_DIR}/systemd/user"/*; do
      name="$(basename "${item}")"
      link_tree "${item}" "${HOME}/.config/systemd/user/${name}"
    done
    shopt -u nullglob
  fi
  systemctl --user daemon-reload || true

  mkdir -p "${HOME}/.local/bin"
  if [[ -d "${DOTFILES_DIR}/bin" ]]; then
    shopt -s nullglob
    for item in "${DOTFILES_DIR}/bin"/*; do
      name="$(basename "${item}")"
      link_tree "${item}" "${HOME}/.local/bin/${name}"
    done
    shopt -u nullglob
  fi
  ui_ok "симлинки config/home/bin"
}

setup_data_root() {
  if [[ "${INSTALL_PROFILE}" == "light" ]]; then
    ui_info "light: DATA_ROOT минимально (${DATA_ROOT})"
    sudo mkdir -p "${DATA_ROOT}" 2>/dev/null || mkdir -p "${DATA_ROOT}" || true
    sudo chown "${USER}:${USER}" "${DATA_ROOT}" 2>/dev/null || true
    mkdir -p "${DATA_ROOT}/backups"
    return 0
  fi

  ui_info "DATA_ROOT=${DATA_ROOT}"
  if [[ ! -d "${DATA_ROOT}" ]]; then
    warn "${DATA_ROOT} нет — создаём (см. INSTALL.md)"
    sudo mkdir -p "${DATA_ROOT}"
    sudo chown "${USER}:${USER}" "${DATA_ROOT}"
  fi

  mkdir -p \
    "${DOCKER_DATA_ROOT}" \
    "${OLLAMA_MODELS}" \
    "${DATA_ROOT}/media/movies" \
    "${DATA_ROOT}/media/series" \
    "${DATA_ROOT}/media/torrents" \
    "${DATA_ROOT}/ai/comfyui" \
    "${DATA_ROOT}/ai/datasets" \
    "${DATA_ROOT}/ai/open-webui" \
    "${DATA_ROOT}/backups"

  sudo mkdir -p /etc/docker
  if [[ -f /etc/docker/daemon.json ]]; then
    sudo cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.endeavouros.$(date +%s)"
  fi
  sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "data-root": "${DOCKER_DATA_ROOT}"
}
EOF

  if pacman -Qq ollama ollama-cuda >/dev/null 2>&1; then
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_MODELS=${OLLAMA_MODELS}"
EOF
    sudo systemctl daemon-reload
  fi
  ui_ok "DATA_ROOT настроен"
}

setup_docker_nvidia() {
  if [[ "${INSTALL_PROFILE}" == "light" ]]; then
    ui_info "light: Docker/NVIDIA runtime пропущен"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker нет — skip"
    return 0
  fi
  sudo systemctl enable --now docker
  sudo usermod -aG docker "${USER}" || true
  if command -v nvidia-ctk >/dev/null 2>&1; then
    sudo nvidia-ctk runtime configure --runtime=docker || warn "nvidia-ctk fail"
    sudo systemctl restart docker || true
  fi
  if command -v nvidia-smi >/dev/null 2>&1; then
    sudo nvidia-smi -pm 1 || true
  fi
  ui_ok "docker готов"
}

enable_sddm() {
  # EOS may already have plasmalogin/gdm/lightdm as display-manager.service
  if ! pacman -Qq sddm >/dev/null 2>&1; then
    warn "sddm не установлен — skip DM"
    return 0
  fi

  local current=""
  if [[ -L /etc/systemd/system/display-manager.service ]]; then
    current="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
  fi

  if [[ "${current}" == *sddm.service ]]; then
    ui_ok "SDDM уже display-manager"
    return 0
  fi

  if [[ -n "${current}" ]]; then
    ui_info "сменяем DM ($(basename "${current}")) → sddm"
    # Disable whatever owns display-manager.service (plasmalogin, gdm, …)
    sudo systemctl disable display-manager.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/display-manager.service 2>/dev/null || true
  fi

  if sudo systemctl enable sddm.service 2>/dev/null; then
    ui_ok "SDDM включён"
  else
    warn "не удалось enable sddm — вручную: sudo systemctl enable sddm.service"
  fi
}

setup_services() {
  sudo systemctl enable --now NetworkManager 2>/dev/null || true
  sudo systemctl enable --now bluetooth 2>/dev/null || true
  sudo systemctl enable --now sshd 2>/dev/null || true
  enable_sddm

  if [[ "${INSTALL_PROFILE}" != "light" ]]; then
    sudo systemctl enable --now tailscaled 2>/dev/null || true
    if pacman -Qq ollama ollama-cuda >/dev/null 2>&1; then
      sudo systemctl enable --now ollama 2>/dev/null || true
    fi
    if systemctl list-unit-files 2>/dev/null | grep -qE '^zapret(\.service)?'; then
      sudo systemctl enable --now zapret 2>/dev/null || \
        sudo systemctl enable --now zapret.service 2>/dev/null || true
    fi
    systemctl --user disable --now sing-box-vpn.service 2>/dev/null || true
    if systemctl list-unit-files 2>/dev/null | grep -qi '^sunshine'; then
      sudo systemctl enable --now sunshine 2>/dev/null || \
        systemctl --user enable --now sunshine 2>/dev/null || true
    fi
  fi
  ui_ok "сервисы"
}

setup_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  # Never abort install on ufw quirks (missing app profiles, etc.)
  sudo ufw --force reset >/dev/null 2>&1 || true
  sudo ufw default deny incoming || true
  sudo ufw default allow outgoing || true
  # Prefer port over app profile — "OpenSSH" profile often missing
  sudo ufw allow 22/tcp comment 'SSH' || true
  sudo ufw allow OpenSSH 2>/dev/null || true
  if [[ "${INSTALL_PROFILE}" != "light" ]]; then
    sudo ufw allow in on tailscale0 || true
    sudo ufw allow 47984:48010/tcp || true
    sudo ufw allow 47984:48010/udp || true
  fi
  sudo ufw --force enable || warn "ufw enable не удался"
  ui_ok "ufw"
}

setup_zram() {
  if ! pacman -Q zram-generator >/dev/null 2>&1; then
    return 0
  fi
  sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  sudo systemctl daemon-reload
  sudo systemctl start systemd-zram-setup@zram0.service 2>/dev/null || true
  ui_ok "zram"
}

generate_vpn_config() {
  local example="${DOTFILES_DIR}/config/sing-box/config.json.example"
  local dest="${DOTFILES_DIR}/config/sing-box/config.json"
  local live="${HOME}/.config/sing-box/config.json"

  [[ "${INSTALL_PROFILE}" == "light" ]] && return 0
  [[ -f "${example}" ]] || return 0

  if [[ ! -f "${dest}" ]]; then
    load_dotfiles_env "${DOTFILES_DIR}/.env"
    sed \
      -e "s|__VPS_IP__|${VPS_IP:-123.45.67.89}|g" \
      -e "s|__VPN_UUID__|${VPN_UUID:-00000000-0000-0000-0000-000000000000}|g" \
      -e "s|__VPN_PORT__|${VPN_PORT:-443}|g" \
      -e "s|__VPN_SNI__|${VPN_SNI:-www.microsoft.com}|g" \
      "${example}" > "${dest}"
    chmod 600 "${dest}"
  fi
  mkdir -p "${HOME}/.config/sing-box"
  [[ -e "${live}" ]] || ln -snf "${dest}" "${live}"
  ui_ok "sing-box шаблон"
}

post_theme_and_dirs() {
  chmod +x \
    "${DOTFILES_DIR}/install.sh" \
    "${DOTFILES_DIR}/track.sh" \
    "${DOTFILES_DIR}/scripts/"*.sh \
    "${DOTFILES_DIR}/bin/"* 2>/dev/null || true

  "${DOTFILES_DIR}/scripts/setup-home-dirs.sh" || warn "setup-home-dirs"

  if [[ "${INSTALL_PROFILE}" == "light" ]]; then
    ui_info "light: обои — только cyberpunk (быстрее)"
    # fetch script downloads all themes; still OK if space allows
  fi
  if ! "${DOTFILES_DIR}/scripts/fetch-wallpapers.sh"; then
    warn "обои: повтори ./scripts/fetch-wallpapers.sh"
  else
    ui_ok "обои"
  fi

  if [[ "${INSTALL_PROFILE}" != "light" ]]; then
    "${DOTFILES_DIR}/scripts/nvidia-modeset.sh" || warn "nvidia-modeset"
  fi

  if [[ -x "${DOTFILES_DIR}/scripts/theme-switch.sh" ]]; then
    "${DOTFILES_DIR}/scripts/theme-switch.sh" apply cyberpunk || warn "theme-switch"
    ui_ok "тема cyberpunk"
  fi
}

print_checklist() {
  ui_finish_banner
  cat <<EOF
${UI_MUTED}  Post-checklist:${UI_RESET}
  ${UI_FG}[ ]${UI_RESET} reboot → SDDM → Hyprland
  ${UI_FG}[ ]${UI_RESET} правь .env (DATA_ROOT, VPN_*, keys)
EOF
  if [[ "${INSTALL_PROFILE}" != "light" ]]; then
    cat <<EOF
  ${UI_FG}[ ]${UI_RESET} sudo tailscale up
  ${UI_FG}[ ]${UI_RESET} Sunshine pair / vpn start (не вместе с zapret full-tunnel)
  ${UI_FG}[ ]${UI_RESET} ollama pull ${OLLAMA_MODEL:-qwen2.5-coder:7b}
EOF
  fi
  if [[ "${INSTALL_HEAVY_AI}" == "1" ]]; then
    printf '  %s[ ]%s docker compose -f docker/open-webui/docker-compose.yml up -d\n' "${UI_FG}" "${UI_RESET}"
  fi
  printf '  %s[ ]%s hyprctl monitors — поправь monitors.conf\n\n' "${UI_FG}" "${UI_RESET}"
  printf '  %sby %s · github.com/%s/%s%s\n\n' \
    "${UI_MUTED}" "${UI_PINK}${UI_AUTHOR}${UI_MUTED}" "${UI_AUTHOR}" "${UI_REPO}" "${UI_RESET}"
}

main() {
  parse_args "$@"
  ui_clear
  ui_banner
  ui_pick_profile
  ui_apply_profile_flags
  ensure_env
  persist_profile_to_env

  ui_set_total 11
  ui_line
  ui_info "профиль ${UI_PROFILE} · HEAVY_AI=${INSTALL_HEAVY_AI} · EXTRAS=${INSTALL_EXTRAS}"

  ui_step_begin "yay"
  install_yay

  ui_step_begin "пакеты (${INSTALL_PROFILE})"
  install_packages

  ui_step_begin "симлинки"
  symlink_configs

  ui_step_begin "DATA_ROOT"
  setup_data_root

  ui_step_begin "Docker / NVIDIA"
  setup_docker_nvidia

  ui_step_begin "сервисы"
  setup_services

  ui_step_begin "ufw"
  setup_ufw

  ui_step_begin "zram"
  setup_zram

  ui_step_begin "VPN шаблон"
  generate_vpn_config

  ui_step_begin "темы и обои"
  post_theme_and_dirs

  ui_step_begin "готово"
  print_checklist
}

main "$@"
