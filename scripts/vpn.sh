#!/usr/bin/env bash
# Control user-level sing-box VPN (do not run alongside full-tunnel zapret).
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "${DOTFILES_DIR}/scripts/lib.sh"
load_dotfiles_env "${DOTFILES_DIR}/.env"

UNIT="sing-box-vpn.service"
CONFIG_REPO="${DOTFILES_DIR}/config/sing-box/config.json"
CONFIG_LIVE="${HOME}/.config/sing-box/config.json"
EXAMPLE="${DOTFILES_DIR}/config/sing-box/config.json.example"

usage() {
  cat <<EOF
Usage: $(basename "$0") <start|stop|restart|status|log|gen>

  start|stop|restart|status  systemctl --user ${UNIT}
  log                        journalctl --user -u ${UNIT} -f
  gen                        regenerate config.json from .env + example
EOF
}

ensure_config() {
  mkdir -p "${HOME}/.config/sing-box"
  if [[ ! -f "${CONFIG_REPO}" ]]; then
    [[ -f "${EXAMPLE}" ]] || { echo "missing ${EXAMPLE}" >&2; exit 1; }
    sed \
      -e "s|__VPS_IP__|${VPS_IP:-123.45.67.89}|g" \
      -e "s|__VPN_UUID__|${VPN_UUID:-00000000-0000-0000-0000-000000000000}|g" \
      -e "s|\"__VPN_PORT__\"|${VPN_PORT:-443}|g" \
      -e "s|__VPN_SNI__|${VPN_SNI:-www.microsoft.com}|g" \
      "${EXAMPLE}" > "${CONFIG_REPO}"
    chmod 600 "${CONFIG_REPO}"
    echo "[vpn] generated ${CONFIG_REPO}"
  fi
  if [[ ! -e "${CONFIG_LIVE}" ]]; then
    ln -snf "${CONFIG_REPO}" "${CONFIG_LIVE}"
  fi
}

warn_conflict() {
  if systemctl is-active --quiet zapret 2>/dev/null || systemctl is-active --quiet zapret.service 2>/dev/null; then
    echo "[vpn] WARN: zapret is active. Prefer: vpn OR zapret full-tunnel — not both." >&2
  fi
  if pgrep -x nekobox >/dev/null 2>&1 || pgrep -xi nekobox >/dev/null 2>&1; then
    echo "[vpn] WARN: NekoBox appears running — avoid parallel tunnels." >&2
  fi
}

cmd="${1:-}"
case "${cmd}" in
  start)
    ensure_config
    warn_conflict
    systemctl --user daemon-reload
    systemctl --user enable --now "${UNIT}"
    systemctl --user --no-pager status "${UNIT}" || true
    ;;
  stop)
    systemctl --user stop "${UNIT}" || true
    systemctl --user disable "${UNIT}" 2>/dev/null || true
    echo "[vpn] stopped"
    ;;
  restart)
    ensure_config
    warn_conflict
    systemctl --user daemon-reload
    systemctl --user restart "${UNIT}"
    systemctl --user --no-pager status "${UNIT}" || true
    ;;
  status)
    systemctl --user --no-pager status "${UNIT}" || true
    ;;
  log)
    journalctl --user -u "${UNIT}" -f
    ;;
  gen)
    rm -f "${CONFIG_REPO}"
    ensure_config
    ;;
  -h|--help|"")
    usage
    [[ -n "${cmd}" ]] || exit 1
    ;;
  *)
    echo "unknown command: ${cmd}" >&2
    usage
    exit 1
    ;;
esac
