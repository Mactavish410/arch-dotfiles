# INSTALL — EndeavourOS от флешки до ready

Полный гайд на русском. Команды — как есть. Чеклисты помечены `[ ]`.

Краткая витрина: [README.md](README.md).

---

## Что нужно сделать вам

Без этих шагов система не станет «полностью вашей»:

1. Скачать ISO EndeavourOS, записать флешку, BIOS, пройти калиму — физический доступ к ПК.
2. Разметка: какой SSD под `/`, какой диск → `/mnt/data` (UUID в fstab).
3. Hostname, пароль пользователя, таймзона при установке EOS.
4. Секреты в `.env`: `OPENAI_API_KEY`, `VPN_UUID` / порт / SNI; при необходимости сменить `DATA_ROOT` (дефолт `/mnt/data`).
5. После первого Hyprland: сверить имена мониторов (`hyprctl monitors`) — если не DP-1 / DP-2 / HDMI-A-1, поправить `monitors.conf`.
6. `tailscale up` — логин в браузере.
7. Sunshine: пароль UI + pair PIN с телефоном (Moonlight).
8. NekoBox / VPN: рабочая подписка или VLESS Reality с VPS (в репо только шаблон).
9. Wi‑Fi пароль; аккаунты Cursor / Firefox sync; Git remote URL (если ещё нет).
10. Режим сети на каждый день: дефолт (zapret) или сразу VPS-VPN.
11. Бэкап секретов вне git (менеджер паролей).
12. Первый `ollama pull` большой модели — подтвердить имя (дефолт `qwen2.5-coder:7b`) и место на DATA_ROOT.
13. Скриншоты риса для README — когда сессия живая.

---

## Фаза 0 — подготовка на другой машине

Windows ок.

### Чеклист

