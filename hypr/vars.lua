-- Shared variables for every module in ./conf.  Usage: local v = require("./vars.lua")

local M = {}

M.mod      = "SUPER"
M.terminal = "footclient"   -- client of the `foot --server` started by vim1s-shell (one font cache, less RAM)
M.launcher = "fuzzel"
M.lock     = "swaylock -f"  -- shm/cairo locker: no GPU work while locked
M.shell    = "vim1s-shell"  -- starts foot server, mako, waybar, swayidle (shared with the sway session)

-- Set by dev/nested.sh when Hyprland runs as a window inside another compositor.
M.nested   = os.getenv("VIM1S_NESTED") == "1"

return M
