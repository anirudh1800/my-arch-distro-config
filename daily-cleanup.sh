#!/bin/bash
#
# daily-cleanup.sh
# Cleans pacman, yay/AUR, flatpak (+ per-app caches), Podman (rootless),
# orphan packages, journal logs, and trash.
# Designed to run daily via systemd timer or cron.
#
# Logs output to /var/log/daily-cleanup.log

set -uo pipefail

LOG="/var/log/daily-cleanup.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# Real user (needed when run as root via cron/systemd, so we can reach ~/.cache etc.)
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

log() {
    echo "[$TIMESTAMP] $*" | tee -a "$LOG"
}

require_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run as root (it uses pacman/journalctl)." >&2
        echo "Run with: sudo $0" >&2
        exit 1
    fi
}

require_root

log "===== Starting daily cleanup ====="

# --- Pacman package cache: keep last 2 versions ---
if command -v paccache &>/dev/null; then
    log "--- Pacman cache (paccache) ---"
    paccache -rk2 2>&1 | tee -a "$LOG"
    paccache -ruk0 2>&1 | tee -a "$LOG"   # remove uninstalled packages from cache
else
    log "paccache not found, falling back to pacman -Sc"
    pacman -Sc --noconfirm 2>&1 | tee -a "$LOG"
fi

# --- Orphaned packages ---
log "--- Orphaned packages ---"
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [ -n "$orphans" ]; then
    echo "$orphans" | tee -a "$LOG"
    pacman -Rns $orphans --noconfirm 2>&1 | tee -a "$LOG"
else
    log "No orphaned packages found."
fi

# --- Yay / AUR build cache ---
# We clean the cache directory directly instead of calling `yay -Sc`.
# yay refuses to run as root and would otherwise drop to the user via
# sudo -u, which triggers an interactive password prompt for the pacman
# part of the cleanup — that hangs/fails under systemd/cron (no TTY).
# Pacman's own cache is already handled above via paccache, so this is safe.
YAY_CACHE="$REAL_HOME/.cache/yay"
if [ -d "$YAY_CACHE" ]; then
    log "--- Yay/AUR build cache ---"
    BEFORE=$(du -sh "$YAY_CACHE" 2>/dev/null | cut -f1)
    rm -rf "${YAY_CACHE:?}"/*
    log "Cleared $YAY_CACHE (was $BEFORE)"
fi

# --- Flatpak ---
if command -v flatpak &>/dev/null; then
    log "--- Flatpak unused runtimes/apps ---"
    flatpak uninstall --unused --delete-data -y 2>&1 | tee -a "$LOG"
    flatpak repair 2>&1 | tee -a "$LOG"
fi

# --- Flatpak per-app caches ---
# Each Flatpak app stores its cache under ~/.var/app/<APP_ID>/cache/.
# Safe to clear: this only removes cache/, not config/ or data/, so
# logins, settings, and saved state are untouched.
FLATPAK_APP_DIR="$REAL_HOME/.var/app"
if [ -d "$FLATPAK_APP_DIR" ]; then
    log "--- Flatpak per-app caches ---"
    for cache_dir in "$FLATPAK_APP_DIR"/*/cache; do
        [ -d "$cache_dir" ] || continue
        rm -rf "${cache_dir:?}"/*
    done
    log "Cleared Flatpak app caches under $FLATPAK_APP_DIR"
fi

# --- Podman cleanup (rootless) ---
# Most desktop Podman setups run rootless under your own user, so the
# script (running as root via systemd/sudo) has to explicitly target
# your user's containers/images, not root's. XDG_RUNTIME_DIR is set
# so rootless podman can find your user's runtime socket.
if command -v podman &>/dev/null; then
    log "--- Podman cleanup (user: $REAL_USER) ---"
    REAL_UID="$(id -u "$REAL_USER")"
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" podman system df 2>&1 | tee -a "$LOG"
    # Removes: stopped containers, unused networks, dangling images, unused build cache.
    # Does NOT remove images still tagged/used by an existing container, or volumes.
    sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$REAL_UID" podman system prune -f 2>&1 | tee -a "$LOG"

    # If you also use podman rootful (sudo podman ...), uncomment below:
    # podman system prune -f 2>&1 | tee -a "$LOG"
fi


log "--- Journal logs (vacuum to 2 weeks) ---"
journalctl --vacuum-time=2weeks 2>&1 | tee -a "$LOG"

# --- Trash ---
if [ -d "$REAL_HOME/.local/share/Trash" ]; then
    log "--- Emptying user trash ---"
    rm -rf "${REAL_HOME:?}/.local/share/Trash/"* 2>&1 | tee -a "$LOG"
fi

log "===== Cleanup finished ====="
log ""
