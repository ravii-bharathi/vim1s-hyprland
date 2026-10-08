-- Autostart. The shell (bar, notifications, terminal server, idle) is NOT listed here:
-- it lives in bin/vim1s-shell so Hyprland and sway start exactly the same components.

local v = require("./vars.lua")

hl.on("hyprland.start", function()
    hl.exec_cmd(v.shell)
end)
