# shellcheck shell=bash
# Shared helpers for scripts/*.sh and dev/*.sh. Source it; do not execute.

VIM1S_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export VIM1S_ROOT

if [[ -t 1 ]]; then
    _b=$'\033[1m' _r=$'\033[31m' _g=$'\033[32m' _y=$'\033[33m' _c=$'\033[36m' _n=$'\033[0m'
else
    _b='' _r='' _g='' _y='' _c='' _n=''
fi

info() { printf '%s==>%s %s\n' "$_b$_c" "$_n" "$*"; }
ok()   { printf '  %sPASS%s    %s\n' "$_g" "$_n" "$*"; }
warn() { printf '  %sWARN%s    %s\n' "$_y" "$_n" "$*"; }
fail() { printf '  %sFAIL%s    %s\n' "$_r" "$_n" "$*"; }
pend() { printf '  %sPENDING%s %s\n' "$_c" "$_n" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$_r" "$_n" "$*" >&2; exit 1; }

# run <cmd...> : execute, or only print when DRY_RUN=1.
DRY_RUN=${DRY_RUN:-0}
run() {
    if [[ $DRY_RUN == 1 ]]; then
        printf '    [dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# read_pkgs <file...> : package names from packages/*.txt (comments and blanks stripped).
read_pkgs() {
    local f
    for f in "$@"; do
        [[ -r $f ]] || die "package list not found: $f"
        sed -e 's/#.*//' -e 's/[[:space:]]//g' "$f" | grep -v '^$' || true
    done
}

# pkg_files_for_profile <hyprland|sway|all> : package list files for a profile.
pkg_files_for_profile() {
    local p=$1 d="$VIM1S_ROOT/packages"
    case $p in
        hyprland) echo "$d/base.txt $d/shell.txt $d/hyprland.txt" ;;
        sway)     echo "$d/base.txt $d/shell.txt $d/sway.txt" ;;
        all)      echo "$d/base.txt $d/shell.txt $d/hyprland.txt $d/sway.txt" ;;
        *)        die "unknown profile '$p' (expected hyprland|sway|all)" ;;
    esac
}
