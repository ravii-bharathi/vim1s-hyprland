-- Input. Applies to any USB/BT keyboard and mouse once the S4 USB nodes exist in the device tree.

hl.config({
    input = {
        kb_layout    = "us",
        kb_options   = "",
        repeat_rate  = 30,
        repeat_delay = 400,
        follow_mouse = 1,
        sensitivity  = 0,
    },
})
