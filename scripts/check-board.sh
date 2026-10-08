#!/usr/bin/env bash
# check-board.sh — read-only prerequisite check for vim1s-desktop on the VIM1S.
# Safe to run NOW over the serial console (no display or input needed); re-run after each BSP step.
#
#   ./scripts/check-board.sh            (from the repo on the board)
#   ssh alarm@<board> 'bash -s' < scripts/check-board.sh   (from the laptop, no checkout needed)
#
# Result per line: PASS | WARN (works but sub-optimal) | FAIL (blocks the desktop)
#                  PENDING (blocked by known in-progress BSP work: S4 KMS driver, S4 USB DT nodes)
# Exit status: 0 if no FAIL, 1 otherwise.
set -uo pipefail

if [[ -t 1 ]]; then
    _b=$'\033[1m' _r=$'\033[31m' _g=$'\033[32m' _y=$'\033[33m' _c=$'\033[36m' _n=$'\033[0m'
else
    _b='' _r='' _g='' _y='' _c='' _n=''
fi
fails=0 warns=0 pends=0
section() { printf '\n%s== %s%s\n' "$_b" "$*" "$_n"; }
ok()   { printf '  %sPASS%s    %s\n' "$_g" "$_n" "$*"; }
warn() { printf '  %sWARN%s    %s\n' "$_y" "$_n" "$*"; warns=$((warns + 1)); }
fail() { printf '  %sFAIL%s    %s\n' "$_r" "$_n" "$*"; fails=$((fails + 1)); }
pend() { printf '  %sPENDING%s %s\n' "$_c" "$_n" "$*"; pends=$((pends + 1)); }
note() { printf '          %s\n' "$*"; }
drv_of() { local d; d=$(readlink -f "$1/device/driver" 2>/dev/null) && basename "$d" || echo "?"; }

# ------------------------------------------------------------------------------------------
section "1. Platform"
arch=$(uname -m)
if [[ $arch == aarch64 ]]; then ok "arch aarch64"; else fail "arch is $arch, expected aarch64"; fi
ok "kernel $(uname -r)"
if [[ -r /proc/device-tree/model ]]; then
    ok "model: $(tr -d '\0' </proc/device-tree/model)"
fi
mem_mb=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo)
ok "RAM ${mem_mb} MiB"
if [[ $(wc -l </proc/swaps) -gt 1 ]]; then
    ok "swap/zram active: $(awk 'NR>1 {printf "%s(%s KiB) ", $1, $3}' /proc/swaps)"
else
    warn "no swap or zram: with 2 GB, a compressed zram swap gives headroom for the compositor + bar"
fi

# ------------------------------------------------------------------------------------------
section "2. GPU render node (Panfrost)"
render_ok=0
shopt -s nullglob
for n in /sys/class/drm/renderD*; do
    d=$(drv_of "$n")
    dev=/dev/dri/$(basename "$n")
    if [[ $d == panfrost ]]; then
        render_ok=1
        ok "$dev bound to panfrost"
        if [[ -r $dev && -w $dev ]]; then ok "$dev is read/writable by $(id -un)"; else
            warn "$dev not accessible by $(id -un) (perms: $(stat -c '%A %G' "$dev")); compositor would fall back to the card node"
        fi
    else
        note "$dev bound to $d"
    fi
done
[[ $render_ok == 1 ]] || fail "no renderD* node bound to panfrost — check the GPU DT node / panfrost probe in dmesg"
if klog=$( (dmesg 2>/dev/null || journalctl -k -b --no-pager 2>/dev/null) | grep -i panfrost | tail -n 3); [[ -n $klog ]]; then
    note "kernel log (last panfrost lines):"
    while IFS= read -r l; do note "  $l"; done <<<"$klog"
fi

