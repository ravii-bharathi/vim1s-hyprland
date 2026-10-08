#!/usr/bin/env bash
# install.sh — install vim1s-desktop ON THE BOARD (Arch Linux ARM). Idempotent: re-run any time.
#
#   ./scripts/install.sh [--profile hyprland|sway|all] [--with-debug] [--no-packages]
#                        [--no-greetd] [--dry-run] [--yes]
#
# Run as your normal user (default board user: alarm); system steps use sudo.
#
# What it does, in order (each step is skipped when already in the desired state):
#   1. pacman -S --needed  for packages/{base,shell}.txt + the profile's list (+ debug.txt)
#   2. /usr/local/bin/vim1s-*                 helper scripts (copied, root-owned)
#      /usr/local/share/vim1s/wayland-sessions the curated session list tuigreet shows
#      /etc/greetd/config.toml                 (old one backed up as *.vim1s-bak.<timestamp>)
#   3. ~/.config/<tool> -> <repo>/<tool>       symlinks; an existing real dir is moved aside
#   4. systemctl enable greetd, disable getty@tty1  (greetd owns VT1; the serial getty is untouched)
#      Nothing is started now: the new login takes effect at the next boot.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

profile=all with_debug=0 do_pkgs=1 do_greetd=1 assume_yes=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile) profile=${2:?--profile needs a value}; shift ;;
        --with-debug) with_debug=1 ;;
        --no-packages) do_pkgs=0 ;;
        --no-greetd) do_greetd=0 ;;
        --dry-run) DRY_RUN=1 ;;
        --yes | -y) assume_yes=1 ;;
        -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
command -v pacman >/dev/null || die "pacman not found: this script is for the Arch Linux ARM board"
[[ $(uname -m) == aarch64 ]] || warn "not aarch64 ($(uname -m)) — continuing, but this targets the VIM1S"

ts=$(date +%Y%m%d-%H%M%S)
# did <word> <path...> : status line after a change; silent in --dry-run (the [dry-run] line says it all)
did() { [[ $DRY_RUN == 1 ]] || printf '    %-10s %s\n' "$1" "${*:2}"; }
cfg_home=${XDG_CONFIG_HOME:-$HOME/.config}

# ---------------------------------------------------------------- plan + confirmation
read -r -a pkg_files <<<"$(pkg_files_for_profile "$profile")"
[[ $with_debug == 1 ]] && pkg_files+=("$VIM1S_ROOT/packages/debug.txt")
mapfile -t pkgs < <(read_pkgs "${pkg_files[@]}")

info "vim1s-desktop install  (repo: $VIM1S_ROOT, profile: $profile, dry-run: $DRY_RUN)"
echo "    packages : $([[ $do_pkgs == 1 ]] && echo "${pkgs[*]}" || echo skipped)"
echo "    system   : /usr/local/bin/vim1s-*, /usr/local/share/vim1s/, $([[ $do_greetd == 1 ]] && echo '/etc/greetd/config.toml + greetd.service' || echo 'greetd skipped')"
echo "    user     : symlinks in $cfg_home -> $VIM1S_ROOT"
if [[ $DRY_RUN == 0 && $assume_yes == 0 ]]; then
    read -r -p "Proceed? [y/N] " ans
    [[ $ans == [yY]* ]] || die "aborted by user"
fi

# ---------------------------------------------------------------- 1. packages
if [[ $do_pkgs == 1 ]]; then
    info "1/4 packages (pacman --needed skips what is already installed)"
    run sudo pacman -S --needed "${pkgs[@]}"
else
    info "1/4 packages: skipped (--no-packages)"
fi

# ---------------------------------------------------------------- 2. system files
info "2/4 system files"
# install_if_changed <mode> <src> <dst> : copy only when content differs (keeps mtimes stable).
install_if_changed() {
    local mode=$1 src=$2 dst=$3
    if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
        echo "    unchanged  $dst"
    else
        if [[ -f $dst ]] && [[ $dst == /etc/* ]]; then
            run sudo cp -a "$dst" "$dst.vim1s-bak.$ts"
            did backup "$dst.vim1s-bak.$ts"
        fi
        run sudo install -D -m "$mode" "$src" "$dst"
        did installed "$dst"
    fi
}

for f in "$VIM1S_ROOT"/bin/*; do
    install_if_changed 0755 "$f" "/usr/local/bin/$(basename "$f")"
done

sessions_dir=/usr/local/share/vim1s/wayland-sessions
case $profile in
    hyprland) sessions=(hyprland.desktop) ;;
    sway)     sessions=(sway.desktop) ;;
    all)      sessions=(hyprland.desktop sway.desktop) ;;
esac
for s in "${sessions[@]}"; do
    install_if_changed 0644 "$VIM1S_ROOT/session/wayland-sessions/$s" "$sessions_dir/$s"
done

if [[ $do_greetd == 1 ]]; then
    install_if_changed 0644 "$VIM1S_ROOT/session/greetd/config.toml" /etc/greetd/config.toml
fi

# ---------------------------------------------------------------- 3. user config symlinks
info "3/4 user configs"
link_config() {
    local src="$VIM1S_ROOT/$1" dst="$cfg_home/$1"
    [[ -e $src ]] || die "missing in repo: $src"
    if [[ -L $dst && $(readlink -f "$dst") == "$(readlink -f "$src")" ]]; then
        echo "    ok         $dst -> $src"
        return
    fi
    if [[ -e $dst || -L $dst ]]; then
        run mv "$dst" "$dst.vim1s-bak.$ts"
        did moved "$dst -> $dst.vim1s-bak.$ts"
    fi
    run mkdir -p "$cfg_home"
    run ln -s "$src" "$dst"
    did linked "$dst -> $src"
}
for c in foot fuzzel mako waybar swaylock swayidle; do link_config "$c"; done
[[ $profile == hyprland || $profile == all ]] && link_config hypr
[[ $profile == sway || $profile == all ]] && link_config sway

if [[ ! -e $cfg_home/vim1s/session.env ]]; then
    echo "    hint       optional debug knobs: cp $VIM1S_ROOT/session/session.env.example $cfg_home/vim1s/session.env"
fi

# ---------------------------------------------------------------- 4. services
info "4/4 services"
if [[ $do_greetd == 1 ]]; then
    if ! getent passwd greeter >/dev/null; then
        if [[ $DRY_RUN == 1 ]]; then
            warn "user 'greeter' does not exist yet (the greetd package is expected to create it)"
        else
            die "user 'greeter' missing after installing greetd — check: pacman -Ql greetd | grep sysusers"
        fi
    fi
    if systemctl is-enabled --quiet greetd.service 2>/dev/null; then
        echo "    ok         greetd.service enabled"
    else
        run sudo systemctl enable greetd.service
    fi
    if systemctl is-enabled --quiet getty@tty1.service 2>/dev/null; then
        run sudo systemctl disable getty@tty1.service
    else
        echo "    ok         getty@tty1.service not enabled (greetd owns VT1)"
    fi
    echo "    note       nothing started now; reboot (or: sudo systemctl start greetd) once display + input work"
else
    echo "    skipped    (--no-greetd)"
fi

info "done. Next: ./scripts/check-board.sh"
