#!/usr/bin/env bash
# EndeavourOS — bootstrap Hyprland dotfiles
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${DOTFILES_DIR}/scripts/lib.sh"

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARN: %s\n' "$*" >&2; }
die()  { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command missing: $1"
}

ensure_env() {
  if [[ ! -f "${DOTFILES_DIR}/.env" ]]; then
    cp "${DOTFILES_DIR}/.env.example" "${DOTFILES_DIR}/.env"
    log "created .env from .env.example — edit secrets before VPN/AI use"
  fi
  load_dotfiles_env "${DOTFILES_DIR}/.env"
  DATA_ROOT="${DATA_ROOT:-/mnt/data}"
  DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${DATA_ROOT}/docker}"
  OLLAMA_MODELS="${OLLAMA_MODELS:-${DATA_ROOT}/ollama}"
  INSTALL_HEAVY_AI="${INSTALL_HEAVY_AI:-0}"
  export DATA_ROOT DOCKER_DATA_ROOT OLLAMA_MODELS INSTALL_HEAVY_AI
}

install_yay() {
  if command -v yay >/dev/null 2>&1; then
    log "yay already installed"
    return 0
  fi
  need_cmd git
  need_cmd makepkg
  local tmp
  tmp="$(mktemp -d)"
  log "installing yay from AUR"
  git clone https://aur.archlinux.org/yay.git "${tmp}/yay"
  (cd "${tmp}/yay" && makepkg -si --noconfirm)
  rm -rf "${tmp}"
}

# Skip proprietary nvidia-dkms if EOS already has nvidia-open*
install_nvidia_drivers() {
  if pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia 2>/dev/null | grep -q .; then
    log "NVIDIA driver already present: $(pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia 2>/dev/null | tr '\n' ' ')"
    return 0
  fi
  log "no NVIDIA driver found — installing nvidia-open-dkms (Turing+)"
  if pacman -Si nvidia-open-dkms >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils || \
      warn "nvidia-open-dkms install failed — install drivers manually"
  else
    sudo pacman -S --needed --noconfirm nvidia-dkms nvidia-utils || \
      warn "nvidia-dkms install failed — install drivers manually"
  fi
}

# Free space in KiB for a path (filesystem of that path).
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

  log "disk free: / ≈ $((root_avail / 1024)) MiB, pacman cache fs ≈ $((cache_avail / 1024)) MiB"

  # < 3 GiB free → downloads often die with "Failure writing output to destination"
  if [[ "${cache_avail}" -lt $((3 * 1024 * 1024)) ]]; then
    warn "мало места (<3 GiB) — pacman будет падать на больших пакетах (ollama-cuda/cuda)"
    warn "проверь: df -h   и очисти кэш: sudo pacman -Scc"
    if [[ "${INSTALL_HEAVY_AI:-0}" == "1" ]]; then
      die "INSTALL_HEAVY_AI=1, но места недостаточно — освободи диск или поставь INSTALL_HEAVY_AI=0"
    fi
  fi
}

# cuda + cudnn + ollama-cuda are multi‑GB; skip on VM / small disks unless asked.
want_heavy_ai() {
  local avail
  case "${INSTALL_HEAVY_AI:-0}" in
    1|yes|true|TRUE|Yes) return 0 ;;
    0|no|false|FALSE|No) return 1 ;;
    auto)
      avail="$(fs_avail_kib /)"
      avail="${avail:-0}"
      if [[ "${avail}" -lt $((20 * 1024 * 1024)) ]]; then
        warn "INSTALL_HEAVY_AI=auto: <20 GiB free — skip cuda/cudnn/ollama-cuda"
        return 1
      fi
      if ! pacman -Qq nvidia-open-dkms nvidia-open nvidia-dkms nvidia 2>/dev/null | grep -q .; then
        warn "INSTALL_HEAVY_AI=auto: нет NVIDIA — skip heavy AI (use plain ollama)"
        return 1
      fi
      return 0
      ;;
    *) return 1 ;;
  esac
}

install_ai_stack() {
  if ! want_heavy_ai; then
    log "heavy AI skipped (INSTALL_HEAVY_AI=${INSTALL_HEAVY_AI:-0}) — base ollama from pkglist is enough for VM"
    log "на боевой машине с местом: INSTALL_HEAVY_AI=1 в .env и: sudo pacman -S --needed - < pkglist_ai.txt"
    return 0
  fi
  if [[ -f "${DOTFILES_DIR}/pkglist_ai.txt" ]]; then
    log "installing heavy AI stack from pkglist_ai.txt"
    # Replace CPU ollama with CUDA build when both would conflict
    if pacman -Qq ollama >/dev/null 2>&1 && ! pacman -Qq ollama-cuda >/dev/null 2>&1; then
      sudo pacman -Rdd --noconfirm ollama 2>/dev/null || true
    fi
    pacman_install_list "${DOTFILES_DIR}/pkglist_ai.txt"
  fi
}

