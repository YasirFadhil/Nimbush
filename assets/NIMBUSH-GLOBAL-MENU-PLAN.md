# Nimbush Global Application Menu

> **Status:** Design proposal  
> **Target:** Nimbush on NixOS + Hyprland + Quickshell  
> **Date:** 22 November 2026  
> **Implementation status:** Not implemented. This document defines the proposed architecture and delivery plan.

## 1. Overview

Build a macOS-inspired global application menu for Nimbush. The menu bar should display the **real menu of the currently focused application** (for example `File`, `Edit`, `View`, `Tools`, and `Help`) in the top bar. Selecting a menu item must invoke the corresponding action in the original application.

This must not be a decorative row of hard-coded labels. If an application does not expose a usable accessible menu, Nimbush must show an honest unsupported/empty state or a separately identified fallback. It must never pretend that a fallback item is the application's native menu.

### Desired user experience

- The left side of the transparent menu bar shows the Nimbush/system icon, the focused application's name, and that application's available menu entries.
- The Dynamic Island remains centered and is not modified by this feature.
- The existing right-side system indicators and Control Center remain in place.
- Clicking a menu heading opens a native-looking Quickshell popup.
- Selecting an item, opening a submenu, checking a toggle, or invoking a shortcut must affect the original application.
- When focus changes, the menu changes to the newly focused application without requiring a shell restart or a manual refresh.
- When the focused application has no exportable menu, the menu area should collapse cleanly or show a clearly labelled fallback state.

## 2. Scope and non-goals

### In scope

1. Detect the focused Hyprland window and identify its PID, app class, title, and window address.
2. Read application menu structures through the Linux accessibility stack (AT-SPI).
3. Convert the accessible tree into a stable, serializable menu snapshot.
4. Render the snapshot in Quickshell/QML.
5. Forward user actions back to the original accessible menu item.
6. Package the bridge, runtime dependencies, environment variables, and user service declaratively with Nix/Home Manager.
7. Preserve Nimbush's current bar, system tray, and Dynamic Island behavior.

### Explicitly out of scope for the first release

- Replacing or hiding the application's own in-window menu bar.
- Guaranteeing a real menu for every Linux application. Some applications expose no usable menu through AT-SPI.
- Implementing a custom menu system inside every application.
- Depending on the legacy `com.canonical.AppMenu.Registrar` / DBusMenu pipeline as the primary backend.
- Implementing a fake `File / Edit / View` menu when the application does not expose one.
- Changing Dynamic Island's animation, media state, or expand/collapse behavior.
- Supporting Niri, Sway, KDE, or COSMIC as focus providers in the first Hyprland-focused release.

## 3. Technical direction

### Use AT-SPI as the menu source

The recommended starting point is **AT-SPI**, the Linux accessibility interface. Qt and GTK applications can expose accessible menu and menu-item objects through the accessibility bus. The bridge can inspect these objects and invoke their accessible actions.

