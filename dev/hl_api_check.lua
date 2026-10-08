-- hl_api_check.lua — static check of a Hyprland Lua config against Hyprland's OWN API stubs.
--
--   lua dev/hl_api_check.lua <hyprland.lua> [stubs=/usr/share/hypr/stubs/hl.meta.lua]
--
-- The stub file is generated from Hyprland's source at build time and installed by the
-- hyprland package, so this always checks against the exact version you have installed.
-- No display, GPU or running compositor needed (complements `Hyprland --verify-config`).
--
-- Checks:
--   * every hl.<fn> called exists in HL.API, every hl.dsp.* dispatcher exists
--   * hl.config{} keys/sub-tables/types match HL.ConfigOpt.*  (catches typos like blur.enable)
--   * hl.bind option keys match HL.BindOptions, hl.monitor fields match HL.MonitorSpec
--   * hl.on() event names are in HL.EventName
--   * require() follows Hyprland's rules: "./x" relative to the main config, "./dir/*" = sorted glob
--   * then fires synthetic "monitor.added" events to unit-test the monitor fallback policy
-- Exit status 0 = clean, 1 = problems found.

local main_path = arg[1] or error("usage: lua hl_api_check.lua <hyprland.lua> [hl.meta.lua]")
local stub_path = arg[2] or "/usr/share/hypr/stubs/hl.meta.lua"

