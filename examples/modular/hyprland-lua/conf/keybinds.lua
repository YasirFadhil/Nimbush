-- ══════════════════════════════════════════════════════════════════════════════
--  Keybindings & Shortcuts (~/.config/hypr/conf/keybinds.lua)
-- ══════════════════════════════════════════════════════════════════════════════

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "nautilus"
local menu = "wofi --show drun"

-- ── Application Launchers ────────────────────────────────────────────────────
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal), { repeating = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))

-- ── Window Management ────────────────────────────────────────────────────────
hl.bind(mainMod .. " + Q",         hl.dsp.window.close(), { repeating = true })
hl.bind(mainMod .. " + ALT + F",   hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + J",         hl.dsp.layout("togglesplit"))

-- ── Window Focus & Movement ──────────────────────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }),  { repeating = true })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { repeating = true })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }),    { repeating = true })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }),  { repeating = true })

hl.bind(mainMod .. " + h",     hl.dsp.focus({ direction = "left" }),  { repeating = true })
hl.bind(mainMod .. " + l",     hl.dsp.focus({ direction = "right" }), { repeating = true })
hl.bind(mainMod .. " + k",     hl.dsp.focus({ direction = "up" }),    { repeating = true })
hl.bind(mainMod .. " + j",     hl.dsp.focus({ direction = "down" }),  { repeating = true })

-- ── Column Layout Swapping ───────────────────────────────────────────────────
hl.bind(mainMod .. " + period", hl.dsp.layout("swapcol r"))
hl.bind(mainMod .. " + comma",  hl.dsp.layout("swapcol l"))

-- ── Workspace Navigation (1-10) ──────────────────────────────────────────────
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- ── Mouse Window Drag & Resize ───────────────────────────────────────────────
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Screenshots (Grim + Slurp + Swappy + Quickshell Notification) ─────────────
hl.bind("print",               hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh full"),   { locked = true })
hl.bind("SHIFT + print",       hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh region"), { locked = true })
hl.bind(mainMod .. " + print", hl.dsp.exec_cmd("~/.config/quickshell/scripts/screenshot.sh window"), { locked = true })

-- ── Multimedia & Volume Control (WirePlumber / Brightnessctl) ─────────────────
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"),   { locked = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),          { locked = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),        { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set +5%"),                             { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"),                             { locked = true })
