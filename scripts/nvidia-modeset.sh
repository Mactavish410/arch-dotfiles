#!/usr/bin/env bash
# Enable NVIDIA DRM KMS modeset (nvidia_drm.modeset=1) for Hyprland.
set -euo pipefail

log() { printf '[nvidia-modeset] %s\n' "$*"; }
warn() { printf '[nvidia-modeset] WARN: %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

MODPROBE_DIR="/etc/modprobe.d"
CONF="${MODPROBE_DIR}/nvidia-modeset.conf"

${SUDO} mkdir -p "${MODPROBE_DIR}"
echo "options nvidia_drm modeset=1" | ${SUDO} tee "${CONF}" >/dev/null
log "wrote ${CONF}"

# GRUB
if [[ -f /etc/default/grub ]]; then
  if grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
    log "GRUB already has nvidia_drm.modeset=1"
  else
    ${SUDO} sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia_drm.modeset=1 /' /etc/default/grub
    if command -v grub-mkconfig >/dev/null 2>&1; then
      ${SUDO} grub-mkconfig -o /boot/grub/grub.cfg || warn "grub-mkconfig failed"
    fi
    log "added nvidia_drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT"
  fi
fi

# systemd-boot entries
if [[ -d /boot/loader/entries ]]; then
  shopt -s nullglob
  for entry in /boot/loader/entries/*.conf; do
    if grep -q 'nvidia_drm.modeset=1' "${entry}"; then
      continue
    fi
    if grep -q '^options ' "${entry}"; then
      ${SUDO} sed -i 's/^options /options nvidia_drm.modeset=1 /' "${entry}"
      log "patched ${entry}"
    fi
  done
  shopt -u nullglob
fi

# mkinitcpio NVIDIA hooks hint
if [[ -f /etc/mkinitcpio.conf ]]; then
  if ! grep -Eq 'MODULES=.*nvidia' /etc/mkinitcpio.conf; then
    warn "consider MODULES=(... nvidia nvidia_modeset nvidia_uvm nvidia_drm) in /etc/mkinitcpio.conf"
  fi
  if command -v mkinitcpio >/dev/null 2>&1; then
    ${SUDO} mkinitcpio -P || warn "mkinitcpio -P failed — reboot after fixing hooks"
  fi
fi

log "nvidia modeset configured — reboot required for full effect"
