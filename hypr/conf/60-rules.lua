-- Window rules.

hl.window_rule({
    -- Apps asking to maximize themselves would fight the tiling layout.
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- The launcher's own windows (if any) and dialogs from portals float.
    name  = "float-dialogs",
    match = { title = "^(Open File|Save File|Confirm)" },
    float = true,
})