# Install only packages that exist in sync DB (missing → warn, continue).
# Supports package groups (e.g. base-devel).
pacman_install_list() {
  local list_file="$1"
  local -a want=() have=() missing=()
  local pkg

  need_cmd pacman
  mapfile -t want < <(grep -E '^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$' "${list_file}" || true)
  [[ ${#want[@]} -gt 0 ]] || { warn "empty package list: ${list_file}"; return 0; }

  sudo pacman -Sy --noconfirm

  for pkg in "${want[@]}"; do
    if pacman -Si "${pkg}" >/dev/null 2>&1 || pacman -Sg "${pkg}" >/dev/null 2>&1; then
      have+=("${pkg}")
    else
      missing+=("${pkg}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "not in official repos (skipped): ${missing[*]}"
    warn "fix names or move to pkglist_aur.txt, then: ./scripts/validate-pkglists.sh"
  fi
  if [[ ${#have[@]} -eq 0 ]]; then
    warn "nothing to install from ${list_file}"
    return 0
  fi

  log "installing ${#have[@]} official packages from $(basename "${list_file}")"
  if ! sudo pacman -S --needed --noconfirm "${have[@]}"; then
    warn "batch install failed — retrying package-by-package"
    local p
    for p in "${have[@]}"; do
      sudo pacman -S --needed --noconfirm "${p}" || warn "failed: ${p} (диск/зеркало? df -h; sudo pacman -Scc)"
    done
  fi
}

aur_install_list() {
  local list_file="$1"
  local -a want=()
  local pkg

  need_cmd yay
  mapfile -t want < <(grep -E '^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$' "${list_file}" || true)
  [[ ${#want[@]} -gt 0 ]] || { warn "empty AUR list: ${list_file}"; return 0; }

  log "installing AUR packages one-by-one (${#want[@]}) from $(basename "${list_file}")"
  for pkg in "${want[@]}"; do
    if yay -Si "${pkg}" >/dev/null 2>&1; then
      yay -S --needed --noconfirm "${pkg}" || warn "AUR failed: ${pkg}"
    else
      warn "AUR package not found: ${pkg}"
    fi
  done
}

install_packages() {
  check_disk_space

  # Strict validation on the target machine (pacman). API-only hosts warn but continue
  # so Windows editing does not block; EOS always catches bad names before pacman -S.
  if command -v pacman >/dev/null 2>&1; then
    log "preflight: validating package lists (pacman)…"
    if ! bash "${DOTFILES_DIR}/scripts/validate-pkglists.sh"; then
      die "package list validation failed — fix pkglist*.txt (./scripts/validate-pkglists.sh)"
    fi
  else
    warn "pacman not found — skip strict pkg validate (run on EndeavourOS before install)"
  fi

  pacman_install_list "${DOTFILES_DIR}/pkglist.txt"
  install_nvidia_drivers
  install_ai_stack
  aur_install_list "${DOTFILES_DIR}/pkglist_aur.txt"
}

link_tree() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "${dest}")"
  if [[ -e "${dest}" || -L "${dest}" ]]; then
    if [[ -L "${dest}" ]]; then
      rm -f "${dest}"
    elif [[ -d "${dest}" && ! -L "${dest}" ]]; then
      warn "backing up existing directory ${dest} → ${dest}.bak.endeavouros"
      mv "${dest}" "${dest}.bak.endeavouros"
    else
      warn "backing up existing file ${dest} → ${dest}.bak.endeavouros"
      mv "${dest}" "${dest}.bak.endeavouros"
    fi
  fi
  ln -snf "${src}" "${dest}"
  log "linked ${dest} → ${src}"
}

symlink_configs() {
  local item name
  if [[ -d "${DOTFILES_DIR}/config" ]]; then
    shopt -s nullglob
    for item in "${DOTFILES_DIR}/config"/*; do
      name="$(basename "${item}")"
      [[ "${name}" == *.example ]] && continue
      if [[ -d "${item}" ]]; then
        mkdir -p "${HOME}/.config/${name}"
        local child cname
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
}

setup_data_root() {
  log "configuring DATA_ROOT=${DATA_ROOT}"
  if [[ ! -d "${DATA_ROOT}" ]]; then
    warn "${DATA_ROOT} missing — creating locally (mount your data disk per INSTALL.md)"
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
  log "docker data-root → ${DOCKER_DATA_ROOT}"

  sudo mkdir -p /etc/systemd/system/ollama.service.d
  sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_MODELS=${OLLAMA_MODELS}"
EOF
  sudo systemctl daemon-reload
  log "ollama models → ${OLLAMA_MODELS}"
}

setup_docker_nvidia() {
  sudo systemctl enable --now docker
  sudo usermod -aG docker "${USER}" || true

  if command -v nvidia-ctk >/dev/null 2>&1; then
    sudo nvidia-ctk runtime configure --runtime=docker || warn "nvidia-ctk configure failed"
    sudo systemctl restart docker || true
  else
    warn "nvidia-ctk not found — skip NVIDIA container runtime"
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    sudo nvidia-smi -pm 1 || warn "nvidia-smi -pm 1 failed"
  fi
}

setup_services() {
  sudo systemctl enable --now NetworkManager || true
  sudo systemctl enable --now bluetooth || true
  sudo systemctl enable --now sshd || true
  sudo systemctl enable --now tailscaled || true
  sudo systemctl enable --now ollama || true
  sudo systemctl enable sddm || true

  # Network default: zapret ON, sing-box OFF (AUR package: zapret-git)
  if systemctl list-unit-files 2>/dev/null | grep -qE '^zapret(\.service)?'; then
    sudo systemctl enable --now zapret 2>/dev/null || \
      sudo systemctl enable --now zapret.service 2>/dev/null || \
      warn "could not enable zapret"
  else
    warn "zapret unit not found — after zapret-git: sudo systemctl enable --now zapret"
  fi

  systemctl --user disable --now sing-box-vpn.service 2>/dev/null || true

  if systemctl list-unit-files | grep -qi '^sunshine'; then
    sudo systemctl enable --now sunshine || \
      systemctl --user enable --now sunshine || \
      warn "enable sunshine manually after first login"
  fi
}

setup_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw not installed"
    return 0
  fi
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow OpenSSH
  sudo ufw allow in on tailscale0 || true
  # Sunshine / Moonlight ports
  sudo ufw allow 47984:48010/tcp
  sudo ufw allow 47984:48010/udp
  sudo ufw --force enable
  log "ufw enabled (OpenSSH, Tailscale, Sunshine)"
}

setup_zram() {
  if ! pacman -Q zram-generator >/dev/null 2>&1; then
    warn "zram-generator not installed"
    return 0
  fi
  sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  sudo systemctl daemon-reload
  sudo systemctl start systemd-zram-setup@zram0.service 2>/dev/null || \
    warn "zram start deferred until reboot"
  log "zram-generator configured (~1/2 RAM)"
}

generate_vpn_config() {
  local example="${DOTFILES_DIR}/config/sing-box/config.json.example"
  local dest="${DOTFILES_DIR}/config/sing-box/config.json"
  local live="${HOME}/.config/sing-box/config.json"

  if [[ ! -f "${example}" ]]; then
    warn "missing ${example}"
    return 0
  fi

  if [[ ! -f "${dest}" ]]; then
    load_dotfiles_env "${DOTFILES_DIR}/.env"
    sed \
      -e "s|__VPS_IP__|${VPS_IP:-123.45.67.89}|g" \
      -e "s|__VPN_UUID__|${VPN_UUID:-00000000-0000-0000-0000-000000000000}|g" \
      -e "s|__VPN_PORT__|${VPN_PORT:-443}|g" \
      -e "s|__VPN_SNI__|${VPN_SNI:-www.microsoft.com}|g" \
      "${example}" > "${dest}"
    chmod 600 "${dest}"
    log "generated config/sing-box/config.json from .env (edit UUID/SNI)"
  fi

  mkdir -p "${HOME}/.config/sing-box"
  if [[ ! -e "${live}" ]]; then
    ln -snf "${dest}" "${live}"
  fi
}

post_theme_and_dirs() {
  chmod +x \
    "${DOTFILES_DIR}/install.sh" \
    "${DOTFILES_DIR}/track.sh" \
    "${DOTFILES_DIR}/scripts/"*.sh \
    "${DOTFILES_DIR}/bin/"* 2>/dev/null || true

  "${DOTFILES_DIR}/scripts/setup-home-dirs.sh"
  log "downloading 4K wallpapers…"
  if ! "${DOTFILES_DIR}/scripts/fetch-wallpapers.sh"; then
    warn "wallpaper fetch failed — re-run: ${DOTFILES_DIR}/scripts/fetch-wallpapers.sh"
  fi
  "${DOTFILES_DIR}/scripts/nvidia-modeset.sh" || warn "nvidia modeset helper reported issues"

  if [[ -x "${DOTFILES_DIR}/scripts/theme-switch.sh" ]]; then
    "${DOTFILES_DIR}/scripts/theme-switch.sh" apply cyberpunk || warn "theme apply failed (themes missing?)"
  fi
}

print_checklist() {
  cat <<EOF

════════════════════════════════════════════════════════════
 EndeavourOS install finished.
 Reboot (or re-login) for docker group, SDDM, NVIDIA modules.

 Post-checklist:
  [ ] Edit ~/dotfiles/.env (DATA_ROOT, VPN_*, keys)
  [ ] sudo tailscale up
  [ ] Sunshine UI password + Moonlight pair PIN
  [ ] vpn start  OR  keep zapret (do not full-tunnel both)
  [ ] ollama pull ${OLLAMA_MODEL:-qwen2.5-coder:7b}
  [ ] docker compose -f docker/open-webui/docker-compose.yml up -d
  [ ] hyprctl monitors — fix monitors.conf if names differ
════════════════════════════════════════════════════════════
EOF
}

main() {
  ensure_env
  install_yay
  install_packages
  symlink_configs
  setup_data_root
  setup_docker_nvidia
  setup_services
  setup_ufw
  setup_zram
  generate_vpn_config
  post_theme_and_dirs
  print_checklist
}

main "$@"
