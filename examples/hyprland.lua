-- Hyprland Lua Configuration (Hyprland 0.55+)
-- Place in ~/.config/hypr/hyprland.lua

local mainMod = "SUPER"

-- ── Autostart Quickshell ───────────────────────────────────────────────────
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs -c ~/.config/quickshell")
end)

-- ── Clipboard History Daemons ──────────────────────────────────────────────
hl.on("hyprland.start", function ()
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

-- ── Quickshell IPC Keybindings ─────────────────────────────────────────────
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + V",     hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",     hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",     hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",     hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))

-- ── Layer Rules (Blur & Transparency) ──────────────────────────────────────
hl.layer_rule({ match = { namespace = "quickshell:bar" },           blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },   blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },          blur = true, ignore_alpha = 0 })
