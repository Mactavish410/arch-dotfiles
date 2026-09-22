#!/usr/bin/env bash
# Waybar: Ollama status / loaded models
set -euo pipefail

HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"

if ! curl -sf --max-time 1 "${HOST}/api/tags" >/dev/null 2>&1; then
  printf '{"text":"LLM off","tooltip":"Ollama not reachable at %s","class":"ollama-off"}\n' "$HOST"
  exit 0
fi

models="$(curl -sf --max-time 2 "${HOST}/api/tags" 2>/dev/null \
  | python -c 'import sys,json; d=json.load(sys.stdin); print(", ".join(m.get("name","?") for m in d.get("models",[])) or "none")' 2>/dev/null || echo "?")"

ps_count="$(curl -sf --max-time 2 "${HOST}/api/ps" 2>/dev/null \
  | python -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get("models",[])))' 2>/dev/null || echo 0)"

printf '{"text":"LLM %s","tooltip":"models: %s","class":"ollama"}\n' "$ps_count" "$models"
