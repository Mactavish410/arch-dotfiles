# EndeavourOS

```
 _____           _                                  ___  ____
| ____|_ __   __| | ___  __ ___   _____  _   _ _ __/ _ \/ ___|
|  _| | '_ \ / _` |/ _ \/ _` \ \ / / _ \| | | | '__| | | \___ \
| |___| | | | (_| |  __/ (_| |\ V / (_) | |_| | |  | |_| |___) |
|_____|_| |_|\__,_|\___|\__,_| \_/ \___/ \__,_|_|   \___/|____/
```

**EndeavourOS · Hyprland · Night City · AI-ready**

Dotfiles для трёхмониторного риса с темами, обходом DPI, VPN, Tailscale, Sunshine и локальным AI-стеком на отдельном `DATA_ROOT`.

[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-00f0ff?style=flat-square&logo=wayland&logoColor=white)](https://hyprland.org/)
[![Arch](https://img.shields.io/badge/Arch-EndeavourOS-1793d1?style=flat-square&logo=archlinux&logoColor=white)](https://endeavouros.com/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-modeset-76b900?style=flat-square&logo=nvidia&logoColor=white)](https://wiki.archlinux.org/title/NVIDIA)
[![Ollama](https://img.shields.io/badge/Ollama-local_LLM-ff2a6d?style=flat-square)](https://ollama.com/)
[![CI](https://img.shields.io/badge/tests-run.sh-fcee0a?style=flat-square)](.github/workflows/test.yml)
[![License](https://img.shields.io/badge/license-MIT-0d0208?style=flat-square)](LICENSE)

> Скриншоты риса — после первого живого входа (Super+Shift+S). Пока placeholder: cyberpunk neon на почти чёрном `#0d0208`.

---

## Features

| Desktop | Network | AI | Remote | Storage |
|---------|---------|-----|--------|---------|
| 3 монитора, тайлинг Hyprland | **zapret** — обход DPI | Ollama на DATA_ROOT | Sunshine + Moonlight | `DATA_ROOT` → docker / ollama / media |
| 8 тем, дефолт **cyberpunk** | **sing-box** + `vpn.sh` | Open WebUI (Docker) | SSH через Tailscale | `~/Projects`, Documents отдельно |
| `SUPER+T` — переключатель | NekoBox (GUI, вручную) | CUDA + nvidia-ctk | KDE Connect | фильмотека не на SSD корня |
| waybar GPU / Ollama | Tailscale mesh | voice assistant stub | | |

---

## Themes

Дефолт при install — **cyberpunk**. Переключение: `SUPER+T` или `theme-switch apply <name>`.

| Тема | Характер | Акценты |
|------|----------|---------|
| **cyberpunk** ★ | Night City, неон | `#0d0208` · `#00f0ff` · `#ff2a6d` · `#fcee0a` |
| **gruvbox-dark** | тёплый классический rice | `#282828` · `#fe8019` · `#b8bb26` · `#fabd2f` |
| **catppuccin-mocha** | мягкий neon rain | mauve `#cba6f7` |
| **tokyo-night** | холодный city night | `#7aa2f7` · `#bb9af7` |
| **dracula** | фиолетовый контраст | `#bd93f9` · `#ff79c6` |
| **nord** | спокойный arctic | `#88c0d0` · `#81a1c1` |
| **rose-pine** | приглушённый розовый | `#c4a7e7` · `#ebbcba` |
| **everforest-dark** | лесной, глаза отдыхают | `#a7c080` · `#e67e80` |

Палитры лежат в `themes/<name>/`; обои — в `wallpapers/<name>/` (скачиваются скриптом, не в git).

---

## Quick start

Полный путь от ISO до готовой системы — в **[INSTALL.md](INSTALL.md)** (фазы 0–8).

```bash
git clone <URL> ~/dotfiles && cd ~/dotfiles
cp .env.example .env    # DATA_ROOT, ключи, VPN_*
./install.sh
# reboot → войти в Hyprland (SDDM)
```

Перед install: смонтировать большой диск в `/mnt/data`, поставить `git` + `base-devel`. См. [Фазу 3](INSTALL.md#фаза-3--первый-вход-и-первостипенные-вещи).

---

## Keybindings

| Хоткей | Действие |
|--------|----------|
| `SUPER` + `Return` | терминал (kitty) |
| `SUPER` + `D` | rofi launcher |
| `SUPER` + `Q` | закрыть окно |
| `SUPER` + `V` | буфер (cliphist) |
| `SUPER` + `L` | lock (hyprlock) |
| `SUPER` + `T` | смена темы |
| `SUPER` + `Space` | AI-ассистент |
| `SUPER` + `SHIFT` + `S` | скриншот области |
| `SUPER` + `SHIFT` + `R` | запись экрана (wf-recorder) |
| `SUPER` + `SHIFT` + `E` | wlogout |
| `Alt` + `Shift` | раскладка US ↔ RU |

---

## Layout

```
~/dotfiles/
├── install.sh · track.sh · pkglist*.txt · .env.example
├── themes/          # 8 палитр (не симлинк всего ~/.config)
├── wallpapers/      # 4K по темам (fetch-wallpapers.sh)
├── scripts/         # theme-switch, vpn, ai_assistant, nvidia-modeset…
├── config/          # hypr, waybar, rofi, kitty, dunst, sing-box…
├── home/            # .zshrc, .gitconfig
├── docker/open-webui/
├── systemd/user/
└── tests/
```

Тяжёлые данные — на **`DATA_ROOT`** (по умолчанию `/mnt/data`): docker, ollama, media/torrents, ComfyUI. Домашний SSD — только код и доки. Подробности: [INSTALL.md → Диски](INSTALL.md#фаза-3--первый-вход-и-первостипенные-вещи).

---

## Network roles

Не включайте всё сразу — иначе двойной NAT/DNS и «нет сети».

| Режим | zapret | sing-box / vpn | Tailscale |
|-------|--------|----------------|-----------|
| **Домашний RU-обход** (дефолт) | ON | OFF | mesh OK, без Exit Node |
| **VPS-прокси** | лучше OFF | `vpn start` | mesh OK |
| **NekoBox** | — | не параллельно с `vpn.sh` | — |

После install: zapret ON, VPN OFF, Tailscale установлен — `tailscale up` вручную.

---

## Tests

Автотесты не требуют Hyprland/pacman — синтаксис shell, структура тем, JSON/compose, LF, парсер AI.

```bash
./tests/run.sh
```

CI: [`.github/workflows/test.yml`](.github/workflows/test.yml) (Ubuntu + shellcheck + python3).  
На Windows — Git Bash или WSL.

---

## Docs

| Документ | Содержание |
|----------|------------|
| [INSTALL.md](INSTALL.md) | От USB до ready: фазы 0–8, чеклисты, NVIDIA, DATA_ROOT |
| [wallpapers/SOURCES.md](wallpapers/SOURCES.md) | URL / авторы / лицензии обоев |
| [.env.example](.env.example) | DATA_ROOT, Ollama, VPN, API keys |

---

## Участие пользователя

Агент и `install.sh` не заменят: запись ISO, разметку дисков, пароли, `.env` секреты, `tailscale up`, pairing Sunshine, импорт VPN-подписки, первый `ollama pull`. Полный список — в [INSTALL.md](INSTALL.md#что-нужно-сделать-вам).

---

## Disclaimer

- NVIDIA + Wayland: нужен `nvidia_drm.modeset=1` (см. INSTALL и `scripts/nvidia-modeset.sh`).
- Не включать zapret + global VPN + Tailscale Exit Node одновременно.
- Конфиги — **MIT**. Обои качайте легально через `fetch-wallpapers.sh`; чужой copyrighted art в репо не кладём.
|