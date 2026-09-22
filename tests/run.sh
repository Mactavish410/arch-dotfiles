#!/usr/bin/env bash
# EndeavourOS — единая точка входа автотестов.
# Не требует Hyprland/pacman. Exit ≠ 0 при любом фейле.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

run_one() {
  local name="$1"
  local script="$2"
  echo ""
  echo "════════════════════════════════════════"
  echo "▶ $name"
  echo "════════════════════════════════════════"
  if [[ ! -f "$script" ]]; then
    echo "SKIP: файл теста отсутствует: $script"
    SKIP=$((SKIP + 1))
    return 0
  fi
  set +e
  if [[ "$script" == *.py ]]; then
    python3 "$script"
    rc=$?
  else
    bash "$script"
    rc=$?
  fi
  set -e
  case "$rc" in
    0)
      echo "PASS: $name"
      PASS=$((PASS + 1))
      ;;
    77)
      # условный skip (как automake)
      echo "SKIP: $name"
      SKIP=$((SKIP + 1))
      ;;
    *)
      echo "FAIL: $name (exit $rc)"
      FAIL=$((FAIL + 1))
      ;;
  esac
}

echo "EndeavourOS tests — ROOT=$ROOT"
echo "date: $(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"

run_one "shell syntax"        "tests/test_shell_syntax.sh"
run_one "theme structure"     "tests/test_theme_structure.sh"
run_one "json configs"        "tests/test_json_configs.sh"
run_one "gitattributes / LF"  "tests/test_gitattributes.sh"
run_one "ai assistant"        "tests/test_ai_assistant.py"

echo ""
echo "────────────────────────────────────────"
echo "PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
echo "────────────────────────────────────────"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
