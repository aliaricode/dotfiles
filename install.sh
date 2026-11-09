#!/bin/bash

set -e

echo ":: INITIALIZING INSTALL SCRIPT ::"

# --- 0. SANITY ---
if [ "$EUID" -eq 0 ]; then
  echo "!! Do not run this as root. It uses sudo where needed."
  echo "!! Running as root would chsh root and stow into /root/.config."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# --- ERROR TRAP ---
LAST_STEP="startup"
on_error() {
  local code=$?
  echo
  echo "!! SCRIPT FAILED during: $LAST_STEP"
  echo "!! Exit code: $code"
  echo "!! Diagnostic state:"
  echo "     sddm active:   $(systemctl is-active sddm 2>/dev/null || echo 'not found/inactive')"
  echo "     fish shell:    $(command -v fish >/dev/null && echo 'installed' || echo 'missing')"
  echo "     config.fish:   $([ -f "$HOME/.config/fish/config.fish" ] && echo 'exists' || echo 'missing')"
  echo "     uwsm autostart present: $(grep -qs 'uwsm start' "$HOME/.config/fish/config.fish" && echo 'yes' || echo 'no')"
  echo
  echo "!! Steps completed before this point (package installs, service enables,"
  echo "!! stowed configs) have already been applied and were NOT rolled back."
  echo "!! All steps are idempotent -- fix the issue above and re-run."
}
trap on_error ERR

# --- 1. INTERNET CHECK ---
LAST_STEP="internet check"
echo ":: Checking Internet Connection..."
# HTTP rather than ping: some networks block ICMP
if ! curl -fsS --max-time 10 -o /dev/null https://archlinux.org; then
  echo "!! ERROR: No Internet Connection. Connect via nmtui first."
  exit 1
fi
echo "   -> Internet is OK."

# --- 2. PACKAGE LISTS ---
LAST_STEP="reading package lists"
for f in pkglist_native.txt pkglist_aur.txt; do
  if [ ! -f "$SCRIPT_DIR/$f" ]; then
    echo "!! ERROR: $f not found in $SCRIPT_DIR"
    exit 1
  fi
done

mapfile -t common_pkgs < <(grep -v '^\s*#' "$SCRIPT_DIR/pkglist_native.txt" | grep -v '^\s*$')
mapfile -t aur_pkgs < <(grep -v '^\s*#' "$SCRIPT_DIR/pkglist_aur.txt" | grep -v '^\s*$')

if [ "${#common_pkgs[@]}" -eq 0 ]; then
  echo "!! ERROR: pkglist_native.txt produced no packages."
  exit 1
fi

# --- 3. FULL SYSTEM UPDATE (must happen before installing anything) ---
LAST_STEP="full system update"
echo ":: Updating full system (required before installing new packages)..."
sudo pacman -Syu --noconfirm

# --- 4. PREPARATION (Paru & Base) ---
LAST_STEP="installing base tools"
echo ":: Installing Base Tools (Paru, Git)..."
sudo pacman -S --needed --noconfirm base-devel git paru stow

# --- 5. HARDWARE DETECTION ---
LAST_STEP="hardware detection"
echo ":: Detecting Hardware..."

IS_LAPTOP=false
if [ -n "$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' -print -quit 2>/dev/null)" ]; then
  IS_LAPTOP=true
fi

HAS_NVIDIA=false
if lspci | grep -i "NVIDIA" >/dev/null; then
  HAS_NVIDIA=true
fi

HAS_INTEL_GPU=false
if lspci | grep -iE "VGA|3D|Display" | grep -i "Intel" >/dev/null; then
  HAS_INTEL_GPU=true
fi

HAS_AMD_GPU=false
if lspci | grep -iE "VGA|3D|Display" | grep -iE "AMD|ATI|Radeon" >/dev/null; then
  HAS_AMD_GPU=true
fi

if [ "$HAS_NVIDIA" = true ]; then
  echo "   -> Nvidia GPU detected."
  common_pkgs+=("nvidia-open-dkms" "nvidia-utils" "lib32-nvidia-utils" "nvidia-settings")
fi

if [ "$HAS_INTEL_GPU" = true ]; then
  echo "   -> Intel GPU detected."
  common_pkgs+=("vulkan-intel" "intel-media-driver" "libva-intel-driver")
fi

if [ "$HAS_AMD_GPU" = true ]; then
  echo "   -> AMD GPU detected."
  common_pkgs+=("mesa" "lib32-mesa" "vulkan-radeon" "lib32-vulkan-radeon" "libva-mesa-driver")
fi