- [ ] Скачан **EndeavourOS** ISO с [официального сайта](https://endeavouros.com/); проверен SHA256.
- [ ] Флешка ≥ 8 ГБ.
- [ ] На флешку / облако / телефон: URL git remote **или** копия репо; заметки Wi‑Fi, UUID VPN, Tailscale, OpenAI key (**не** в git).
- [ ] Записана схема дисков: SSD → `/` (+ ESP); большой диск → позже `/mnt/data`.

### Запись флешки

**Windows:** Ventoy (удобно) или Rufus в режиме DD.

**Linux:**

```bash
sudo dd if=EndeavourOS-….iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Подставьте свой `/dev/sdX` (`lsblk`). Не перепутайте диск.

---

## Фаза 1 — BIOS / UEFI

- [ ] Boot menu → **UEFI**-флешка (не Legacy).
- [ ] **Secure Boot: Off** (иначе боль с `nvidia-dkms` / подписью модулей).
- [ ] CSM / Legacy Off при чистом UEFI.
- [ ] Above 4G / Resizable BAR — по желанию (на desktop NVIDIA обычно ок).
- [ ] Hybrid GPU: prefer discrete / отключить iGPU, если мешает (на чистом desktop часто N/A).

---

## Фаза 2 — установка EndeavourOS

1. Загрузка live → Wi‑Fi или Ethernet.
2. Калима / Installer:
   - раскладка **English (US)** на время установки (RU позже в Hyprland через Alt+Shift);
   - ваша таймзона;
   - разметка: ESP 512M–1G fat32 `boot`, root btrfs или ext4;
   - **большой диск** — не форматировать, если на нём данные; либо сразу раздел под `/mnt/data`.
3. Окружение: **Online install → No Desktop** (рекомендуется) или минимальный XFCE как страховка на первый вход. Дальше только Hyprland из этого репо.
4. Пользователь + пароль + sudo; hostname.
5. Дождаться конца → reboot → вынуть флешку.

### Чеклист

- [ ] Система ставится на SSD (`/`).
- [ ] DATA-диск не стёрт случайно.
- [ ] Первый reboot успешен (TTY или запасной DE).

---

## Фаза 3 — первый вход и «первостипенные» вещи

Пока нет полного rice — консоль или временный DE.

### 3.1 Сеть и обновление

```bash
# TTY: Ctrl+Alt+F2 при необходимости
nmcli device wifi connect "SSID" password "…"   # или nmtui / Ethernet

sudo pacman -Sy archlinux-keyring
sudo pacman -Syu
```

### 3.2 Обязательно до `install.sh`

```bash
sudo pacman -S --needed base-devel git curl wget networkmanager
sudo systemctl enable --now NetworkManager
```

Без `git` + `base-devel` скрипт не взлетит. `yay` может поставить сам `install.sh`, но эти пакеты уже должны быть.

Опционально заранее:

```bash
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay && makepkg -si
```

### 3.3 NVIDIA modeset (сделать рано, если есть NVIDIA)

Иначе после перехода на Hyprland часто чёрный экран.

1. Добавить в параметры ядра: `nvidia_drm.modeset=1`
   - GRUB: `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT=… nvidia_drm.modeset=1`, затем `sudo grub-mkconfig -o /boot/grub/grub.cfg`
   - systemd-boot: в loader entry добавить тот же параметр
2. Убедиться, что в mkinitcpio есть нужные hooks для NVIDIA (см. Arch Wiki / скрипт `scripts/nvidia-modeset.sh` после клона репо).
3. `sudo mkinitcpio -P` → reboot.

После клона репо можно прогнать:

```bash
~/dotfiles/scripts/nvidia-modeset.sh
```

### 3.4 Смонтировать DATA_ROOT

По умолчанию `DATA_ROOT=/mnt/data`.

```bash
sudo mkdir -p /mnt/data
# найти UUID:
sudo blkid
# добавить в /etc/fstab, например:
# UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  /mnt/data  ext4  defaults,nofail  0  2
sudo mount /mnt/data
sudo chown "$USER:$USER" /mnt/data
```

Ожидаемое дерево после `install.sh` (создаст каталоги):

```
/mnt/data/
├── docker/          # образы, volumes, cache
├── ollama/          # веса моделей
├── media/
│   ├── movies/
│   ├── series/
│   └── torrents/
├── ai/
│   ├── comfyui/
│   └── datasets/
└── backups/
```

### Чеклист фазы 3

- [ ] Интернет работает.
- [ ] `git`, `base-devel` установлены.
- [ ] `/mnt/data` смонтирован и принадлежит вашему пользователю.
- [ ] NVIDIA modeset прописан (если GPU NVIDIA).

---

## Фаза 4 — получение dotfiles

```bash
git clone https://github.com/Mactavish410/arch-dotfiles.git ~/dotfiles
cd ~/dotfiles
cp .env.example .env
```

Отредактируйте `.env` минимум:

| Переменная | Назначение |
|------------|------------|
| `DATA_ROOT` | корень данных (`/mnt/data`) |
| `DOCKER_DATA_ROOT` | обычно `$DATA_ROOT/docker` |
| `OLLAMA_MODELS` | обычно `$DATA_ROOT/ollama` |
| `OLLAMA_MODEL` | дефолт `qwen2.5-coder:7b` |
| `OPENAI_API_KEY` | опционально |
| `VPN_UUID` / `VPN_PORT` / `VPN_SNI` / `VPS_IP` | для sing-box |

Альтернатива без remote: `cp -a /media/…/dotfiles ~/dotfiles`.

Опционально до install:

```bash
./tests/run.sh
```

### Чеклист

- [ ] Репозиторий в `~/dotfiles`.
- [ ] `.env` заполнен; секреты не попадут в git (`.env` в `.gitignore`).

---

## Фаза 5 — автоматическая установка

```bash
cd ~/dotfiles
chmod +x install.sh track.sh scripts/*.sh bin/* 2>/dev/null || true
./install.sh
```

Скрипт (кратко): копирует `.env` при отсутствии; ставит yay при необходимости; `pacman`/`yay` из pkglist; симлинки `config/` → `~/.config`, `home/` → `$HOME`; docker data-root + ollama override; bluetooth, NM, sshd, tailscaled; zapret ON / VPN OFF; home dirs; wallpapers; `theme-switch apply cyberpunk`; чеклист remote.

После скрипта:

- [ ] **Выйти из сессии / reboot** (группа `docker`, модули NVIDIA).

---

## Фаза 6 — вход в Hyprland

1. **SDDM** (ставится из pkglist): выбрать сессию `hyprland` и войти.  
   Для быстрого теста из TTY: `exec Hyprland` (после reboot предпочтительнее SDDM).
2. Мониторы:

   ```bash
   hyprctl monitors
   ```

   Если имена не `DP-1` / `DP-2` / `HDMI-A-1` — править `~/.config/hypr/monitors.conf` (оригинал в репо: `config/hypr/`; рядом `monitors.conf.example`).
3. Проверки:
   - [ ] Alt+Shift — US ↔ RU
   - [ ] Super+Return — kitty
   - [ ] Super+D — rofi
   - [ ] Super+T — список тем

---

## Фаза 7 — пост-настройка (до «готово»)

### Сеть (правило конфликтов)

- [ ] Zapret **или** full-tunnel VPN — не оба сразу
- [ ] NekoBox: импорт подписки в GUI (не параллельно с `scripts/vpn.sh`)
- [ ] VPN: заполнить `.env` → `vpn start` → проверить IP
- [ ] Tailscale: `sudo tailscale up` → логин в браузере (без Exit Node, пока не разберётесь)
- [ ] SSH: свой ключ; при желании позже отключить password auth (на bootstrap пароль не ломаем)

### Remote

- [ ] Sunshine: UI → пароль → pair PIN
- [ ] Moonlight на телефоне по Tailscale IP
- [ ] KDE Connect pair

Типичные ограничения Moonlight: стримится обычно один монитор; тайлинг пальцем неудобен; нужна активная графическая сессия; LTE+DERP = лаги; параллельно тяжёлый Ollama может упереться в VRAM.

### AI

- [ ] `ollama pull qwen2.5-coder:7b` (или ваша модель), если install не тянул из‑за размера
- [ ] `docker compose -f docker/open-webui/docker-compose.yml up -d`
- [ ] `python -m venv .venv && .venv/bin/pip install -r scripts/requirements-ai.txt`
- [ ] Микрофон в pavucontrol

### Красота / UX

- [ ] Обои: `wallpapers/cyberpunk/wallpaper.jpg` есть (качает `install.sh` → `fetch-wallpapers.sh`)
- [ ] Super+T / `theme-switch apply …`
- [ ] nwg-look: GTK + Papirus
- [ ] Blueman: наушники

### Данные

- [ ] qBittorrent save path → `$DATA_ROOT/media/torrents`
- [ ] `~/Documents`, `~/Projects/{work,personal}` на месте
- [ ] Cursor: войти в аккаунт

### Проверка «система готова»

- [ ] Reboot → Hyprland сам (SDDM)
- [ ] Интернет + браузер + screen share (portal) в тестовом звонке
- [ ] `nvidia-smi`, `nvtop`
- [ ] `docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi`
- [ ] `curl -s localhost:11434` (Ollama)
- [ ] Lock Super+L; screenshot Super+Shift+S

---

## Фаза 8 — повседневная эксплуатация

### Обновления

```bash
sudo pacman -Syu
yay -Syu
# после обновления ядра (nvidia-dkms) — reboot
```

### Новые конфиги в git

```bash
./track.sh ~/.config/foo
```

Скрипт перенесёт путь в `~/dotfiles/config/`, сделает симлинк обратно и обновит pkglist.

### Сеть каждый день

| Цель | Действие |
|------|----------|
| Домашний обход DPI | zapret ON, `vpn stop` |
| Нужен VPS | `vpn start`, zapret лучше OFF |
| Mesh SSH / Moonlight | Tailscale без Exit Node |

**Не** включать одновременно: zapret + global sing-box + Tailscale Exit Node.

### Безопасность

- Бэкап `.env` и VPN UUID вне git.
- ufw: default deny incoming; разрешены OpenSSH, Tailscale (`tailscale0`), порты Sunshine `47984–48010` tcp/udp (настраивает install).
- hypridle: lock 5 мин → DPMS 10 мин; **suspend выключен** (нужен удалённый доступ).

### Firewall (справочно)

После install ожидается:

- default deny incoming
- allow OpenSSH
- allow на интерфейсе Tailscale
- Sunshine: 47984–48010/tcp+udp

---

## Справка: переменные `.env`

См. [.env.example](.env.example). Ключевые:

```
DATA_ROOT="/mnt/data"
DOCKER_DATA_ROOT="/mnt/data/docker"
OLLAMA_MODELS="/mnt/data/ollama"
LINK_VIDEOS_TO_DATA="0"   # 1 → symlink ~/Videos → media/movies
```

---

## Справка: тесты локально

```bash
cd ~/dotfiles
./tests/run.sh
```

На Windows-машине разработки: Git Bash / WSL. CI крутит то же на Ubuntu.

---

## Если что-то пошло не так

| Симптом | Что проверить |
|---------|----------------|
| `не найдена цель: …` | пакет не в official — в AUR или переименован. `./scripts/validate-pkglists.sh` |
| Конфликт `nvidia-open*` / `nvidia-dkms` | EOS уже поставил open-драйвер; `nvidia-dkms` в pkglist не кладём |
| Чёрный экран Hyprland | `nvidia_drm.modeset=1`, mkinitcpio, TTY Ctrl+Alt+F2 |
| Нет интернета после VPN | выключить один из слоёв (zapret / sing-box / exit node) |
| Нет шаринга экрана | portal-hyprland + portal-gtk + PipeWire |
| Docker забил корневой SSD | `daemon.json` → `data-root` на `$DOCKER_DATA_ROOT` |
| Ollama на маленьком диске | drop-in `OLLAMA_MODELS` |

### Политика пакетов

- `pkglist.txt` — **только** official (`pacman -Si` / группа в sync DB).
- `pkglist_aur.txt` — только AUR (`yay -Si`).
- Перед `./install.sh` на EOS гоняется `scripts/validate-pkglists.sh` через pacman (строго). На Windows/CI — API, сеть может WARN.
- NVIDIA: если уже есть `nvidia-open` / `nvidia-open-dkms`, новые драйверы не ставятся.
- Обои / сбои отдельных AUR-пакетов не валят весь install; битые **имена** в списках валят preflight на EOS.

Удачи в Night City.