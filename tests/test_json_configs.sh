#!/usr/bin/env bash
# JSON / JSONC / compose: waybar, sing-box example, open-webui compose.
# Отсутствующие файлы — SKIP, не FAIL.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
CHECKED=0
SKIPPED=0

echo "=== test_json_configs ==="

strip_jsonc() {
  # убрать // и /* */ комментарии для python json.tool
  python3 - "$@" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
# block comments
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
# line comments (not inside strings — приближение достаточно для waybar)
out = []
for line in text.splitlines():
    in_str = False
    esc = False
    buf = []
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            buf.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            buf.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        buf.append(c)
        i += 1
    out.append("".join(buf))
cleaned = "\n".join(out)
# trailing commas before } or ]
cleaned = re.sub(r",(\s*[}\]])", r"\1", cleaned)
sys.stdout.write(cleaned)
PY
}

check_json_file() {
  local path="$1"
  local kind="${2:-json}"
  if [[ ! -f "$path" ]]; then
    echo "  SKIP (нет файла): $path"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  echo "  check: $path ($kind)"
  if [[ "$kind" == "jsonc" ]]; then
    if ! strip_jsonc "$path" | python3 -m json.tool >/dev/null; then
      echo "  FAIL: невалидный JSONC: $path"
      FAIL=$((FAIL + 1))
      return 0
    fi
  else
    if ! python3 -m json.tool "$path" >/dev/null; then
      echo "  FAIL: невалидный JSON: $path"
      FAIL=$((FAIL + 1))
      return 0
    fi
  fi
  CHECKED=$((CHECKED + 1))
  echo "  OK: $path"
}

check_compose() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "  SKIP (нет файла): $path"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  echo "  check compose: $path"
  if command -v docker >/dev/null 2>&1; then
    if docker compose -f "$path" config >/dev/null 2>&1; then
      CHECKED=$((CHECKED + 1))
      echo "  OK: docker compose config"
      return 0
    fi
    echo "  WARN: docker compose config не прошёл — пробуем PyYAML"
  fi
  if python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1],encoding='utf-8'))" "$path"; then
      CHECKED=$((CHECKED + 1))
      echo "  OK: YAML parse"
      return 0
    fi
    echo "  FAIL: невалидный YAML: $path"
    FAIL=$((FAIL + 1))
    return 0
  fi
  # минимальная проверка: файл не пуст и похож на compose
  if grep -qE '^(services|version):' "$path"; then
    echo "  WARN: нет docker/PyYAML — базовая проверка ключей OK"
    CHECKED=$((CHECKED + 1))
  else
    echo "  FAIL: compose не похож на YAML compose: $path"
    FAIL=$((FAIL + 1))
  fi
}

# План: эти пути должны появиться
check_json_file "config/waybar/config.jsonc" "jsonc"
check_json_file "config/sing-box/config.json.example" "json"
check_compose "docker/open-webui/docker-compose.yml"

# Доп. JSON если появятся
for extra in config/waybar/*.json config/mpv/mpv.conf; do
  [[ -f "$extra" ]] || continue
  case "$extra" in
    *.json) check_json_file "$extra" "json" ;;
  esac
done

# config.json (реальный VPN) в gitignore — если вдруг есть локально, тоже валидируем
if [[ -f "config/sing-box/config.json" ]]; then
  check_json_file "config/sing-box/config.json" "json"
fi

echo "Checked=$CHECKED Skipped=$SKIPPED Failures=$FAIL"

if [[ "$CHECKED" -eq 0 ]]; then
  echo "WARN: ни одного конфига ещё нет — ожидаются waybar/sing-box/compose по плану"
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
