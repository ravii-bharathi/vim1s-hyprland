-- Low-resource tuning for a single-core Mali-G31 sharing LPDDR4 with 4x Cortex-A35.
-- Every key below exists in Hyprland 0.56.2 (checked against src/config/values/ConfigValues.cpp).
--
-- Not set on purpose:
--   debug.vfr                  VFR is already ON by default; upstream says only touch it when debugging.
--   render.direct_scanout      default 0 (off). Try 2 ("auto") once the S4 KMS driver is stable:
--                              it lets fullscreen clients skip compositing, but exercises plane/modifier paths.

hl.config({
    animations = {
        enabled = false,
    },

    decoration = {
        rounding     = 0,
        dim_inactive = false,
        shadow       = { enabled = false },
        glow         = { enabled = false },
        blur         = { enabled = false },
        motion_blur  = { enabled = false },
    },

    render = {
        cm_enabled            = false, -- skip colour-management shader passes (needs a restart to fully apply)
        use_fp16              = 0,     -- 0 = disable FP16 work buffers (default 2 = auto); halves buffer bandwidth
        new_render_scheduling = true,  -- upstream: "should improve FPS on underpowered devices" (default false)
    },

    xwayland = {
        enabled = false, -- package hard-depends on xorg-xwayland, but we never start it: saves RAM
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        force_default_wallpaper  = 0,
        background_color         = "rgb(1d2021)", -- solid colour drawn by the compositor: no wallpaper process
        enable_anr_dialog        = false,         -- slow board => false "not responding" dialogs; each is a GUI process
    },

    ecosystem = {
        no_update_news  = true, -- these popups launch extra GUI helpers
        no_donation_nag = true,
    },
})
