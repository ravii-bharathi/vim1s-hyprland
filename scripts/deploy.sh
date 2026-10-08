#!/usr/bin/env bash
# deploy.sh — copy this repo to the board over SSH (and optionally run install.sh there).
#
#   scripts/deploy.sh <user@host> [--dest DIR] [--install [--profile P] [--with-debug]] [--yes]
#
#   default DIR: vim1s-desktop — a relative path, which ssh/rsync/tar all resolve against the
#                board user's HOME (install.sh symlinks ~/.config/* into this deployed tree).
#
# Transport:
#   rsync (if present on both ends)  -> incremental copy of the working tree incl. .git
#   otherwise: git archive | ssh tar -> copies the last COMMIT only (rsync is not in ALARM's base)
# A file .vim1s-deployed on the board records which commit (and dirty state) was deployed.
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$VIM1S_ROOT"

target=${1:-}
[[ -n $target && $target != -* ]] || die "usage: scripts/deploy.sh <user@host> [--dest DIR] [--install ...] [--yes]"
shift
dest=vim1s-desktop do_install=0 assume_yes=0 install_args=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --dest) dest=${2:?}; shift ;;
        --install) do_install=1 ;;
        --profile) install_args+=(--profile "${2:?}"); shift ;;
        --with-debug) install_args+=(--with-debug) ;;
        --yes | -y) assume_yes=1 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

rev=$(git describe --always --dirty 2>/dev/null || echo "no-git")
[[ $rev == *-dirty ]] && warn "working tree has uncommitted changes ($rev)"

info "checking SSH to $target"
ssh -o BatchMode=yes -o ConnectTimeout=8 "$target" true || die "cannot SSH to $target (keys set up? board on the network?)"

if command -v rsync >/dev/null && ssh "$target" 'command -v rsync' >/dev/null 2>&1; then
    transport=rsync
else
    transport=tar
fi

info "plan: $rev -> $target:$dest via $transport$([[ $do_install == 1 ]] && echo ", then install.sh ${install_args[*]}")"
if [[ $assume_yes == 0 ]]; then
    read -r -p "Proceed? [y/N] " ans
    [[ $ans == [yY]* ]] || die "aborted by user"
fi

# shellcheck disable=SC2029  # $dest is meant to expand on the board (it may contain ~)
ssh "$target" "mkdir -p $dest"
if [[ $transport == rsync ]]; then
    rsync -az --delete --info=stats1 ./ "$target:$dest/"
else
    [[ $rev == *-dirty ]] && warn "tar mode ships the last commit only; uncommitted changes are NOT deployed"
    # shellcheck disable=SC2029
    git archive --format=tar HEAD | ssh "$target" "tar -x -C $dest"
fi
# shellcheck disable=SC2029
ssh "$target" "echo '$rev $(date -u +%Y-%m-%dT%H:%M:%SZ)' > $dest/.vim1s-deployed"
ok "deployed $rev"

if [[ $do_install == 1 ]]; then
    info "running install.sh on the board (interactive: sudo will ask for the password)"
    # shellcheck disable=SC2029
    ssh -t "$target" "cd $dest && ./scripts/install.sh ${install_args[*]:-}"
fi