local problems = {}
local SELF = debug.getinfo(1, "S").source
local function problem(msg)
    -- Report the first stack frame that belongs to the user's config, not to this checker.
    local where = "?"
    for level = 2, 30 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.source ~= SELF and info.what ~= "C" then
            where = info.short_src .. ":" .. (info.currentline or "?")
            break
        end
    end
    problems[#problems + 1] = where .. ": " .. msg
end

---------------------------------------------------------------------------- parse stubs
local classes, aliases = {}, {}
do
    local fh = assert(io.open(stub_path, "r"), "cannot open stubs: " .. stub_path)
    local cur_class, cur_alias
    for line in fh:lines() do
        local c = line:match("^%-%-%-@class%s+([%w%._]+)")
        local a = line:match("^%-%-%-@alias%s+([%w%._]+)")
        if c then
            cur_class, cur_alias = c, nil
            classes[c] = classes[c] or {}
        elseif a then
            cur_alias, cur_class = a, nil
            aliases[a] = aliases[a] or {}
        else
            local fname, ftype = line:match("^%-%-%-@field%s+([%w_%[%]'%.\"]+)%??%s+(.+)$")
            if fname and cur_class then
                fname = fname:gsub("^%['", ""):gsub("'%]$", "")
                classes[cur_class][fname] = ftype
            end
            local alt = line:match('^%-%-%-|%s+"([^"]+)"')
            if alt and cur_alias then
                aliases[cur_alias][alt] = true
            end
        end
    end
    fh:close()
end
assert(classes["HL.API"] and classes["HL.ConfigOpt"], "stub file has no HL.API / HL.ConfigOpt: wrong file?")

---------------------------------------------------------------------------- type checks
local function lua_matches(v, t)
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    if t == "any" then return true end
    if t == "integer" then return math.type(v) == "integer" end
    if t == "number" then return type(v) == "number" end
    if t == "boolean" then return type(v) == "boolean" end
    if t == "string" then return type(v) == "string" end
    if t:match("^table") or t:match("%[%]$") then return type(v) == "table" end
    if t:match("^fun") then return type(v) == "function" end
    if t:match("^HL%.") then return type(v) == "table" or type(v) == "string" or type(v) == "number" end
    if t:match("^{") then return type(v) == "table" end
    return true -- unknown annotation: do not guess
end

local function type_ok(v, ftype)
    for alt in (ftype .. "|"):gmatch("([^|]+)|") do
        if lua_matches(v, alt) then return true end
    end
    return false
end

local function validate(tbl, cls, path)
    local schema = classes[cls]
    if not schema then return end
    if type(tbl) ~= "table" then
        problem(path .. " must be a table")
        return
    end
    for k, v in pairs(tbl) do
        local key = path .. "." .. tostring(k)
        local ftype = schema[k]
        if not ftype then
            problem("unknown option " .. key .. " (not in " .. cls .. ")")
        else
            local sub = ftype:match("^(HL%.ConfigOpt%.[%w%.]+)%??$")
            if sub and classes[sub] then
                validate(v, sub, key)
            elseif not type_ok(v, ftype) then
                problem(key .. " = " .. tostring(v) .. " has type " .. (math.type(v) or type(v)) .. ", expected " .. ftype)
            end
        end
    end
end

---------------------------------------------------------------------------- mock hl
local calls = { monitor = {}, on = {} }
local hl = {}

local function dispatcher_ns(cls, prefix)
    local ns = {}
    for name, ftype in pairs(classes[cls] or {}) do
        local sub = ftype:match("^(HL%.Dsp%w+Namespace)$")
        if sub then
            ns[name] = dispatcher_ns(sub, prefix .. name .. ".")
        else
            local full = prefix .. name
            ns[name] = function(...) return { __dispatcher = full, args = { ... } } end
        end
    end
    return setmetatable(ns, {
        __index = function(_, k)
            problem("dispatcher " .. prefix .. tostring(k) .. " does not exist")
            return function() return { __dispatcher = "invalid" } end
        end,
    })
end
hl.dsp = dispatcher_ns("HL.DspNamespace", "hl.dsp.")

function hl.config(t) validate(t, "HL.ConfigOpt", "config") end

function hl.monitor(spec)
    validate(spec, "HL.MonitorSpec", "monitor")
    if type(spec) ~= "table" or spec.output == nil then problem("hl.monitor: 'output' is required") end
    calls.monitor[#calls.monitor + 1] = spec
end

function hl.bind(keys, dsp, opts)
    if type(keys) ~= "string" then problem("hl.bind: keys must be a string") end
    if not (type(dsp) == "function" or (type(dsp) == "table" and dsp.__dispatcher)) then
        problem("hl.bind '" .. tostring(keys) .. "': second argument must be hl.dsp.* or a function")
    end
    if opts ~= nil then validate(opts, "HL.BindOptions", "bind[" .. tostring(keys) .. "]") end
    return setmetatable({}, { __index = function() return function() end end })
end

function hl.on(event, cb)
    if not (aliases["HL.EventName"] or {})[event] then problem("hl.on: unknown event '" .. tostring(event) .. "'") end
    if type(cb) ~= "function" then problem("hl.on: callback must be a function") end
    calls.on[event] = calls.on[event] or {}
    table.insert(calls.on[event], cb)
    return {}
end

local handle = function() return setmetatable({}, { __index = function() return function() end end }) end
for _, f in ipairs({ "window_rule", "layer_rule", "workspace_rule" }) do
    hl[f] = function(spec)
        if type(spec) ~= "table" then problem("hl." .. f .. ": expected a table") end
        return handle()
    end
end

-- Remaining HL.API functions: accept and record (their arguments are not described in detail by the stubs).
setmetatable(hl, {
    __index = function(_, k)
        if classes["HL.API"][k] then return function() return nil end end
        problem("hl." .. tostring(k) .. " does not exist in HL.API")
        return function() end
    end,
})
_G.hl = hl

---------------------------------------------------------------------------- require() like Hyprland
local base_dir = main_path:match("^(.*)/[^/]*$") or "."
local loaded = {}

local function load_file(path)
    local chunk, err = loadfile(path)
    if not chunk then
        problems[#problems + 1] = "syntax: " .. err
        return nil
    end
    local ok, res = xpcall(chunk, debug.traceback)
    if not ok then
        problems[#problems + 1] = "runtime error in " .. path .. ": " .. tostring(res)
        return nil
    end
    return res == nil and true or res
end

local function resolve(name)
    if name:sub(1, 1) == "/" then return name end
    return base_dir .. "/" .. name:gsub("^%./", "")
end

_G.require = function(name)
    if loaded[name] ~= nil then return loaded[name] end
    if name:sub(1, 2) == "./" or name:sub(1, 1) == "/" then
        local path = resolve(name)
        if path:find("[%*%?%[]") then
            local dir, pat = path:match("^(.*)/([^/]*)$")
            local lua_pat = "^" .. pat:gsub("%.", "%%."):gsub("%*", ".*"):gsub("%?", ".") .. "$"
            local files = {}
            local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
            for f in p:lines() do
                if f:match(lua_pat) and f:match("%.lua$") then files[#files + 1] = dir .. "/" .. f end
            end
            p:close()
            table.sort(files)
            if #files == 0 then problems[#problems + 1] = "require('" .. name .. "'): no files matched" end
            local results = {}
            for i, f in ipairs(files) do results[i] = load_file(f) or {} end -- each file isolated, like Hyprland
            loaded[name] = results
            return results
        end
        if not path:match("%.lua$") then path = path .. ".lua" end
        local res = load_file(path)
        loaded[name] = res
        return res
    end
    problems[#problems + 1] = "require('" .. name .. "'): only explicit ./ or / paths are supported by this checker"
end

---------------------------------------------------------------------------- run config
load_file(main_path)

---------------------------------------------------------------------------- monitor policy test
local function fake_monitor(name, modes)
    local list = {}
    for _, m in ipairs(modes) do
        list[#list + 1] = { width = m[1], height = m[2], refresh_rate = m[3], preferred = m[4] or false }
    end
    return { name = name, available_modes = list }
end

local cases = {
    { "HDMI-A-1", { { 3840, 2160, 30.0, true }, { 1920, 1080, 60.0 }, { 1280, 720, 60.0 } }, nil },
    { "HDMI-A-2", { { 1280, 720, 59.94, true }, { 1024, 768, 60.0 } }, "1280x720@60" },
    { "HDMI-A-3", { { 1024, 768, 60.0, true } }, "preferred" },
}
local handlers = calls.on["monitor.added"] or {}
if #handlers > 0 then
    for _, c in ipairs(cases) do
        local before = #calls.monitor
        for _, h in ipairs(handlers) do
            local ok, err = pcall(h, fake_monitor(c[1], c[2]))
            if not ok then problems[#problems + 1] = "monitor.added handler crashed for " .. c[1] .. ": " .. tostring(err) end
        end
        local added = calls.monitor[before + 1]
        local got = added and added.mode or nil
        if got ~= c[3] then
            problems[#problems + 1] = string.format("monitor policy: %s expected %s, got %s", c[1], tostring(c[3] or "no override (1080p rule)"), tostring(got or "no override"))
        else
            print(string.format("  monitor policy ok: %-8s -> %s", c[1], c[3] or "1920x1080@60 (base rule)"))
        end
    end
end

---------------------------------------------------------------------------- report
if #problems == 0 then
    print("hl_api_check: OK (" .. main_path .. " vs " .. stub_path .. ")")
    os.exit(0)
end
for _, p in ipairs(problems) do io.stderr:write("hl_api_check: " .. p .. "\n") end
os.exit(1)
