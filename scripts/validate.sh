#!/usr/bin/env bash
# validate.sh — every check that can run WITHOUT the board. Run before each deploy.
#
#   make validate                 (runs this inside the vim1s-dev distrobox)
#   scripts/validate.sh [--offline]
#
# Stages (each PASS / FAIL / SKIP; all stages run, exit 1 if any FAIL):
#   1 shellcheck        bin/*, scripts/*.sh, dev/*.sh
#   2 waybar            JSONC parse + includes exist + every layout module defined (dev/waybar_check.py)
#   3 hyprland-api      luac -p + config vs installed Hyprland stubs + monitor policy unit test
#   4 hyprland-verify   Hyprland --verify-config (the compositor's own parser)
#   5 sway              sway -C (sway's own parser)
#   6 foot / fuzzel     their --check-config, when the installed version supports it
#   7 session files     greetd TOML parses, paths match install.sh, .desktop files sane
#   8 alarm-packages    every name in packages/*.txt resolves (with deps) in the LIVE ALARM aarch64 repos
#   9 version-parity    container versions == ALARM versions (what you test is what the board runs)
# --offline skips 8 and 9.
set -uo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$VIM1S_ROOT" || exit 1

offline=0
[[ ${1:-} == --offline ]] && offline=1
ALARM_MIRROR=${ALARM_MIRROR:-http://mirror.archlinuxarm.org}
HYPR_STUBS=${HYPR_STUBS:-/usr/share/hypr/stubs/hl.meta.lua}

failed=() skipped=()
stage() { printf '\n%s[%s]%s %s\n' "$_b" "$1" "$_n" "$2"; }
pass_() { ok "$*"; }
fail_() { fail "$*"; failed+=("$cur"); }
skip_() { warn "SKIP: $*"; skipped+=("$cur"); }
have() { command -v "$1" >/dev/null 2>&1; }

[[ -f /etc/vim1s-dev-versions.txt ]] || warn "not inside the vim1s-dev container: some stages may SKIP (use: make validate)"

# ------------------------------------------------------------------------------------- 1
cur=shellcheck; stage 1 "shellcheck"
if have shellcheck; then
    mapfile -t sh_files < <(ls bin/* scripts/*.sh dev/*.sh)
    if shellcheck -x -P SCRIPTDIR -P "$VIM1S_ROOT" "${sh_files[@]}"; then pass_ "${#sh_files[@]} scripts clean"
    else fail_ "shellcheck findings above"; fi
else skip_ "shellcheck not installed"; fi

# ------------------------------------------------------------------------------------- 2
cur=waybar; stage 2 "waybar config"
if python3 -I dev/waybar_check.py waybar/config.jsonc; then pass_ "waybar config consistent"
else fail_ "waybar config errors above"; fi

# ------------------------------------------------------------------------------------- 3
cur=hyprland-api; stage 3 "Hyprland Lua: syntax + API check vs installed stubs"
if have luac; then
    lua_ok=1
    while IFS= read -r f; do luac -p "$f" || lua_ok=0; done < <(find hypr -name '*.lua' | sort)
    if [[ $lua_ok == 1 ]]; then pass_ "luac -p: all hypr/*.lua parse"; else fail_ "Lua syntax errors above"; fi
else skip_ "luac not installed (package: lua)"; fi
if have lua && [[ -r $HYPR_STUBS ]]; then
    if lua dev/hl_api_check.lua hypr/hyprland.lua "$HYPR_STUBS"; then pass_ "config matches $(pacman -Q hyprland 2>/dev/null || echo 'installed') API"
    else fail_ "API check errors above"; fi
else skip_ "need lua + $HYPR_STUBS (installed with the hyprland package)"; fi

# ------------------------------------------------------------------------------------- 4
cur=hyprland-verify; stage 4 "Hyprland --verify-config"
if have Hyprland; then
    out=$(Hyprland --verify-config -c "$VIM1S_ROOT/hypr/hyprland.lua" 2>&1); rc=$?
    if [[ $rc -eq 0 ]]; then pass_ "Hyprland accepted the config"
    else
        printf '%s\n' "$out" | tail -n 25
        fail_ "Hyprland --verify-config exit $rc"
    fi
else skip_ "Hyprland not installed"; fi

# ------------------------------------------------------------------------------------- 5
cur=sway; stage 5 "sway -C"
if have sway; then
    if out=$(sway -C -c "$VIM1S_ROOT/sway/config" 2>&1); then pass_ "sway accepted the config"
    else printf '%s\n' "$out" | tail -n 25; fail_ "sway -C failed"; fi
else skip_ "sway not installed"; fi

# ------------------------------------------------------------------------------------- 6
cur=foot-fuzzel; stage 6 "foot / fuzzel config checkers"
for tool in foot fuzzel; do
    if ! have "$tool"; then skip_ "$tool not installed"; continue; fi
    if "$tool" --help 2>&1 | grep -q -- '--check-config'; then
        if "$tool" --check-config --config="$VIM1S_ROOT/$tool/$tool.ini"; then pass_ "$tool accepted $tool/$tool.ini"
        else fail_ "$tool rejected $tool/$tool.ini"; fi
    else
        skip_ "$tool $($tool --version 2>/dev/null | head -n1) has no --check-config; covered by the nested run"
    fi
done

# ------------------------------------------------------------------------------------- 7
cur=session; stage 7 "session files"
if python3 -I - "$VIM1S_ROOT/session/greetd/config.toml" <<'PY'
import sys, tomllib
cfg = tomllib.load(open(sys.argv[1], "rb"))
cmd = cfg["default_session"]["command"]
need = ["/usr/local/bin/vim1s-session", "/usr/local/share/vim1s/wayland-sessions"]
missing = [n for n in need if n not in cmd]
assert cfg["default_session"]["user"] == "greeter", "user must be greeter"
assert cfg["terminal"]["vt"] == 1, "vt must be 1"
if missing:
    sys.exit("greetd command does not reference: " + ", ".join(missing))
PY
then pass_ "greetd config.toml parses; paths match install.sh"
else fail_ "greetd config.toml"; fi
for d in session/wayland-sessions/*.desktop; do
    if grep -q '^Exec=/' "$d" && grep -q '^DesktopNames=' "$d" && grep -q '^Type=Application' "$d"; then
        pass_ "$d"
    else fail_ "$d lacks absolute Exec=, DesktopNames= or Type="; fi
done

# ------------------------------------------------------------------------------------- 8, 9
if [[ $offline == 1 ]]; then
    cur=alarm; stage 8-9 "ALARM package resolution"; skip_ "--offline"
elif ! have pacman || ! have curl; then
    cur=alarm; stage 8-9 "ALARM package resolution"; skip_ "needs pacman + curl (run inside the vim1s-dev box)"
else
    cur=alarm-packages; stage 8 "resolve packages/*.txt against live ALARM aarch64 repos"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    # Empty "installed" DB (version 9 = pacman 6.x format) so -Si/-Sp treat nothing as installed
    # and resolve the FULL dependency set, as on a fresh board. No root needed for read-only ops.
    mkdir -p "$tmp/sync" "$tmp/local"
    echo 9 >"$tmp/local/ALPM_DB_VERSION"
    dl_ok=1
    for repo in core extra alarm aur; do
        db="$tmp/sync/$repo.db"
        # -L: mirror.archlinuxarm.org answers with a GeoIP REDIRECT to a nearby mirror.
        #     Without -L curl saves the redirect response itself as the "database".
        if ! curl -fsSL --retry 2 -o "$db" "$ALARM_MIRROR/aarch64/$repo/$repo.db"; then
            dl_ok=0; fail_ "could not download $repo.db from $ALARM_MIRROR"
        # A sync DB is a (compressed) tar archive; anything else is an HTML error page, a captive portal...
        elif ! bsdtar -tf "$db" >/dev/null 2>&1; then
            dl_ok=0; fail_ "$repo.db is not a valid package database ($(wc -c <"$db") bytes, starts: $(head -c 60 "$db" | tr -dc '[:print:]'))"
        else
            ok "$repo.db: $(bsdtar -tf "$db" | grep -c '/desc$') packages"
        fi
    done
    if [[ $dl_ok == 1 ]]; then
        pac=(pacman --config "$VIM1S_ROOT/dev/alarm-aarch64.conf" --dbpath "$tmp" --noconfirm)
        mapfile -t all_pkgs < <(read_pkgs packages/*.txt | sort -u)
        unknown=() first_err=''
        for p in "${all_pkgs[@]}"; do
            if ! err=$("${pac[@]}" -Si "$p" 2>&1 >/dev/null); then
                unknown+=("$p")
                [[ -z $first_err ]] && first_err=$err
            fi
        done
        if [[ ${#unknown[@]} -gt 0 ]]; then
            [[ -n $first_err ]] && echo "    pacman said: ${first_err//$'\n'/ | }"
            fail_ "not found in ALARM aarch64: ${unknown[*]}"
        else
            pass_ "all ${#all_pkgs[@]} package names exist in ALARM aarch64"
            if deps=$("${pac[@]}" -Sp --print-format '%n' "${all_pkgs[@]}" 2>&1); then
                pass_ "dependency resolution OK: $(wc -l <<<"$deps") packages in the full transaction"
            else
                printf '%s\n' "$deps" | tail -n 15; fail_ "dependency resolution failed"
            fi
        fi

        cur=version-parity; stage 9 "container versions vs ALARM (what you test == what the board runs)"
        if [[ -r /etc/vim1s-dev-versions.txt ]]; then
            drift=0
            while read -r name local_ver; do
                remote_ver=$("${pac[@]}" -Si "$name" 2>/dev/null | awk -F': ' '/^Version/ {print $2; exit}')
                if [[ $remote_ver == "$local_ver" ]]; then ok "$name $local_ver"
                else warn "$name: container $local_ver, ALARM ${remote_ver:-?}"; drift=1; fi
            done </etc/vim1s-dev-versions.txt
            if [[ $drift == 0 ]]; then pass_ "no version drift"
            else warn "drift: rebuild the image with a newer ARCHIVE_DATE (dev/Containerfile) or accept it"; fi
        else skip_ "/etc/vim1s-dev-versions.txt missing (not in the vim1s-dev image)"; fi
    fi
fi

# ------------------------------------------------------------------------------------- summary
printf '\n%sSummary:%s ' "$_b" "$_n"
if [[ ${#failed[@]} -eq 0 ]]; then
    printf '%sall checks passed%s' "$_g" "$_n"
else
    printf '%sFAILED: %s%s' "$_r" "${failed[*]}" "$_n"
fi
[[ ${#skipped[@]} -gt 0 ]] && printf '  (skipped: %s)' "$(printf '%s\n' "${skipped[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
printf '\n'
[[ ${#failed[@]} -eq 0 ]]
