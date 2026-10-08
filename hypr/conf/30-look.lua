-- Flat, cheap look: thin solid borders, small gaps, no gradients (a gradient border is a shader per window).

hl.config({
    general = {
        gaps_in     = 2,
        gaps_out    = 4,
        border_size = 1,
        layout      = "dwindle",
        col = {
            active_border   = "rgb(d79921)",
            inactive_border = "rgb(3c3836)",
        },
        resize_on_border = false,
        allow_tearing    = false,
    },

    dwindle = {
        preserve_split = true,
    },
})
