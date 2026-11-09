# Hyprland + Quickshell Dotfiles

My personal Linux desktop, running Hyprland on CachyOS with a fully custom shell built with [Quickshell](https://quickshell.outfoxxed.me/); bar, OSD, app launcher, clipboard manager, lockscreen, quick settings, and notification center are all native Quickshell/QML, not a patchwork of separate daemons. The entire color scheme is generated live from the current wallpaper via `wallust` and propagated through the shell and (on desktop) synced to RGB peripherals via `openrgb`.

## 🚀 Key Features

- **Custom Quickshell shell** — a single coordinated shell replacing the usual bar/launcher/notification-daemon/lockscreen stack:
  - **Bar** — three-pill layout with interactive modules (workspaces, media player, system monitor, clock, audio, backlight, network, bluetooth, battery, tray, notifications) — nearly every module opens its own popup rather than being a static readout
  - **OSD** — custom on-screen display for volume and brightness
  - **Launcher** — native app launcher
  - **Clipboard manager** — Quickshell frontend over `cliphist`
  - **Quick settings** — Control-Center-style tile grid (Wi-Fi, Bluetooth, airplane mode, night light, DND, keep-awake) with volume/brightness sliders, and tiles that expand in place into full network/bluetooth/temperature panes
  - **Notification center** — SwayNC-inspired, built natively in Quickshell (toast + history/center view), with a critical-priority toast queue so error notifications can't be buried by chatty ones
  - **Lockscreen** — native Quickshell lock screen with PAM password _and_ fingerprint auth running in parallel
  - **Wallpaper picker** — see below; considerably more than a wallpaper list
  - **Calendar** — month view with Google Calendar events, quick-add via natural language, and current weather from open-meteo
  - **System monitor** — per-core CPU, memory, GPU, sensors, disks, network throughput and a process list with real instantaneous CPU usage
  - **Fallback TUIs** — the network and bluetooth modules can drop into `nmtui` / `bluetui` for anything the custom UI doesn't cover
- **Automated theming** — `wallust` generates colors from the active wallpaper and feeds them into the Quickshell theme, Hyprland, Alacritty, btop, cava, and GTK
- **Theme presets** — five wallust color-generation moods (vibrant, muted, pastel, dark, mono). The picker generates live preview swatches for every preset against the selected wallpaper in parallel, caches them by wallpaper+preset mtime, and remembers which preset you last used per wallpaper
- **Video wallpapers** — `.mp4`/`.webm`/`.mkv`/`.mov` are supported alongside stills. `awww` shows an extracted frame during the transition, then `mpvpaper` takes over the layer. Playback pauses automatically on battery and resumes on AC
- **Power-aware effects** — blur and video wallpaper are disabled on battery and restored on AC, driven from UPower. Shell surfaces compensate with slightly higher opacity so translucency doesn't look flat without blur
- **Dual-machine ready** — install.sh detects machine type from battery presence (no battery → desktop profile, battery found → laptop profile) and detects GPU vendor (Nvidia/Intel/AMD) independently, installing the correct driver package set for whichever GPU is actually present regardless of machine type
  - **Desktop:** GPU drivers + `openrgb` for RGB sync
  - **Laptop:** GPU drivers, `tlp`/`tlp-rdw`/`tlp-pd` for battery/profile management, `fprintd` for fingerprint unlock
  - The Hyprland config also branches at runtime (`hypr/lua/machine.lua`): gaps, rounding, blur, VRR, animation speeds, touchpad gestures and GPU env vars all differ per machine from the same repo
- **Fish shell** as default, launched into Hyprland via `uwsm`

## 📦 Software & Dependencies

- **Window Manager:** `hyprland`
- **Shell (bar/OSD/launcher/clipboard/lockscreen/notifications):** `quickshell-git`
- **Wallpaper daemon:** `awww` (+ `mpvpaper` for video wallpapers)
- **Theming:** `wallust`
- **Terminal:** `alacritty`
- **File Manager:** `thunar` (GUI), `yazi` (TUI)
- **Shell:** `fish`
- **Media/imaging:** `ffmpeg`, `imagemagick` (thumbnails and video frame extraction)
- **Misc CLI:** `jq`, `cliphist`, `playerctl`, `brightnessctl`, `hyprsunset`, `pavucontrol`
- **Fonts:** Departure Mono, Symbols Nerd Font
- **RGB (desktop only):** `openrgb`
- **Power management (laptop only):** `tlp`, `tlp-rdw`, `tlp-pd`

Full package lists live in [`pkglist_native.txt`](./pkglist_native.txt) and [`pkglist_aur.txt`](./pkglist_aur.txt).

## 🛠️ Installation

```bash
git clone https://github.com/aliaricode/dotfiles.git
cd dotfiles
./install.sh
```

The script will:

1. Check for an internet connection and install `paru`/`stow`/base tools
2. Install packages from `pkglist_native.txt` (pacman) and `pkglist_aur.txt` (paru)
3. Detect your GPU and install the appropriate desktop/laptop extras
4. Stow all config directories into `~/.config` (existing files that would conflict are moved to `*.bak`)
5. Set `fish` as your default shell (the `uwsm` autostart for Hyprland lives in `config.fish`) and enable the `hyprpolkitagent` user service
6. Ask whether to reboot

To change your theme, just pick a new wallpaper through the Quickshell wallpaper picker — `wallust` handles the rest automatically.

### Calendar setup (optional)

The calendar popup works out of the box for weather and the month view. Google Calendar events need credentials that can't be shipped in a repo:

1. Create an OAuth client (Desktop app) in the Google Cloud console
2. Save it as `~/.local/share/quickshell/secrets/credentials.json`
3. Run once, by hand: `python3 ~/.config/quickshell/scripts/calendar-auth.py`

That writes `token.json` next to it, which the shell then refreshes silently. Secrets live outside the repo (the Spotify player's `spotify_credentials.json`/`spotify_token.json` too), so they can't be committed by accident. Without them the calendar simply shows no events — nothing else is affected.

## 📁 Structure

```
.config/
├── hypr/
│   ├── lua/            # Hyprland config (Lua): keybinds, theme, windowrules, per-machine profiles
│   └── scripts/        # blur toggling, gamemode, monitor toggles
├── quickshell/
│   ├── bar/            # the shell proper (see below)
│   ├── lockscreen/     # separate Quickshell instance; shares theme + services via symlinks
│   └── scripts/        # wallust pipeline, wallpaper/thumbnail generation, calendar backend
├── wallust/
│   ├── templates/      # theme templates for every themed app
│   └── presets/        # the five color-generation moods
├── fish/, alacritty/, btop/, cava/, nvim/, yazi/, Thunar/, gtk-3.0/, gtk-4.0/
```

### Shell layout

`quickshell/bar/` is organised by role rather than by feature:

```
bar/
├── shell.qml           # entry point; defines the QML module root
├── Bar.qml             # the bar window itself (one per monitor via Variants)
├── Theme.qml           # colors, read from theme.json (regenerated by wallust)
├── services/           # singletons: state and side effects, no UI
├── components/         # reusable building blocks: popup bases, sliders, pills, tiles
├── windows/            # top-level windows: launcher, clipboard, wallpaper picker, quick settings, OSD
├── widgets/            # bar modules
└── popups/             # each widget's expanded view
```

A few conventions worth knowing before editing:

- **`services/` splits observation from action.** `PowerState` only reports AC/battery state; `PowerActions` is what actually spawns scripts in response. This matters because the lockscreen runs as a _separate Quickshell process_ and mirrors some services via symlink — anything with side effects must not be shared, or both processes would fire it.
- **`lockscreen/services/` contains symlinks into `bar/services/`**, and the directory name must match so `import qs.services` resolves identically in both processes. Renaming it breaks the lockscreen at load time, not at runtime.
- **`Theme.qml` and `theme.json` stay at the bar root.** `post-apply.sh` writes to that path, the wallust template targets it, and the lockscreen symlinks both. Moving them breaks all three.
- **The lockscreen is deliberately a second process.** A crash in the bar or a `hyprctl reload` during a theme change — must not be able to take down or unlock the lock screen.

## Notes

- `hypr/old_config/` in this repo is a legacy config kept for reference and is not stowed by `install.sh`.
- `openrgb` is only installed automatically on machines with an Nvidia GPU (treated as "desktop" by the install script's hardware detection).
- Wallpapers live in `~/Pictures/wallpapers/<category>/`, one level of subfolders deep — the picker uses the folder name as the category filter.
- Generated caches (thumbnails, stills, preset previews) live under `~/.cache/quickshell/` and are safe to delete; they regenerate on next scan.
