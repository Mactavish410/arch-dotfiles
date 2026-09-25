#!/usr/bin/env bash
# Нет CRLF в текстовых исходниках (*.sh, *.conf, *.css, …).
# Учитывает .gitattributes (* text eol=lf).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0
CHECKED=0

echo "=== test_gitattributes ==="

if [[ -f .gitattributes ]]; then
  if grep -qE 'text[[:space:]]+eol=lf|\*[[:space:]]+text[[:space:]]+eol=lf' .gitattributes; then
    echo "  OK: .gitattributes задаёт eol=lf"
  else
    echo "  WARN: .gitattributes есть, но нет явного '* text eol=lf'"
  fi
else
  echo "  SKIP: .gitattributes ещё нет (ожидается sibling agent: '* text eol=lf')"
fi

# Расширения текстовых файлов из плана
EXTS="sh conf css rasi json jsonc yml yaml toml md py txt example service"

crlf_check() {
  local f="$1"
  # ищем CR (0x0D)
  if grep -qU $'\r' "$f" 2>/dev/null || grep -l $'\r' "$f" >/dev/null 2>&1; then
    # portable: use file or od
    if LC_ALL=C grep -q $'\r' "$f"; then
      echo "  FAIL: CRLF в $f"
      FAIL=$((FAIL + 1))
      return 0
    fi
  fi
  if LC_ALL=C grep -q $'\r' "$f" 2>/dev/null; then
    echo "  FAIL: CRLF в $f"
    FAIL=$((FAIL + 1))
    return 0
  fi
  CHECKED=$((CHECKED + 1))
}

# Собрать файлы без find - слишком тяжело на огромных деревьях; ограничиваем
PATHS=()
while IFS= read -r -d '' f; do
  PATHS+=("$f")
done < <(
  # shellcheck disable=SC2086
  for ext in $EXTS; do
    find . -type f -name "*.${ext}" \
      ! -path "./.git/*" \
      ! -path "./.venv/*" \
      ! -path "./node_modules/*" \
      ! -path "./wallpapers/*/*.png" \
      -print0 2>/dev/null
  done
  # файлы без расширения, важные
  for f in install.sh track.sh .env.example .gitattributes .gitignore; do
    [[ -f "$f" ]] && printf '%s\0' "./$f"
  done
)

# dedupe
declare -A SEEN=()
UNIQUE=()
for f in "${PATHS[@]+"${PATHS[@]}"}"; do
  [[ -n "${SEEN[$f]+x}" ]] && continue
  SEEN["$f"]=1
  UNIQUE+=("$f")
done

if [[ "${#UNIQUE[@]}" -eq 0 ]]; then
  echo "  WARN: текстовых файлов для проверки LF пока мало/нет"
else
  for f in "${UNIQUE[@]}"; do
    crlf_check "$f"
  done
fi

# Явно проверить наши тесты и доки (всегда должны быть LF)
for must in README.md INSTALL.md tests/run.sh tests/test_shell_syntax.sh \
  tests/test_theme_structure.sh tests/test_json_configs.sh \
  tests/test_gitattributes.sh tests/test_ai_assistant.py \
  .github/workflows/test.yml; do
  if [[ -f "$must" ]]; then
    if LC_ALL=C grep -q $'\r' "$must" 2>/dev/null; then
      echo "  FAIL: CRLF в обязательном $must"
      FAIL=$((FAIL + 1))
    else
      echo "  OK LF: $must"
    fi
  fi
done

echo "Scanned≈$CHECKED Failures=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