# ------------------------------------------------------------------------------------------
section "3. Display (KMS)"
kms_drivers=()
for c in /sys/class/drm/card[0-9] /sys/class/drm/card[0-9][0-9]; do
    conns=("$c"-*)
    d=$(drv_of "$c")
    if [[ ${#conns[@]} -eq 0 ]]; then
        note "/dev/dri/$(basename "$c") ($d): no connectors — render-only (expected for panfrost)"
        continue
    fi
    kms_drivers+=("$d")
    ok "/dev/dri/$(basename "$c") ($d) is KMS-capable with ${#conns[@]} connector(s)"
    for k in "${conns[@]}"; do
        st=$(cat "$k/status" 2>/dev/null || echo "?")
        name=${k##*/}
        if [[ $st == connected ]]; then
            modes=$(tr '\n' ' ' <"$k/modes" 2>/dev/null)
            ok "$name connected; modes: ${modes:-none listed}"
            if grep -qx '1920x1080' "$k/modes" 2>/dev/null; then
                note "  policy -> 1920x1080@60 (if a 60 Hz variant exists; refresh is not listed in sysfs)"
            elif grep -qx '1280x720' "$k/modes" 2>/dev/null; then
                note "  policy -> 1280x720@60 fallback"
            else
                note "  policy -> monitor's preferred mode"
            fi
        else
            note "$name: $st"
        fi
    done
done
if [[ ${#kms_drivers[@]} -eq 0 ]]; then
    pend "no KMS-capable DRM device — expected until the S4 HDMI/VPU display driver is in your kernel"
fi

# ------------------------------------------------------------------------------------------
section "4. Mesa userspace"
if mver=$(pacman -Q mesa 2>/dev/null); then ok "$mver"; else fail "mesa not installed"; fi
# Locate the DRI driver directory from the package file list instead of assuming a path.
pf=$(pacman -Qlq mesa 2>/dev/null | grep -m1 '/panfrost_dri\.so$' || true)
if [[ -n $pf && -e $pf ]]; then
    dri=$(dirname "$pf")
    ok "$pf present"
else
    dri=/usr/lib/dri
    fail "no panfrost_dri.so in the mesa package — Mesa built without the panfrost Gallium driver?"
fi
for d in "${kms_drivers[@]}"; do
    [[ $d == panfrost ]] && continue
    if [[ -e $dri/${d}_dri.so ]]; then
        ok "$dri/${d}_dri.so present: Mesa's loader can pair KMS driver '$d' with panfrost (kmsro)"
    else
        warn "$dri/${d}_dri.so missing: Mesa may not know KMS driver '$d' -> GBM/EGL scanout via panfrost can fail"
        note "fix is a one-line kmsro entry in Mesa for '$d' (Mesa docs: Panfrost > kmsro)"
    fi
done

if command -v eglinfo >/dev/null 2>&1; then
    # Works WITHOUT a display: eglinfo also probes the surfaceless / device platforms on renderD*.
    eout=$(eglinfo 2>&1 || true)
    gles=$(grep -m1 -i 'OpenGL ES profile version' <<<"$eout" | sed 's/^[[:space:]]*//')
    rend=$(grep -m1 -iE 'OpenGL ES profile renderer|renderer string' <<<"$eout" | sed 's/^[[:space:]]*//')
    if [[ -n $gles ]]; then ok "$gles"; else warn "eglinfo printed no GLES version (no usable platform?)"; fi
    [[ -n $rend ]] && note "$rend"
    if grep -q 'GL_EXT_texture_format_BGRA8888' <<<"$eout"; then ok "GL_EXT_texture_format_BGRA8888 (Hyprland hard requirement)"
    else fail "GL_EXT_texture_format_BGRA8888 not seen (Hyprland aborts without it)"; fi
    if grep -qE 'EGL_KHR_platform_gbm|EGL_EXT_platform_device' <<<"$eout"; then ok "EGL GBM/device platform (Hyprland hard requirement)"
    else fail "neither EGL_KHR_platform_gbm nor EGL_EXT_platform_device seen (Hyprland aborts)"; fi
    for e in EGL_ANDROID_native_fence_sync EGL_EXT_image_dma_buf_import_modifiers; do
        if grep -q "$e" <<<"$eout"; then ok "$e"; else warn "$e not seen (Hyprland runs, but slower / no explicit sync)"; fi
    done
else
    warn "eglinfo not installed — run install.sh --with-debug (packages/debug.txt) to test GLES on the render node now"
fi

# ------------------------------------------------------------------------------------------
section "5. Input devices"
evs=(/dev/input/event*)
if [[ ${#evs[@]} -eq 0 ]]; then
    pend "no /dev/input/event* — expected until the S4 USB nodes are in the device tree"
else
    ok "${#evs[@]} evdev node(s):"
    for e in /sys/class/input/event*; do note "$(basename "$e"): $(cat "$e/device/name" 2>/dev/null)"; done
    note "(no keyboard/mouse listed? only on-SoC buttons/IR exist until USB host works)"
fi

# ------------------------------------------------------------------------------------------
section "6. Seat / session management"
if systemctl is-active --quiet systemd-logind 2>/dev/null; then ok "systemd-logind active (libseat uses it; seatd not needed)"
else fail "systemd-logind not active and no seatd: compositors cannot open DRM/input as a user"; fi
if seat=$(loginctl seat-status seat0 --no-pager 2>/dev/null); then
    drm_on_seat=$(grep -c 'drm:' <<<"$seat" || true)
    in_on_seat=$(grep -c 'input:' <<<"$seat" || true)
    note "seat0 has ${drm_on_seat} drm and ${in_on_seat} input device(s) attached"
fi
note "user $(id -un) groups: $(id -nG)  (video/input membership not required with logind)"
if [[ -n ${XDG_SESSION_ID:-} ]]; then
    note "this login: $(loginctl show-session "$XDG_SESSION_ID" -p Type -p Seat -p VTNr --value 2>/dev/null | tr '\n' ' ') (serial logins have no seat — that is normal)"
fi

# ------------------------------------------------------------------------------------------
section "7. vim1s-desktop install state"
missing=()
for p in greetd greetd-tuigreet hyprland sway foot fuzzel mako waybar swayidle swaylock; do
    pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
done
if [[ ${#missing[@]} -eq 0 ]]; then ok "all desktop packages installed"; else
    warn "not installed yet: ${missing[*]}  (scripts/install.sh)"
fi
if getent passwd greeter >/dev/null; then ok "user 'greeter' exists"; else warn "user 'greeter' missing (created by the greetd package)"; fi
if systemctl is-enabled --quiet greetd.service 2>/dev/null; then ok "greetd.service enabled"; else warn "greetd.service not enabled yet"; fi
for c in hypr sway waybar foot fuzzel mako swaylock swayidle; do
    t="${XDG_CONFIG_HOME:-$HOME/.config}/$c"
    if [[ -L $t ]]; then note "$t -> $(readlink "$t")"; fi
done
for b in vim1s-session vim1s-shell vim1s-dpms vim1s-sway-modeset; do
    command -v "$b" >/dev/null || { warn "$b not in PATH (scripts/install.sh installs it to /usr/local/bin)"; break; }
done

# ------------------------------------------------------------------------------------------
section "8. Network (for deployment)"
if def=$(ip route show default 2>/dev/null) && [[ -n $def ]]; then
    ok "default route: $def"
    ip -br addr 2>/dev/null | grep -v '^lo ' | while IFS= read -r l; do note "$l"; done
else
    pend "no default route yet (wpa_supplicant / DHCP) — deploy over SSH needs it"
fi
if systemctl is-active --quiet sshd 2>/dev/null; then ok "sshd active"; else warn "sshd not active (deploy uses SSH)"; fi

# ------------------------------------------------------------------------------------------
printf '\n%sSummary:%s %d FAIL, %d WARN, %d PENDING\n' "$_b" "$_n" "$fails" "$warns" "$pends"
[[ $fails -eq 0 ]]
