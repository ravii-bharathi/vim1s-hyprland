-- vim1s-desktop :: Hyprland entry point (Hyprland >= 0.55, Lua config)
--
-- Target: Khadas VIM1S (Amlogic S905Y4, Mali-G31 MP1 via Panfrost, 2 GB RAM).
-- Verified against Hyprland v0.56.2 source + generated stubs (meta/hl.meta.lua).
--
-- Layout:
--   vars.lua        shared variables (terminal, launcher, ...), require("./vars.lua")
--   conf/NN-*.lua   one concern per file, loaded in sorted order by the glob below
--
-- Why one file per concern: Hyprland runs every require()'d file in its own scope,
-- so a runtime error in e.g. 50-binds.lua does not stop 10-perf.lua from applying.
-- Relative paths resolve against THIS file's directory, so `Hyprland -c <repo>/hypr/hyprland.lua`
-- works straight from the git checkout (that is how dev/nested.sh tests it).
--
-- Editor support: point LuaLS at /usr/share/hypr/stubs (see .luarc.json in repo root).

require("./conf/*")
