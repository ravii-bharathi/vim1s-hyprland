#!/usr/bin/env bash
# nested.sh — run the session NESTED (as a window) inside your GNOME Wayland session.
#
#   dev/nested.sh hyprland     # or: sway
#
# Run inside the vim1s-dev distrobox (make nested-hypr / make nested-sway).
# Uses the configs straight from this checkout: nothing is installed or symlinked.
#
# Board-likeness knobs set here:
#   MESA_GLES_VERSION_OVERRIDE=3.1  Panfrost on Mali-G31 tops out at GLES 3.1, so Hyprland's
#                                   "GLES 3.2 failed, retrying 3.0" path is exercised here too.
#   VIM1S_NESTED=1                  configs pick a fixed 1280x720 window instead of 1080p
#   VIM1S_REPO=<checkout>           vim1s-shell loads waybar/mako/foot configs from the repo
#
# Inside the nested window: SUPER is usually grabbed by GNOME; click into the window first.
# Quit with SUPER+SHIFT+E, or close the window.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

which_wm=${1:-}
[[ -n ${WAYLAND_DISPLAY:-} ]] || die "WAYLAND_DISPLAY not set: run this from a Wayland session (GNOME on Wayland), inside distrobox"

export VIM1S_NESTED=1
export VIM1S_REPO=$VIM1S_ROOT
export PATH="$VIM1S_ROOT/bin:$PATH"
export MESA_GLES_VERSION_OVERRIDE=${MESA_GLES_VERSION_OVERRIDE:-3.1}

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/vim1s"
mkdir -p "$state_dir"

case $which_wm in
    hyprland | hypr)
        command -v Hyprland >/dev/null || die "Hyprland not found (are you inside the vim1s-dev box?)"
        info "Hyprland $(Hyprland --version 2>/dev/null | head -n1) nested; log: $state_dir/nested-hyprland.log"
        # Direct binary instead of start-hyprland: a crash should end the test, not restart in safe mode.
        Hyprland -c "$VIM1S_ROOT/hypr/hyprland.lua" 2>&1 | tee "$state_dir/nested-hyprland.log"
        ;;
    sway)
        command -v sway >/dev/null || die "sway not found (are you inside the vim1s-dev box?)"
        info "sway $(sway --version 2>/dev/null) nested; log: $state_dir/nested-sway.log"
        sway -c "$VIM1S_ROOT/sway/config" 2>&1 | tee "$state_dir/nested-sway.log"
        ;;
    *)
        die "usage: dev/nested.sh hyprland|sway"
        ;;
esac
