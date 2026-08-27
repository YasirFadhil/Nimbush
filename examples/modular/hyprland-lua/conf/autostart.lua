-- ══════════════════════════════════════════════════════════════════════════════
--  Autostart Daemons & Background Services (~/.config/hypr/conf/autostart.lua)
-- ══════════════════════════════════════════════════════════════════════════════

hl.on("hyprland.start", function ()
    -- Polkit Authentication Agent
    hl.exec_cmd("systemctl enable --now --user hyprpolkitagent")

    -- Clipboard History Daemons
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")

    -- Default wallpaper fallback (swww is managed automatically by Quickshell)
    -- hl.exec_cmd("swww-daemon")
end)
