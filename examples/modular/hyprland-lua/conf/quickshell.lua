-- ══════════════════════════════════════════════════════════════════════════════
--  Quickshell Desktop Environment Integration (~/.config/hypr/conf/quickshell.lua)
-- ══════════════════════════════════════════════════════════════════════════════

local mainMod = "SUPER"

-- ── 1. Autostart Quickshell Desktop Environment & Clipboard Daemons ─────────
hl.on("hyprland.start", function ()
    hl.exec_cmd("qs")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

-- ── 2. Quickshell IPC Keybindings ─────────────────────────────────────────────
hl.bind(mainMod .. " + SPACE",         hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + SHIFT + W",     hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))
hl.bind(mainMod .. " + SHIFT + E",     hl.dsp.exec_cmd("qs ipc call emoji toggle"))
hl.bind(mainMod .. " + V",             hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P",             hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + ALT + L",       hl.dsp.exec_cmd("qs ipc call lockscreen toggle"))
hl.bind(mainMod .. " + D",             hl.dsp.exec_cmd("qs ipc call dashboard toggle"))
hl.bind(mainMod .. " + N",             hl.dsp.exec_cmd("qs ipc call notifCenter toggle"))
hl.bind(mainMod .. " + C",             hl.dsp.exec_cmd("qs ipc call controlCenter toggle"))
hl.bind(mainMod .. " + B",             hl.dsp.exec_cmd("qs ipc call battery toggle"))

-- ── 3. Quickshell Layer Rules (Blur & Transparency) ───────────────────────────
hl.layer_rule({ match = { namespace = "quickshell:bar" },               blur = true })
hl.layer_rule({ match = { namespace = "quickshell:launcher" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:wallpaperselector" }, blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:emojipicker" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:clipboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:controlcenter" },     blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:notifcenter" },       blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:dashboard" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:calendar" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:hud" },               blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:traymenu" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:trayoverflow" },      blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:settings" },          blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:battery" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:volume" },            blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:welcome" },           blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:powermenu" },         blur = true, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "^quickshell:.*$" },              blur = true, ignore_alpha = 0 })
