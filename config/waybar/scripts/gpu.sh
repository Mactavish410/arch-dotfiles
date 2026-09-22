#!/usr/bin/env bash
# Waybar: NVIDIA GPU util + VRAM
set -euo pipefail

if ! command -v nvidia-smi >/dev/null 2>&1; then
  printf '{"text":"GPU n/a","tooltip":"nvidia-smi not found","class":"gpu"}\n'
  exit 0
fi

read -r util mem_used mem_total <<<"$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -n1 | tr -d ' ')"
util=${util:-0}
mem_used=${mem_used:-0}
mem_total=${mem_total:-0}

printf '{"text":"GPU %s%%","tooltip":"VRAM %s / %s MiB","class":"gpu"}\n' "$util" "$mem_used" "$mem_total"
