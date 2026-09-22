#!/usr/bin/env bash
# Toggle region screen recording with wf-recorder + slurp.
set -euo pipefail

PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/endeavouros-wf-recorder.pid"
OUTDIR="${HOME}/Videos/Recordings"
mkdir -p "${OUTDIR}"

if [[ -f "${PIDFILE}" ]]; then
  oldpid="$(cat "${PIDFILE}" 2>/dev/null || true)"
  if [[ -n "${oldpid}" ]] && kill -0 "${oldpid}" 2>/dev/null; then
    kill -INT "${oldpid}" 2>/dev/null || kill "${oldpid}" 2>/dev/null || true
    rm -f "${PIDFILE}"
    command -v notify-send >/dev/null 2>&1 && notify-send "Recording" "Stopped"
    exit 0
  fi
  rm -f "${PIDFILE}"
fi

if ! command -v wf-recorder >/dev/null 2>&1; then
  echo "wf-recorder not installed" >&2
  exit 1
fi
if ! command -v slurp >/dev/null 2>&1; then
  echo "slurp not installed" >&2
  exit 1
fi

GEOM="$(slurp)" || exit 1
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${OUTDIR}/rec-${STAMP}.mp4"

command -v notify-send >/dev/null 2>&1 && notify-send "Recording" "Started → ${OUT}"

wf-recorder -g "${GEOM}" -f "${OUT}" &
echo $! > "${PIDFILE}"
wait || true
rm -f "${PIDFILE}"
command -v notify-send >/dev/null 2>&1 && notify-send "Recording" "Saved ${OUT}"
