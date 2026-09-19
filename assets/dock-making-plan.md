# Nimbush Dock — Implementation Plan

Dock component for Nimbush (Quickshell macOS-inspired DE), showing pinned + running apps.

## 1. Window & Layout

- New `PanelWindow`, anchored to bottom.
- `exclusiveZone: 0` initially (don't reserve space / push other windows — revisit if auto-hide is skipped).
- Row layout via `Repeater` inside a `RowLayout`/`Row`; one delegate per app icon.
- Reuse existing blur/liquid-glass approximation from Settings/Control Center components for the dock background.

## 2. Data Model — Pinned vs Running Apps

- **Pinned apps**: stored in `Settings.qml`, persisted to `~/.config/quickshell/config/settings.json` (same debounced `Process` write pattern already used for accent/radius/blur).
- **Running apps**: need a toplevel tracker. Two options:
  1. Quickshell's `Wayland` module / `wlr-foreign-toplevel-management` protocol (if exposed) — cleaner, protocol-native.
  2. Hyprland event socket (`openwindow` / `closewindow` / `activewindow` events) — more realtime than polling `hyprctl clients -j`, and matches existing Hyprland-centric approach used elsewhere (IpcHandler via `hl.exec_cmd`).
- Merge pinned + running into a single list model:
  - Running app that's also pinned → single icon + running indicator dot.
  - Running app not pinned → shows temporarily, disappears when closed.
  - Pinned app not running → shows normally, click launches it.
- Matching app instances to icons: resolve by app class / `.desktop` id, reusing lookup logic from `Applications.qml` (`DesktopEntries`).

## 3. Interactions (macOS-style)

- **Hover magnification**: top-level `MouseArea` tracking `mouseX`; each icon delegate computes `scale` from distance to cursor, animated.
- **Click behavior**:
  - Running → focus window (`hyprctl dispatch focuswindow`).
  - Not running → launch via existing launcher logic.
- **Bounce animation** on new app open (optional, nice-to-have).
- **Running indicator**: small dot under icon, reflects toplevel count for that app.

## 4. Auto-Hide (optional)

- Reveal-on-hover at bottom edge, animate `y` / `anchors.bottomMargin`.
- Given known limitation (QML can't animate closing once `visible: false`, per Control Center experience), prefer a persistent thin strip (2–4px) that's always present and expands on hover, instead of full show/hide toggling.

## 5. Drag-to-Reorder (Pinned Apps)

- `DelegateModel` + `DragHandler`, standard Quickshell/QML reorder pattern.
- Persist new order back to `Settings.qml` / `settings.json`.

## Suggested Build Order

1. Data model first — pinned list + toplevel tracking (Wayland protocol vs Hyprland socket). This is the highest-risk / most debug-heavy part, especially app-class matching for icons.
2. Static UI/layout — row of icons, background, basic click-to-launch/focus.
3. Polish — hover magnification, bounce, running indicators, drag reorder, auto-hide.

## Open Decisions

- [ ] Toplevel tracking: native Wayland protocol vs Hyprland event socket.
- [ ] Auto-hide vs always-visible thin strip.
- [ ] Whether bounce-on-launch animation is worth the complexity.
