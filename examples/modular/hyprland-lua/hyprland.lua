-- ══════════════════════════════════════════════════════════════════════════════
--  Hyprland Lua Modular Configuration (~/.config/hypr/hyprland.lua)
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 1. Monitors ──────────────────────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({ name = "", modeline = "preferred,auto,1" })

-- ── 2. Environment Variables ─────────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
hl.env({
    XCURSOR_SIZE        = 24,
    HYPRCURSOR_SIZE     = 24,
    XDG_CURRENT_DESKTOP = "Hyprland",
    XDG_SESSION_TYPE    = "wayland",
    XDG_SESSION_DESKTOP = "Hyprland",
    QT_QPA_PLATFORM     = "wayland;xcb",
    GDK_BACKEND         = "wayland,x11,*",
})

-- ── 3. Look and Feel ─────────────────────────────────────────────────────────
-- https://wiki.hypr.land/Configuring/Basics/Variables/
hl.general({
    gaps_in             = 5,
    gaps_out            = 10,
    border_size         = 2,
    "col.active_border"   = "rgba(89b4faee) rgba(cba6f7ee) 45deg",
    "col.inactive_border" = "rgba(313244aa)",
    resize_on_border    = true,
    allow_tearing       = false,
    layout              = "dwindle",
})

hl.decoration({
    rounding            = 10,
    active_opacity      = 1.0,
    inactive_opacity    = 0.95,
    shadow = {
        enabled = true,
        range   = 15,
        render_power = 3,
        color   = "rgba(181825ee)",
    },
    blur = {
        enabled = true,
        size    = 6,
        passes  = 3,
        new_optimizations = true,
        xray    = false,
    },
})

-- ── 4. Animations ────────────────────────────────────────────────────────────
hl.animation({ leaf = "windows",   enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "layers",    enabled = true, speed = 4, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",      enabled = true, speed = 3 })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "easeOutQuint", style = "slide" })

-- ── 5. Layouts & Input ───────────────────────────────────────────────────────
hl.dwindle({
    pseudotile     = true,
    preserve_split = true,
})

hl.config({
    scrolling = {
        column_width             = 0.89,
        fullscreen_on_one_column = false,
    },
})

hl.input({
    kb_layout     = "us",
    follow_mouse  = 1,
    sensitivity   = 0,
    touchpad = {
        natural_scroll = true,
    },
})

-- ── 6. Load Modular Configuration Files ──────────────────────────────────────
local home = os.getenv("HOME") or ""
local confDir = home .. "/.config/hypr/conf"

local function load_conf(module_name)
    local module_path = confDir .. "/" .. module_name .. ".lua"
    local f = io.open(module_path, "r")
    if f then
        f:close()
        dofile(module_path)
    end
end

-- Load separated modules
load_conf("autostart")
load_conf("keybinds")
load_conf("rules")
load_conf("quickshell")
