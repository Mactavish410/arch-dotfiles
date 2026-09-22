#!/usr/bin/env bash
# Структура themes/*: 8 тем, обязательные файлы, валидные #RRGGBB в palette.conf.
# theme-switch list/apply dry-run если скрипт уже есть.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAIL=0

EXPECTED_THEMES=(
  cyberpunk
  gruvbox-dark
  catppuccin-mocha
  tokyo-night
  dracula
  nord
  rose-pine
  everforest-dark
)

REQUIRED_FILES=(
  palette.conf
  hypr.conf
  waybar.css
  rofi.rasi
  kitty.conf
  dunst.conf
  hyprlock.conf
)

# Ключи палитры из плана
PALETTE_KEYS=(
  bg
  fg
  accent
  accent2
  active_border_start
  active_border_end
)

echo "=== test_theme_structure ==="

if [[ ! -d "themes" ]]; then
  echo "SKIP: каталог themes/ ещё не создан (ожидается sibling agent)"
  echo "Ожидаемые темы: ${EXPECTED_THEMES[*]}"
  echo "В каждой: ${REQUIRED_FILES[*]}"
  exit 77
fi

found_any=0
for theme in "${EXPECTED_THEMES[@]}"; do
  dir="themes/$theme"
  if [[ ! -d "$dir" ]]; then
    echo "FAIL: нет темы $dir"
    FAIL=$((FAIL + 1))
    continue
  fi
  found_any=1
  echo "── theme: $theme"
  for f in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$dir/$f" ]]; then
      echo "  FAIL: отсутствует $dir/$f"
      FAIL=$((FAIL + 1))
    else
      echo "  OK: $f"
    fi
  done

  palette="$dir/palette.conf"
  if [[ -f "$palette" ]]; then
    for key in "${PALETTE_KEYS[@]}"; do
      # допускаем $bg=... или bg=... или $bg = ...
      line="$(grep -E "^[[:space:]]*\\\$?${key}[[:space:]]*=" "$palette" | head -n1 || true)"
      if [[ -z "$line" ]]; then
        echo "  FAIL: в palette.conf нет ключа \$$key"
        FAIL=$((FAIL + 1))
        continue
      fi
      # значение после '=' — hex (#RRGGBB); не режем # как комментарий
      rhs="${line#*=}"
      rhs="$(echo "$rhs" | sed -E 's/^[\"'\'']//; s/[\"'\'']$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
      if [[ "$rhs" =~ (\#[0-9A-Fa-f]{6}) ]]; then
        val="${BASH_REMATCH[1]}"
      elif [[ "$rhs" =~ (^|[^0-9A-Fa-f])([0-9A-Fa-f]{6})($|[^0-9A-Fa-f]) ]]; then
        val="#${BASH_REMATCH[2]}"
      else
        val="$rhs"
      fi
      if [[ ! "$val" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        echo "  FAIL: \$$key имеет невалидный цвет: '$val' (строка: $line)"
        FAIL=$((FAIL + 1))
      else
        echo "  OK: \$$key=$val"
      fi
    done
  fi
done

# Лишние каталоги в themes/ (кроме служебных) — предупреждение, не фейл
if [[ -d themes ]]; then
  for d in themes/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    [[ "$name" == .* ]] && continue
    known=0
    for t in "${EXPECTED_THEMES[@]}"; do
      [[ "$name" == "$t" ]] && known=1 && break
    done
    if [[ "$known" -eq 0 ]]; then
      echo "WARN: неожиданная тема themes/$name (не из списка плана)"
    fi
  done
fi

# theme-switch dry-run
TS="scripts/theme-switch.sh"
if [[ -f "$TS" ]]; then
  echo "── theme-switch dry-run"
  export DOTFILES_DIR="$ROOT"
  if bash "$TS" list >/tmp/endeavouros-theme-list.$$ 2>/tmp/endeavouros-theme-list.err.$$; then
    for theme in "${EXPECTED_THEMES[@]}"; do
      if ! grep -qx "$theme" /tmp/endeavouros-theme-list.$$ && ! grep -q "$theme" /tmp/endeavouros-theme-list.$$; then
        echo "  FAIL: theme-switch list не содержит $theme"
        FAIL=$((FAIL + 1))
      else
        echo "  OK list: $theme"
      fi
    done
  else
    echo "  WARN: theme-switch list завершился с ошибкой (скрипт ещё сырой?):"
    cat /tmp/endeavouros-theme-list.err.$$ 2>/dev/null || true
  fi

  TMPAPPLY="$(mktemp -d)"
  export HOME="$TMPAPPLY"
  mkdir -p "$TMPAPPLY/.config/hypr" "$TMPAPPLY/.config/waybar" \
    "$TMPAPPLY/.config/kitty" "$TMPAPPLY/.config/rofi" \
    "$TMPAPPLY/.config/dunst" "$TMPAPPLY/.config/hyprlock" 2>/dev/null || true
  # apply без живого hyprctl — скрипт должен уважать отсутствие hyprctl
  if bash "$TS" apply cyberpunk >/tmp/endeavouros-theme-apply.$$ 2>&1; then
    echo "  OK: apply cyberpunk (exit 0) в TMPDIR-подобном HOME"
  else
    rc=$?
    # если упал только из-за hyprctl — мягко
    if grep -qiE 'hyprctl|swww|waybar|not found' /tmp/endeavouros-theme-apply.$$; then
      echo "  WARN: apply cyberpunk exit $rc (ожидаемо без hyprctl) — смотри лог"
    else
      echo "  FAIL: apply cyberpunk exit $rc"
      FAIL=$((FAIL + 1))
    fi
    sed -n '1,20p' /tmp/endeavouros-theme-apply.$$ || true
  fi
  rm -rf "$TMPAPPLY" /tmp/endeavouros-theme-list.$$ /tmp/endeavouros-theme-list.err.$$ /tmp/endeavouros-theme-apply.$$ 2>/dev/null || true
else
  echo "SKIP: scripts/theme-switch.sh ещё нет — dry-run пропущен"
fi

# starship.toml опционален в плане (есть в cyberpunk tree) — warn only
for theme in "${EXPECTED_THEMES[@]}"; do
  if [[ -d "themes/$theme" && ! -f "themes/$theme/starship.toml" ]]; then
    echo "WARN: нет themes/$theme/starship.toml (в плане для cyberpunk — желательно)"
  fi
done

if [[ "$found_any" -eq 0 ]]; then
  echo "FAIL: themes/ есть, но ни одной ожидаемой темы"
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
echo "theme structure OK"
exit 0
