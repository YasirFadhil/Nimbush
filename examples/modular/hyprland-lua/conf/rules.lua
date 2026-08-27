-- ══════════════════════════════════════════════════════════════════════════════
--  Window & Workspace Rules (~/.config/hypr/conf/rules.lua)
-- ══════════════════════════════════════════════════════════════════════════════

-- Suppress maximize events from applications
hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Picture-in-Picture and Dialog floating rules
hl.window_rule({
    name  = "pip-float",
    match = { title = "^(Picture-in-Picture|Picture in picture)$" },
    float = true,
    pin   = true,
})

hl.window_rule({
    name  = "dialog-float",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|swappy)" },
    float = true,
})