A useful implementation reference is [`yolo-labz/noctalia-appmenu`](https://github.com/yolo-labz/noctalia-appmenu). Its newer architecture uses a Rust sidecar, AT-SPI, a published active-menu snapshot, and a Quickshell/QML widget. It documents Qt6 as the primary path and GTK as a supported-but-not-uniform path.

However, that project currently uses Niri for focused-window tracking. Its focus-tracker abstraction is a useful reference, but its Niri integration is **not** a drop-in solution for Nimbush on Hyprland. Nimbush must implement its own Hyprland focus provider.

### Why not build on the legacy DBusMenu registrar first?

The older AppMenu approach relies on applications exporting a `com.canonical.dbusmenu` object and registering window/menu information with a registrar. The historical implementation notes that the window registration mechanism is problematic outside the compositor integrations that implement the required AppMenu manager protocol. The newer reference project moved to AT-SPI for this reason.

Quickshell's `DBusMenuHandle` is also not a generic QML constructor for an arbitrary application's `(bus name, object path)`. Nimbush should therefore normalize the application menu in its own bridge instead of coupling the QML widget directly to each application's DBusMenu object.

## 4. Proposed architecture

```text
┌─────────────────────────────────────────────────────┐
│ Applications                                         │
│ Qt6 / GTK apps that expose an accessible menu        │
└───────────────────────┬─────────────────────────────┘
                        │ AT-SPI accessibility bus
                        ▼
┌─────────────────────────────────────────────────────┐
│ nimbush-appmenu-bridge (Rust, user service)           │
│                                                     │
│  ┌──────────────────┐   ┌────────────────────────┐  │
│  │ Hyprland Focus   │──▶│ Active Window Resolver │  │
│  │ Provider         │   │ address → PID/app ID   │  │
│  └──────────────────┘   └───────────┬────────────┘  │
│                                    │               │
│                                    ▼               │
│  ┌──────────────────┐   ┌────────────────────────┐  │
│  │ AT-SPI Connector │──▶│ Menu Tree Extractor    │  │
│  │ + object cache   │   │ roles, labels, states  │  │
│  └──────────────────┘   └───────────┬────────────┘  │
│                                    │               │
│                                    ▼               │
│                       ┌────────────────────────┐   │
│                       │ Snapshot + Action API │   │
│                       │ generation + tokens   │   │
│                       └───────────┬────────────┘   │
└───────────────────────────────────┼─────────────────┘
                                    │
                         JSON snapshot / local IPC
                                    │
                                    ▼
┌─────────────────────────────────────────────────────┐
│ Quickshell / Nimbush                                 │
│                                                     │
│ AppMenu.qml → MenuPopup.qml → recursive MenuItem    │
│                                                     │
│ Existing transparent bar | Dynamic Island | Tray     │
└─────────────────────────────────────────────────────┘
```

### Component responsibilities

| Component | Responsibility |
|---|---|
| `HyprlandFocusProvider` | Subscribe to Hyprland focus events and request the authoritative active-window JSON. |
| `ActiveWindowResolver` | Resolve window address, PID, class/app ID, and title; reject stale results after a focus change. |
| `AtSpiConnector` | Connect to the session accessibility bus and locate the accessible application for the focused PID. |
| `MenuTreeExtractor` | Find the menu-bar node and recursively extract menu entries, submenus, states, labels, and action references. |
| `SnapshotPublisher` | Publish the current normalized menu and its generation/version. |
| `ActionDispatcher` | Resolve short-lived opaque tokens and call the associated AT-SPI action. |
| `AppMenu.qml` | Display the focused application's menu headings in the top bar. |
| `MenuPopup.qml` | Render nested menus, separators, disabled entries, checks, radio states, and shortcuts. |

## 5. Focus tracking on Hyprland

Hyprland exposes two IPC sockets:

- `.socket.sock` for request/response commands.
- `.socket2.sock` for a newline-delimited event stream.

The bridge should use the event socket to know **when** focus changes, then query the command socket for the current active-window JSON. Do not try to derive a PID from the `activewindow` event payload: that event contains the window class and title, while `activewindowv2` identifies the window by address.

### Proposed flow

1. On bridge startup, query `hyprctl activewindow -j` to establish the initial focused window.
2. Connect to `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`.
3. Listen for `activewindowv2` and `activewindow` events.
4. On either event, query `hyprctl activewindow -j` and read the current `address`, `pid`, `class`, and `title` fields.
5. Increment a monotonically increasing `generation` value.
6. Resolve the accessible application for that PID and extract its menu.
7. Before publishing the result, verify that its generation/window address is still current. Discard late responses from an application that lost focus while extraction was in progress.
8. On no focused application, a desktop surface, or a Nimbush-owned surface, publish an empty menu state.

A short debounce (initial target: 75–150 ms) may be applied to avoid repeated extraction during rapid focus transitions. This value must be measured rather than treated as fixed.

## 6. Menu extraction and action model

### Menu snapshot

The bridge should publish a versioned JSON document. A possible schema:

```json
{
  "schemaVersion": 1,
  "generation": 42,
  "source": "atspi",
  "application": {
    "pid": 1234,
    "appId": "org.example.Editor",
    "title": "document.txt - Editor"
  },
  "menus": [
    {
      "id": "menu-file",
      "label": "File",
      "enabled": true,
      "children": [
        {
          "id": "item-open",
          "token": "opaque-short-lived-token",
          "role": "item",
          "label": "Open…",
          "enabled": true,
          "checked": false,
          "shortcut": "Ctrl+O",
          "children": []
        }
      ]
    }
  ]
}
```

This is an illustrative contract, not a final schema. The implementation should add only fields verified to be available from the accessible object.

### Required item data

- Human-readable label.
- Role: menu, menu item, checkbox item, radio item, separator, or another explicitly supported role.
- Enabled/disabled state.
- Checked/unchecked state where relevant.
- Shortcut text when exposed by the application.
- Children for submenus.
- Opaque action token for actionable nodes.

Preserve the original menu hierarchy. Do not infer actions by parsing labels such as `Open`, `Save`, or `Quit`.

### Invoking an action

1. QML sends the item token together with the snapshot generation.
2. The bridge verifies that the generation is still current and that the token belongs to the active menu.
3. The bridge resolves the token to its live AT-SPI accessible object and calls the supported accessible action (for example, `DoAction`).
4. The bridge publishes a refreshed snapshot if the menu state or application focus changed.
5. If the token is stale, return a controlled error and refresh the menu. Never call an action against an object from a previous focused window.

Menu labels, window titles, application names, and accessibility metadata are untrusted data. They must never be interpreted as shell commands or executable paths.

### Submenus and dynamic menus

Submenus may be lazy-loaded or expose different children when opened. The prototype must test whether a submenu can be read without activating it. If not, the bridge should support an explicit `ExpandSubmenu(token, generation)` request, refresh the accessible tree, and publish the new children.

The design must also handle:

- Menu items disabled by application state.
- Checked and radio items.
- Separators and nested submenus.
- Dynamic menus such as `Recent Files`.
- Applications that recreate accessible nodes after each popup.
- Application closure while a popup is open.
- Focus changing while a popup is open.

## 7. Quickshell / QML integration

### Proposed components

Add a dedicated component rather than expanding `WorkspaceIndicator.qml` or `StatusTray.qml` with menu extraction logic.

```text
modules/bar/components/
├── AppMenu.qml
├── AppMenuPopup.qml
├── AppMenuItem.qml
└── ...existing bar components
```

The parent bar should position `AppMenu` on the **left side**, following the Nimbush identity icon and active application name. The Dynamic Island remains centered. The existing right-side status tray stays independent.

### Visual behavior

- Transparent by default; no full-width background or divider.
- Compact text menu headings with spacing similar to macOS.
- A small contextual glass highlight on hover/active state.
- Popup surfaces use the existing Nimbush glass/theme tokens.
- Popups open below the relevant heading and remain within screen bounds.
- Submenus open beside their parent item, with a fallback direction near screen edges.
- Keyboard navigation should support Up/Down, Left/Right, Enter/Space, Escape, and mnemonic/shortcut display where available.
- Respect dark/light theme and the existing font configuration.
- Do not change the Dynamic Island component or its animation timing.

### State handling

QML should render only the normalized snapshot. It should not traverse AT-SPI or communicate with application-specific menu objects directly.

The prototype must settle the most reliable Quickshell transport. Preferred options:

1. **Versioned JSON snapshot + local D-Bus action API.** The bridge publishes an atomic JSON snapshot for menu state and provides a small session-bus API for actions and refresh requests.
2. If the installed Quickshell version can consume the fixed D-Bus object cleanly, publish state changes over D-Bus as well and avoid file polling.

The transport must be event-driven. Do not introduce a fast polling loop in QML.

## 8. NixOS and Home Manager integration

### System-level prerequisite

Enable the AT-SPI accessibility bus in the NixOS configuration. The reference implementation documents:

```nix
services.gnome.at-spi2-core.enable = true;
```

Before adding it to Nimbush, verify the option against the pinned nixpkgs revision and ensure the user session exposes the accessibility D-Bus services.

### Application environment

Qt applications need accessibility enabled in their environment. The reference implementation uses:

```nix
home.sessionVariables = {
  QT_ACCESSIBILITY = "1";
};
```

After changing session variables, fully restart the affected applications (and log out/in if the desktop session does not inherit the new environment). GTK accessibility behavior must be verified with the actual GTK versions and applications in the user's NixOS generation; do not blindly add toolkit variables without testing them.

### User service

Package the Rust bridge through the Nimbush flake and run it as a hardened `systemd --user` service, tied to the graphical session. The service should:

- Restart on failure with a bounded restart policy.
- Run as the logged-in user, not root.
- Use only the user's session D-Bus and Hyprland IPC sockets.
- Write transient state under `$XDG_RUNTIME_DIR` (or another user-owned runtime directory).
- Log concise diagnostics through journald.
- Stop cleanly when the graphical session ends.

The bridge should be optional through a Nix/Home Manager option, for example `programs.nimbush.appmenu.enable`, rather than being unconditionally started on hosts that do not use Quickshell.

## 9. Compatibility expectations

Support must be measured per toolkit and application, not assumed from the toolkit name alone.

| Application class | Initial expectation | Notes |
|---|---|---|
| Qt6 applications | Primary target | Enable `QT_ACCESSIBILITY=1`; first prototype should use a known Qt6 app with a conventional menu bar. |
| GTK3 applications | Test after Qt6 | Depends on the application's exported accessible tree and menu structure. |
| GTK4 applications | Experimental | Some apps use popover menu bars; a closed menu can expose no useful children. |
| Qt5 / GTK under XWayland | Candidate | AT-SPI is toolkit-oriented, but window/PID association and actions still need tests. |
| Electron / Chromium | Limited | May require an accessibility launch flag; do not promise a native menu by default. |
| Firefox / Thunderbird | Experimental | Accessibility menu behavior can be lazy or app-specific; validate directly under Hyprland. |
| libcosmic / Iced apps | Unsupported until proven | Do not claim support without an upstream accessibility export. |

The Noctalia reference's compatibility table is evidence for the tested application/toolkit combinations in that project, not a guarantee for Nimbush or Hyprland. In particular, its focus provider is currently Niri-specific.

### Fallback policy

For the first version, prefer an empty/collapsed native menu area with the app name still visible when no native menu is found.

A second-stage fallback may provide clearly separated desktop/window actions (for example, app-specific `.desktop` actions and safe Hyprland window commands). It must be marked internally as `source = "desktop-fallback"` and visually distinguished from a real application menu. It must not invent `File`, `Edit`, or `View` entries.

## 10. Proposed repository layout

This is a proposed layout. Adjust names to match the current Nimbush module conventions during implementation.

```text
Nimbush/
├── modules/
│   └── bar/
│       └── components/
│           ├── AppMenu.qml
│           ├── AppMenuPopup.qml
│           └── AppMenuItem.qml
├── services/
│   └── appmenu/
│       ├── default.nix
│       ├── service.nix
│       └── config.nix
├── packages/
│   └── nimbush-appmenu-bridge/
│       ├── default.nix
│       └── source/                 # Rust crate, or separate bridge/ directory
├── bridge/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs
│   │   ├── focus/
│   │   │   └── hyprland.rs
│   │   ├── atspi/
│   │   │   ├── connection.rs
│   │   │   ├── application.rs
│   │   │   ├── menu_tree.rs
│   │   │   └── actions.rs
│   │   ├── snapshot.rs
│   │   └── ipc.rs
│   └── tests/
│       ├── fixtures/
│       ├── focus_tests.rs
│       ├── snapshot_tests.rs
│       └── atspi_integration.rs
└── docs/
    └── GLOBAL-MENU.md
```

The Rust crate can live inside `packages/` or `bridge/`; choose one canonical location before implementation. Avoid maintaining duplicate source trees.

## 11. Implementation phases

### Phase 0 — Audit and proof of concept

- Record the current NixOS/nixpkgs revision, Hyprland version, Quickshell version, and actual Nimbush directory structure.
- Verify AT-SPI service availability on the current session.
- Pick one known Qt6 application with a conventional menu bar (for example Kate, Okular, or Krita).
- Confirm its menu-bar and menu-item objects are visible over AT-SPI.
- Confirm a menu-item accessible action can be invoked without touching the in-window menu manually.
- Decide the snapshot/action transport after a small QML/bridge test.

**Exit criteria:** one focused Qt6 app can be identified by PID, its menu can be read, and a harmless menu action can be invoked through AT-SPI.

### Phase 1 — Hyprland focus provider

- Implement the `.socket2.sock` event listener.
- Use `activewindowv2` as a focus-change signal and query `hyprctl activewindow -j` for the active window's PID and metadata.
- Handle initial focus, no active window, app close, rapid switching, and service reconnects.
- Add generation checks to prevent stale menu results.

**Exit criteria:** bridge logs the correct focused PID/app ID and never publishes an older window after a rapid focus switch.

### Phase 2 — AT-SPI menu bridge

- Connect to the session accessibility bus.
- Locate the accessible application by PID.
- Find its menu bar and recursively extract the supported menu roles.
- Generate stable-per-snapshot opaque action tokens.
- Implement action invocation and submenu refresh.
- Publish a versioned active-menu snapshot.

**Exit criteria:** Qt6 menu tree renders correctly in a diagnostic JSON/CLI view and a leaf action reaches the application.

### Phase 3 — Quickshell UI

- Build `AppMenu.qml`, `AppMenuPopup.qml`, and `AppMenuItem.qml` using fixture JSON before connecting the live bridge.
- Implement submenus, keyboard navigation, checked/disabled state, separators, hover, focus, dismissal, and screen-edge positioning.
- Add the widget to the left side of the existing bar.
- Keep Dynamic Island and StatusTray independent.

**Exit criteria:** fixture-based UI passes interaction checks and does not regress existing bar layout.

### Phase 4 — Live integration and declarative packaging

- Connect QML to the bridge snapshot and action API.
- Add the bridge package to the Nimbush flake.
- Add the optional Home Manager user service.
- Enable AT-SPI at the NixOS layer.
- Export `QT_ACCESSIBILITY=1` for Qt apps.
- Add service status and logs to the README/troubleshooting notes.

**Exit criteria:** after `nh os switch` and a Quickshell restart, focusing the test Qt app updates the menu automatically and actions work.

### Phase 5 — Toolkit compatibility and fallback

- Test at least one GTK3 and one GTK4 app.
- Test XWayland if used.
- Test Firefox and a Chromium/Electron app separately.
- Document unsupported apps accurately.
- Only then consider an explicitly labelled desktop/window fallback.

**Exit criteria:** compatibility table is based on repeatable tests on the user's actual machine.

## 12. Testing and acceptance criteria

### Functional tests

- [ ] Starting the bridge with no focused application produces a clean empty state.
- [ ] Focusing a supported app changes the app name and menu within a measured, acceptable delay.
- [ ] Switching rapidly between two apps never leaves the previous app's menu visible.
- [ ] A top-level menu opens at the correct position.
- [ ] Submenus open, close, and remain navigable.
- [ ] Clicking a leaf item invokes the action in the original application.
- [ ] Disabled, checked, radio, and separator states render correctly.
- [ ] Dynamic menu changes are reflected without restarting Quickshell.
- [ ] Closing the app clears the menu and invalidates its action tokens.
- [ ] A stale token/generation is rejected safely.
- [ ] Applications without a usable menu do not display fake native entries.

### Regression tests

- [ ] Dynamic Island remains centered and unchanged.
- [ ] Dynamic Island media/expanded/compact transitions remain functional.
- [ ] Existing system tray popup and overflow still work.
- [ ] Control Center and clock/calendar still open correctly.
- [ ] Menu bar stays transparent over the wallpaper.
- [ ] Bar layout works at the Chromebook's 1366×768 resolution and on larger displays.
- [ ] No excessive CPU use while idle; no tight polling loop.
- [ ] Restarting Quickshell or the bridge recovers the active menu state.

### Observability

Use structured log prefixes such as `[appmenu::focus]`, `[appmenu::atspi]`, `[appmenu::snapshot]`, and `[appmenu::action]`. Log state transitions and errors, but avoid dumping the entire accessible tree or sensitive document contents by default.

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Hyprland event has no PID | Query `activewindow -j` after focus events; use the window address and generation to guard races. |
| App does not export a menubar | Show no native menu and record unsupported status; consider a labelled fallback later. |
| AT-SPI nodes are lazy or recreated | Keep short-lived references, invalidate on focus/menu changes, and test submenu expansion. |
| Focus changes while menu is open | Close popup and reject old-generation actions immediately. |
| QML/bridge transport is awkward | Prove the transport in Phase 0 before committing to the full UI. |
| Toolkit environment variables are not inherited | Verify each process environment and fully restart affected apps/session. |
| High idle resource use | Use event streams and change-driven snapshots, not rapid polling. |
| Accessible labels contain untrusted content | Treat all strings as data; never pass them to a shell. |
| Quickshell or AT-SPI API changes | Pin/record the relevant versions and keep the bridge behind a small internal API. |

## 14. Decisions to make during the prototype

1. Which Rust AT-SPI client library is sufficiently maintained for the pinned nixpkgs/toolchain? If no suitable abstraction exists, use a small, tested D-Bus implementation rather than coupling the UI to undocumented APIs.
2. Should the QML state channel be a watched JSON snapshot, a D-Bus signal/property, or a hybrid? Prefer an event-driven approach; decide based on a real Quickshell prototype.
3. How are lazy submenus represented by the selected AT-SPI library? Test this before finalizing the menu schema.
4. Which application should be the first acceptance target? Recommended: a Qt6 app with a conventional menubar, such as Kate, Okular, or Krita.
5. Should an optional desktop/window fallback be included in v1, or should v1 remain native-menu-only? Recommended: native-menu-only for the first release.

## 15. External references

- [Nimbush reference implementation: noctalia-appmenu](https://github.com/yolo-labz/noctalia-appmenu) — Rust sidecar, AT-SPI extraction, active menu snapshot, QML widget, compatibility notes. **Use as an architectural reference only; its documented focus integration is Niri-specific.**
- [Noctalia AppMenu README / compatibility and installation](https://github.com/yolo-labz/noctalia-appmenu#readme) — AT-SPI setup, Qt accessibility environment, supported toolkit notes, and known limitations.
- [Hyprland IPC documentation](https://wiki.hypr.land/ipc/) — command and event sockets, including `activewindow` and `activewindowv2` events.
- [AT-SPI2 overview (freedesktop)](https://wiki.freedesktop.org/www/Accessibility/AT-SPI2/) — accessibility objects are exposed over D-Bus; the overview notes that AT-SPI2 also works on Wayland.
- [AT-SPI D-Bus interface reference (Ubuntu Desktop)](https://ubuntu.com/desktop/docs/en/latest/reference/accessibility/dbus/) — the Accessible, Action, Application, and related interfaces used by accessibility clients.
- [Noctalia AppMenu historical DBusMenu pipeline](https://github.com/yolo-labz/noctalia-appmenu/blob/main/docs/architecture/dbusmenu.md) — rationale for not choosing the legacy registrar pipeline as the first implementation path.

---

## Recommended first milestone

Do **not** begin by styling the QML popup. First prove this round trip with one Qt6 app:

1. Hyprland tells the bridge which window is focused.
2. The bridge resolves that window's PID.
3. AT-SPI exposes the app's menu tree.
4. The bridge can invoke one harmless menu action.

Once this works reliably, the rest becomes a contained UI and packaging task rather than guesswork.
