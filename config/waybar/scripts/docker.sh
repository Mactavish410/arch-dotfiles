#!/usr/bin/env bash
# Waybar: running Docker containers count
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  printf '{"text":"DKR —","tooltip":"docker not installed","class":"docker"}\n'
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  printf '{"text":"DKR off","tooltip":"docker daemon unavailable","class":"docker-off"}\n'
  exit 0
fi

count="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
names="$(docker ps --format '{{.Names}}' 2>/dev/null | paste -sd ', ' - || true)"
tooltip="${names:-no running containers}"

printf '{"text":"DKR %s","tooltip":"%s","class":"docker"}\n' "$count" "$tooltip"
