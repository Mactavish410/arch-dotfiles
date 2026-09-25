# arch-dotfiles

```
 _____           _                                  ___  ____
| ____|_ __   __| | ___  __ ___   _____  _   _ _ __/ _ \/ ___|
|  _| | '_ \ / _` |/ _ \/ _` \ \ / / _ \| | | | '__| | | \___ \
| |___| | | | (_| |  __/ (_| |\ V / (_) | |_| | |  | |_| |___) |
|_____|_| |_|\__,_|\___|\__,_| \_/ \___/ \__,_|_|   \___/|____/
```

**Мои** dotfiles под [EndeavourOS](https://endeavouros.com/) · Hyprland · Night City · локальный AI

Репозиторий: [github.com/Mactavish410/arch-dotfiles](https://github.com/Mactavish410/arch-dotfiles)

Трёхмониторный rice: темы, обход DPI, VPN, Tailscale, Sunshine и AI-стек на отдельном `DATA_ROOT`.

[![Hyprland](https://img.shields.io/badge/Hyprland-Wayland-00f0ff?style=flat-square&logo=wayland&logoColor=white)](https://hyprland.org/)
[![Arch](https://img.shields.io/badge/Arch-EndeavourOS-1793d1?style=flat-square&logo=archlinux&logoColor=white)](https://endeavouros.com/)
[![NVIDIA](https://img.shields.io/badge/NVIDIA-modeset-76b900?style=flat-square&logo=nvidia&logoColor=white)](https://wiki.archlinux.org/title/NVIDIA)
[![Ollama](https://img.shields.io/badge/Ollama-local_LLM-ff2a6d?style=flat-square)](https://ollama.com/)
[![CI](https://img.shields.io/badge/tests-run.sh-fcee0a?style=flat-square)](.github/workflows/test.yml)
[![License](https://img.shields.io/badge/license-MIT-0d0208?style=flat-square)](LICENSE)

> Скриншоты — после первого живого входа (`Super+Shift+S`). Пока placeholder: neon на `#0d0208`.

---

## Features

| Desktop | Network | AI | Remote | Storage |
|---------|---------|-----|--------|---------|
| 3 монитора, Hyprland | **zapret** — обход DPI | Ollama на DATA_ROOT | Sunshine + Moonlight | `DATA_ROOT` → docker / ollama / media |
| 8 тем, дефолт **cyberpunk** | **sing-box** + `vpn.sh` | Open WebUI (Docker) | SSH через Tailscale | `~/Projects`, Documents отдельно |
| `SUPER+T` — смена темы | NekoBox (GUI) | CUDA + nvidia-ctk | KDE Connect | фильмотека не на SSD корня |
| waybar GPU / Ollama | Tailscale mesh | voice assistant | | |

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
| **everforest-dark** | лесной | `#a7c080` · `#e67e80` |

Палитры — `themes/<name>/`. Обои 4K качает **`scripts/fetch-wallpapers.sh`** во время `./install.sh` (в git бинарники не лежат).

---

## Quick start

Полный путь от ISO — в **[INSTALL.md](INSTALL.md)** (фазы 0–8).

```bash
git clone https://github.com/Mactavish410/arch-dotfiles.git ~/dotfiles
cd ~/dotfiles
cp .env.example .env    # DATA_ROOT, ключи, VPN_*
chmod +x install.sh track.sh scripts/*.sh bin/* tests/*.sh
./install.sh
# reboot → Hyprland (SDDM)
```

`install.sh` в конце сам запускает `scripts/fetch-wallpapers.sh` (4K по всем темам) и `theme-switch apply cyberpunk`. Нужна сеть. Перед установкой пакетов — `scripts/validate-pkglists.sh` (имена official/AUR).

Перед install: большой диск в `/mnt/data`, пакеты `git` + `base-devel`. См. [фазу 3](INSTALL.md#фаза-3--первый-вход-и-первостипенные-вещи).

---

## Keybindings

| Хоткей | Действие |
|--------|----------|
| `SUPER` + `Return` | терминал (kitty) |
| `SUPER` + `D` | rofi |
| `SUPER` + `Q` | закрыть окно |
| `SUPER` + `V` | буфер (cliphist) |
| `SUPER` + `L` | lock (hyprlock) |
| `SUPER` + `T` | смена темы |
| `SUPER` + `Space` | AI-ассистент |
| `SUPER` + `SHIFT` + `S` | скриншот области |
| `SUPER` + `SHIFT` + `R` | запись экрана |
| `SUPER` + `SHIFT` + `E` | wlogout |
| `Alt` + `Shift` | раскладка US ↔ RU |

---

## Layout

```
~/dotfiles/
├── install.sh · track.sh · pkglist*.txt · .env.example
├── themes/          # 8 палитр
├── wallpapers/      # 4K по темам — качает install → fetch-wallpapers.sh
├── scripts/         # theme-switch, vpn, ai_assistant, nvidia-modeset…
├── config/          # hypr, waybar, rofi, kitty, dunst, sing-box…
├── home/            # .zshrc, .gitconfig
├── docker/open-webui/
├── systemd/user/
└── tests/
```

Тяжёлые данные — на **`DATA_ROOT`** (по умолчанию `/mnt/data`): docker, ollama, media, ComfyUI. SSD дома — код и доки. Подробности: [INSTALL.md](INSTALL.md#фаза-3--первый-вход-и-первостипенные-вещи).

---

## Network

Не включайте всё сразу — будет двойной NAT/DNS.

| Режим | zapret | sing-box / vpn | Tailscale |
|-------|--------|----------------|-----------|
| **Домашний RU-обход** (дефолт) | ON | OFF | mesh OK, без Exit Node |
| **VPS-прокси** | лучше OFF | `vpn start` | mesh OK |
| **NekoBox** | — | не параллельно с `vpn.sh` | — |

После install: zapret ON, VPN OFF; `tailscale up` — вручную.

---

## Tests

```bash
./tests/run.sh
```

CI: [`.github/workflows/test.yml`](.github/workflows/test.yml). На Windows — Git Bash или WSL.

---

## Docs

| Документ | Содержание |
|----------|------------|
| [INSTALL.md](INSTALL.md) | От USB до ready: фазы 0–8, NVIDIA, DATA_ROOT |
| [wallpapers/SOURCES.md](wallpapers/SOURCES.md) | URL / авторы / лицензии обоев |
| [.env.example](.env.example) | DATA_ROOT, Ollama, VPN, API keys |

---

## Вручную после install

`install.sh` не делает за вас: ISO и разметку дисков, пароли, секреты в `.env`, `tailscale up`, pairing Sunshine, импорт VPN-подписки, первый `ollama pull`. Полный список — в [INSTALL.md](INSTALL.md#что-нужно-сделать-вам).
