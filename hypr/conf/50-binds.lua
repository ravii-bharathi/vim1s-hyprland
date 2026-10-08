-- Keybinds. Kept identical to sway/config.d/50-binds so either session feels the same.
--
--   SUPER+Return      terminal          SUPER+D            launcher
--   SUPER+Q           close window      SUPER+F            fullscreen
--   SUPER+V           toggle float      SUPER+arrows       move focus
--   SUPER+SHIFT+arrow move window       SUPER+1..9         workspace
--   SUPER+SHIFT+1..9  send to workspace SUPER+Escape       lock
--   SUPER+N           dismiss notifs    SUPER+SHIFT+E      exit session

local v   = require("./vars.lua")
local mod = v.mod

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(v.terminal))
hl.bind(mod .. " + D",      hl.dsp.exec_cmd(v.launcher))
hl.bind(mod .. " + Q",      hl.dsp.window.close())
hl.bind(mod .. " + F",      hl.dsp.window.fullscreen())          -- default action = toggle
hl.bind(mod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd(v.lock))
hl.bind(mod .. " + N",      hl.dsp.exec_cmd("makoctl dismiss --all"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())

for _, dir in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mod .. " + " .. dir,             hl.dsp.focus({ direction = dir }))
    hl.bind(mod .. " + SHIFT + " .. dir,     hl.dsp.window.move({ direction = dir }))
end

for i = 1, 9 do
    hl.bind(mod .. " + " .. i,             hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i,     hl.dsp.window.move({ workspace = i }))
end

-- Mouse: SUPER + left drag = move, SUPER + right drag = resize.
-- (The upstream example passes { mouse = true }; 0.56.2's hl.bind does not read that key,
--  the mouse behaviour comes from the dispatcher itself, so it is omitted here.)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize())
