-- Display policy: 1920x1080@60, fall back to 1280x720@60, then to the monitor's preferred mode.
--
-- How it works:
--   1. A catch-all rule (output = "") asks for 1080p60 on every output.
--   2. When an output appears (event "monitor.added"), we read its real mode list
--      (HL.Monitor.available_modes: {width, height, refresh_rate, preferred}) and,
--      if 1080p60 is not offered, override the rule for that output only.
--   hl.monitor() schedules a monitor-state refresh, so calling it from the event applies live.

local v = require("./vars.lua")

local WANT = {
    { w = 1920, h = 1080, hz = 60 },
    { w = 1280, h = 720,  hz = 60 },
}

local function has_mode(mon, want)
    for _, m in ipairs(mon.available_modes or {}) do
        -- refresh_rate is in Hz (float); 59.94 counts as 60
        if m.width == want.w and m.height == want.h and math.abs(m.refresh_rate - want.hz) < 1.0 then
            return true
        end
    end
    return false
end

local function pick_mode(mon)
    for _, want in ipairs(WANT) do
        if has_mode(mon, want) then
            return string.format("%dx%d@%d", want.w, want.h, want.hz)
        end
    end
    return "preferred"
end

if v.nested then
    -- Nested window: the "monitor" is a window on the host desktop. Fixed 720p keeps it small.
    hl.monitor({ output = "", mode = "1280x720@60", position = "auto", scale = 1 })
else
    hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = 1 })

    hl.on("monitor.added", function(mon)
        local mode = pick_mode(mon)
        if mode ~= "1920x1080@60" then
            hl.monitor({ output = mon.name, mode = mode, position = "auto", scale = 1 })
        end
    end)
end