if [ "$IS_LAPTOP" = true ]; then
  echo "   -> Battery present. Treating as Laptop..."
  common_pkgs+=("thermald" "tlp" "tlp-rdw" "tlp-pd" "fprintd")
else
  echo "   -> No battery. Treating as Desktop..."
  common_pkgs+=("openrgb")
fi

if grep -q "GenuineIntel" /proc/cpuinfo; then
  common_pkgs+=("intel-ucode")
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
  common_pkgs+=("amd-ucode")
fi

# --- 6. INSTALLATION ---
LAST_STEP="installing repository packages"
echo ":: Installing Repository Packages..."
sudo pacman -S --needed --noconfirm "${common_pkgs[@]}"

LAST_STEP="installing AUR packages"
echo ":: Installing AUR Packages..."
if [ "${#aur_pkgs[@]}" -gt 0 ]; then
  paru -S --needed --noconfirm "${aur_pkgs[@]}"
else
  echo "   -> No AUR packages listed, skipping."
fi

# --- 7. CONFIGURING SERVICES ---
LAST_STEP="enabling services"
echo ":: Enabling Services..."
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
# Polkit agent for the Hyprland session (started with graphical-session.target)
systemctl --user enable hyprpolkitagent.service
# Spotify Connect device the Quickshell music player drives
systemctl --user enable spotifyd.service

if [ "$IS_LAPTOP" = true ]; then
  echo "   -> Enabling Laptop Battery Savers (TLP & Thermald)..."
  sudo systemctl enable --now tlp
  sudo systemctl enable --now thermald
  # PAM service the Quickshell lockscreen uses for fingerprint unlock (runs alongside the password prompt)
  if [ ! -f /etc/pam.d/quickshell-fprint ]; then
    echo "auth required pam_fprintd.so" | sudo tee /etc/pam.d/quickshell-fprint >/dev/null
  fi
  echo "   -> fprintd installed. Run 'fprintd-enroll' to register a fingerprint."
else
  echo "   -> openrgb installed. Color sync is handled by quickshell/scripts/update-rgb.sh."
fi

# --- 8. STOWING DOTFILES ---
# The repo itself is the stow package (non-config files are excluded by
# .stow-local-ignore), so ~/.config/<app> links into this checkout.
LAST_STEP="stowing dotfiles"
echo ":: Stowing Dotfiles..."

mkdir -p "$HOME/.config"

# Back up real files that would block stow, instead of aborting
conflicts=$(stow -n -R -d "$SCRIPT_DIR" -t "$HOME" . 2>&1 |
  sed -n 's/.*cannot stow .* over existing target \(.*\) since .*/\1/p')
while IFS= read -r target; do
  [ -z "$target" ] && continue
  echo "   -> Backing up existing ~/$target to ~/$target.bak"
  mv "$HOME/$target" "$HOME/$target.bak"
done <<<"$conflicts"

stow -R -d "$SCRIPT_DIR" -t "$HOME" .
echo "   -> Dotfiles stowed."

# --- 9. SHELL SETUP ---
LAST_STEP="setting default shell to fish"
echo ":: Final Touches..."

if command -v fish >/dev/null; then
  if ! grep -q "/usr/bin/fish" /etc/shells; then
    echo "   -> Adding /usr/bin/fish to /etc/shells..."
    echo "/usr/bin/fish" | sudo tee -a /etc/shells
  fi
  echo "   -> Changing default shell to Fish..."
  sudo chsh -s /usr/bin/fish "$USER"
fi

# --- 10. UWSM AUTOSTART ---
# The autostart block lives in the stowed config.fish -- verify it before touching sddm.
LAST_STEP="verifying autostart before touching sddm"
UWSM_CONF="$HOME/.config/fish/config.fish"
if ! grep -q "uwsm start" "$UWSM_CONF" 2>/dev/null; then
  echo "!! ERROR: UWSM autostart not found in $UWSM_CONF."
  echo "!! Refusing to disable SDDM -- you would be left with no way to log in."
  echo "!! Fix $UWSM_CONF manually, or re-run this script, before disabling SDDM yourself."
  exit 1
fi
echo "   -> UWSM autostart verified present."

# --- 11. DISABLE SDDM (only reached if autostart is confirmed working) ---
LAST_STEP="disabling sddm"
if systemctl is-active --quiet sddm; then
  echo "   -> UWSM autostart confirmed. Disabling SDDM (using UWSM from TTY)..."
  sudo systemctl disable --now sddm
else
  echo "   -> SDDM not active, nothing to disable."
fi

trap - ERR
echo ":: INSTALL COMPLETE!"
read -r -p ":: Reboot now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  sudo reboot
else
  echo ":: Reboot when ready to start Hyprland from TTY1."
fi
