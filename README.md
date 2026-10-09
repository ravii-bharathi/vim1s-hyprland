# vim1s-desktop

A lean, modular Wayland desktop for the **Khadas VIM1S** (Amlogic S905Y4, 4× Cortex-A35,
2 GB RAM, Mali-G31 MP1 via Panfrost) on **Arch Linux ARM** with a mainline kernel.
Authored and tested on an x86_64 laptop, deployed to the board over SSH.

Hyprland is the primary session and sway the fallback. Both share one shell, and you choose
between them at the login screen.

```
 Layer 0  login          greetd ── tuigreet (console TUI, no GPU)  ── vim1s-session (logs, env)
                                         │ F3: pick session
 Layer 1  compositor     Hyprland 0.56 (Lua)        │        sway 1.12 (fallback)
                         hypr/hyprland.lua          │        sway/config
                         hypr/conf/NN-*.lua         │        sway/config.d/NN-*
                                         └──────┬───┘
 Layer 2  shared shell   vim1s-shell ─┬─ waybar   (ext/workspaces: same bar for both)
                                      ├─ mako     (notifications)
                                      ├─ foot --server / footclient (terminal)
                                      ├─ fuzzel   (launcher)
                                      └─ swayidle → swaylock / vim1s-dpms
```

## Repository layout

| Path | What |
|---|---|
| `hypr/` | Hyprland Lua config: `hyprland.lua` loads `conf/*` in sorted order; `vars.lua` holds shared variables |
| `sway/` | sway fallback config: same keybinds, same shell |
| `waybar/` | `config.jsonc` (layout only) + `modules.d/*.jsonc` (one module per file) + `style.css` |
| `foot/ fuzzel/ mako/ swaylock/ swayidle/` | tool configs, symlinked into `~/.config` by `install.sh` |
| `bin/` | `vim1s-session` (greetd wrapper + persistent log), `vim1s-shell`, `vim1s-dpms`, `vim1s-sway-modeset` |
| `session/` | greetd `config.toml`, curated `wayland-sessions/*.desktop`, `session.env.example` |
| `packages/` | `base`, `shell`, `hyprland`, `sway`, `debug` package lists (validated against live ALARM) |
| `scripts/` | `install.sh` (board), `check-board.sh` (board, read-only), `deploy.sh`, `validate.sh` |
| `dev/` | `Containerfile` (pinned Arch test env), `nested.sh`, `hl_api_check.lua`, `waybar_check.py` |

## Keybinds (identical in both sessions)

| Keys | Action | Keys | Action |
|---|---|---|---|
| `SUPER+Return` | terminal | `SUPER+D` | launcher |
| `SUPER+Q` | close window | `SUPER+F` | fullscreen |
| `SUPER+V` | toggle floating | `SUPER+arrows` | move focus |
| `SUPER+SHIFT+arrows` | move window | `SUPER+1..9` | workspace |
| `SUPER+SHIFT+1..9` | send to workspace | `SUPER+Escape` | lock |
| `SUPER+N` | dismiss notifications | `SUPER+SHIFT+E` | exit session |

## Workflow

### 1. Laptop: one-time setup (Ubuntu 26.04, GNOME on Wayland)

```sh
sudo apt install podman distrobox        # both in universe
git clone vim1s-desktop.bundle ~/src/vim1s-desktop   # from the bundle; repo must be under $HOME
cd ~/src/vim1s-desktop
git remote rename origin bundle          # optional: then add your bare repo / GitHub as origin
make box                                 # builds dev/Containerfile, creates the distrobox
```

### 2. Laptop: edit → validate → try

```sh
make validate        # 9 stages; see scripts/validate.sh header
make nested-hypr     # Hyprland as a 1280x720 window in GNOME (GLES capped at 3.1 like the G31)
make nested-sway
```

`make validate` checks, among other things:
- every Hyprland option, dispatcher, bind flag and event against the **installed Hyprland's own
  API stubs**, plus a unit test of the 1080p → 720p → preferred monitor policy;
- Hyprland's and sway's own config parsers;
- that every package name resolves, with dependencies, in the **live ALARM aarch64 repos**;
- that the container's versions equal the board's.

### 3. Board: now, over the serial console

```sh
./scripts/check-board.sh     # or from the laptop: make check-board
```

PASS / WARN / FAIL / PENDING per prerequisite. **PENDING** marks items waiting on in-progress BSP
work (S4 KMS driver, S4 USB nodes); those do not count as failures. Install `packages/debug.txt`
(`install.sh --with-debug`) to get `eglinfo`. It tests GLES on the Panfrost render node
**without a display**, including Hyprland's hard-required extensions.

