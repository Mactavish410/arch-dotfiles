#!/usr/bin/env bash
# bash -n (+ shellcheck -x если установлен) на ключевые скрипты.
# Отсутствующие пути — SKIP с сообщением, не фейл (sibling agents ещё пишут файлы).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
CHECKED=0
SKIPPED=0

# Обязательные к проверке, когда появятся (план репо)
SCRIPTS=(
  "install.sh"
  "track.sh"
  "scripts/vpn.sh"
  "scripts/theme-switch.sh"
  "scripts/nvidia-modeset.sh"
  "scripts/fetch-wallpapers.sh"
  "scripts/setup-home-dirs.sh"
  "scripts/record-screen.sh"
  "scripts/validate-pkglists.sh"
  "scripts/ui.sh"
  "tests/run.sh"
  "tests/test_shell_syntax.sh"
  "tests/test_theme_structure.sh"
  "tests/test_json_configs.sh"
  "tests/test_gitattributes.sh"
)

# Опциональные waybar / bin хуки — проверяем если есть
OPTIONAL_GLOBS=(
  "scripts/*.sh"
  "bin/*"
  "config/waybar/scripts/*.sh"
)

check_file() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "  SKIP (нет файла): $f"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  # пропускаем не-shell
  case "$f" in
    *.py|*.md|*.txt|*.json|*.jsonc|*.yml|*.yaml|*.toml|*.css|*.rasi|*.conf|*.example)
      return 0
      ;;
  esac
  if ! head -n 1 "$f" | grep -qE '^#!.*(bash|sh)'; then
    # исполняемые без shebang в bin/ — всё равно bash -n если похоже на shell
    if ! grep -qE '^(set |if |function |\[\[)' "$f" 2>/dev/null; then
      echo "  SKIP (не shell): $f"
      SKIPPED=$((SKIPPED + 1))
      return 0
    fi
  fi
  echo "  bash -n: $f"
  if ! bash -n "$f"; then
    echo "  FAIL: синтаксис $f"
    FAIL=$((FAIL + 1))
    return 0
  fi
  CHECKED=$((CHECKED + 1))
  if command -v shellcheck >/dev/null 2>&1; then
    # -x: follow source; не фейлим на SC-warnings style — только errors? Plan: shellcheck -x
    if ! shellcheck -x "$f"; then
      echo "  FAIL: shellcheck $f"
      FAIL=$((FAIL + 1))
    fi
  fi
}

echo "=== test_shell_syntax ==="

for s in "${SCRIPTS[@]}"; do
  check_file "$s"
done

# Дополнительные .sh из glob (уникальные)
declare -A SEEN=()
for s in "${SCRIPTS[@]}"; do
  SEEN["$s"]=1
done

for pattern in "${OPTIONAL_GLOBS[@]}"; do
  # shellcheck disable=SC2086
  for f in $pattern; do
    [[ -e "$f" ]] || continue
    [[ -n "${SEEN[$f]+x}" ]] && continue
    SEEN["$f"]=1
    check_file "$f"
  done
done

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "  INFO: shellcheck не установлен — пропущен (в CI ставится)"
fi

echo "Checked=$CHECKED Skipped-missing=$SKIPPED Failures=$FAIL"

if [[ "$CHECKED" -eq 0 && "$SKIPPED" -gt 0 ]]; then
  echo "WARN: ни одного shell-скрипта ещё нет — структура ожидается по плану"
fi

[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