### 4. Board: deploy + install (once networking works)

```sh
make install-board BOARD=alarm@<board-ip>   # deploy.sh → install.sh, both ask before acting
```

`install.sh` is idempotent: run it again after every change. It enables greetd for the next boot
and disables `getty@tty1`. The serial getty is never touched, so UART login always works.

### Logs (read these over serial when something fails)

| Log | Contents |
|---|---|
| `~/.local/state/vim1s/session-<name>.log` | compositor stdout/stderr + env + `/dev/dri` at start (previous run: `.log.1`) |
| `~/.local/state/vim1s/shell.log` and `<component>.log` | waybar / mako / foot / swayidle startup |
| `$XDG_RUNTIME_DIR/hypr/*/hyprland.log` | Hyprland's own log (lost on reboot) |
| `journalctl -b -u greetd` | greeter / login failures |

Debug knobs (`AQ_NO_ATOMIC`, `AQ_DRM_DEVICES`, `WLR_RENDERER=pixman`, …): copy
`session/session.env.example` to `~/.config/vim1s/session.env` and uncomment.

## Decisions and the facts behind them

| Decision | Verified fact (source) |
|---|---|
| Lua config, not `hyprland.conf` | hyprlang is deprecated since 0.55; `~/.config/hypr/hyprland.lua` is the default (wiki.hypr.land) |
| Monitor fallback in `monitor.added` | `hl.monitor()` schedules a monitor-state refresh, so calling it at runtime applies (Hyprland `LuaBindingsConfigRules.cpp`) |
| `ext/workspaces` in waybar | waybar 0.15.0's `hyprland/workspaces` clicks send legacy `dispatch workspace N`; with a Lua config, Hyprland evaluates `dispatch` arguments as Lua (`HyprCtl.cpp`). Hyprland 0.56 and sway 1.12 both implement ext-workspace-v1 |
| `render.cm_enabled=false`, `use_fp16=0`, `new_render_scheduling=true` | option descriptions + defaults in Hyprland `ConfigValues.cpp`; upstream says new scheduling "should improve FPS on underpowered devices" |
| VFR not set | `debug:vfr` defaults to on; upstream says do not change it unless debugging |
| `direct_scanout` left at 0 | default off; enable (`2` = auto) once the S4 KMS driver is stable |
| No `{ mouse = true }` on drag binds | 0.56.2's `hl.bind` does not read that key; the drag/resize dispatchers set mouse mode themselves |
| GLES expectations | Hyprland requests GLES 3.2 and falls back to 3.0; Panfrost exposes GLES 3.1 on Bifrost v7 (G31) |
| Display card selection | aquamarine only uses KMS-capable DRM devices (unless `AQ_NO_KMS_REQUIREMENT`), so Panfrost's render-only node is skipped automatically |
| `start-hyprland` as session Exec | upstream `hyprland.desktop` uses it; it restarts in safe mode only after a crash *after* init, so a GPU-init failure does not loop |
| Curated session dir for tuigreet | the distro dir may contain `hyprland-uwsm.desktop`, which fails without uwsm |
| swaylock over hyprlock, swaybg over hyprpaper | hyprlock is GPU-accelerated; hyprpaper now pulls hyprtoolkit |
| Pinned Arch archive date in the container | Ubuntu 26.04 ships Hyprland 0.53.3; Arch x86_64 and ALARM both had 0.56.2-4 on 2026-10-08 |

## Not verified from the build environment

Some upstream sources were unreachable when this repo was authored (Codeberg, freedesktop GitLab,
a few archlinuxarm.org pages). Everything below is therefore checked on **your** machines
by `make validate`, not assumed:

- `ttf-dejavu`, `mesa-utils`, `drm_info`, `evtest` package names on ALARM (marked `unverified` in `packages/`)
- `foot` / `fuzzel` configs use only long-stable keys and are checked by their own `--check-config`
- Mesa / wlroots environment variables in `session.env.example` are listed but commented out

## Updating the pinned versions

1. Pick a newer date: `make image ARCHIVE_DATE=YYYY/MM/DD`, or `make image ARCHIVE_DATE=` to use live
   mirrors when archive.archlinux.org is slow (one server in Europe). Stage 9 of `make validate` then reports drift.
2. `distrobox rm vim1s-dev && make box && make validate`. Stage 9 tells you whether ALARM has caught up.
3. Read the Hyprland release notes for Lua API changes. `hl_api_check.lua` flags removed or renamed options automatically.
