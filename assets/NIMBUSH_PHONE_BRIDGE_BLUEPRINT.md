# Nimbush Phone Bridge and Phone Hub Blueprint

**Purpose:** Implementation blueprint for a coding agent working in the existing Nimbush/Quickshell repository. This document is the source of truth for the next implementation. Prefer small, reviewed changes over a one-shot patcher.

> **Important:** This blueprint supersedes the earlier idea of running an automatic patcher. Do not run an earlier `apply-phone-bridge.py` patcher or blindly copy its code. Inspect the current repository first, implement the design in small stages, and review each diff before proceeding.

## 1. Project context

- Host OS: NixOS.
- Desktop compositor: Hyprland 0.56.
- Desktop shell: Quickshell with a custom QML shell and Dynamic Island.
- Main configuration repository on the user's machine: `~/.config/quickshell`.
- Main NixOS configuration repository: `~/.config/nixos`.
- Quickshell repository branch at planning time: `master`.
- Home Manager module: `~/.config/quickshell/nix/home-manager-module.nix`.
- Flake builds a Quickshell config package from `src = ./.;` and copies repository contents into `$out/share/quickshell`. It also has a config/development mode that points Quickshell at `~/.config/quickshell` when `cfg.package == null`. Inspect the current flake/module before assuming this behavior is unchanged.
- KDE Connect is already paired to the Android phone. The user has LocalSend and scrcpy installed. KDE Connect daemon is already managed by the user session and must remain the existing device integration layer.
- Current Android clipboard behavior is unchanged by this project: phone-to-laptop clipboard may require pressing the KDE Connect “Send Clipboard” tile on Android. Do not promise background clipboard sync or introduce Shizuku/root requirements as part of this work.

## 2. Goal

Create a single local backend for Nimbush's KDE Connect interactions, exposed to QML through one shared `PhoneBridge` singleton. Later, a Phone Hub UI can use that same backend for device status and phone-related actions.

The initial backend migration must centralize:

1. KDE Connect notification event watching.
2. Fetching devices and active KDE Connect notifications.
3. Sending inline replies to the phone.
4. Dismissing phone notifications from the desktop.
5. Sending files via KDE Connect.

`DeviceShare.qml` must continue to preserve its existing public API so the current Dynamic Island and other callers keep working. LocalSend and scrcpy remain separate tools. Invoke them only when relevant user actions request them; do not claim their executables or protocols are merged into KDE Connect.

## 3. Non-goals

- Do not redesign the visual shell or Dynamic Island during the backend migration.
- Do not replace or restart the KDE Connect daemon itself.
- Do not rewrite `Notifications.qml` wholesale. It is a large file with important notification-center behavior.
- Do not add network TCP listeners. IPC is local to the user's session.
- Do not require root, Shizuku, Android debugging permissions, or a new phone app.
- Do not remove LocalSend or scrcpy.
- Do not auto-run `nh-switch`, switch generations, restart the graphical session, or commit changes without the user's authorization.

## 4. Existing code that must be understood and preserved

### 4.1 `scripts/kdeconnect-helper.py`

This script already works as the compatibility layer around KDE Connect's user D-Bus API. It has these commands/functions:

- `watch` / `do_watch()`: streams newline-delimited JSON watcher events to stdout and launches `dbus-monitor` internally.
- `list` / `get_active_notifications()`: emits current phone notifications as JSON.
- `devices` / `get_devices()`: emits device information as JSON.
- `share --device DEVICE_ID --files PATH...` / `do_share()`.
- `reply --reply-id ID --notif-id ID --summary TEXT --body TEXT --message TEXT` / `do_reply()`.
- `dismiss --notif-id ID --summary TEXT --body TEXT` / `do_dismiss()`.

Read the complete current script and preserve its argument names and output shapes unless a change is necessary and documented. Do not duplicate its D-Bus logic in QML.

Observed watcher event shapes:

- Initial/periodic snapshot: `{"event":"sync","activeIds":[...],"notifications":[...]}`.
- A notification removal: `{"event":"removed","removedIds":[...],"activeIds":[...],"notifications":[...]}`.
- Clear-all notification event: `{"event":"all_removed", ...}`.

The helper may evolve. Verify the actual event payloads from the current repository before implementing the bridge.

### 4.2 `services/Notifications.qml`

Important existing behavior includes:

- `kdeHelperPath` points to `scripts/kdeconnect-helper.py`.
- A `Process` currently starts `[helperPath, "watch"]` and consumes its stdout with `SplitParser`.
- A restart timer restarts the watcher with exponential backoff.
- Watcher events call existing functions such as `syncKdeNotificationsWithActive(...)`, `removeKdeNotificationsByIds(...)`, and `removeAllKdeNotifications()`.
- `kdeLinkProc` runs `list` to link notifications with KDE Connect metadata/reply IDs.
- Separate `Process` objects run the helper's `reply` and `dismiss` commands.
- Native desktop notification actions, notification history, popup timers, grouping, app icon resolution, and inline-reply behavior must not regress.

Migrate only the KDE Connect transport first. Keep notification models, metadata matching, popup/history logic, native desktop notification handling, timer behavior, and public functions intact.

### 4.3 `services/DeviceShare.qml`

Keep the public API and its meaning compatible. Known members include:

- State: `kdeDevices`, `defaultDevice`, `hasKdeDevice`, `hasLocalSend`.
- Transfer feedback: `transferState`, `transferTargetName`, `transferFileCount`, `transferPreviewUrl`, `transferMessage`.
- Methods: `refreshKdeDevices()`, `cleanPaths(...)`, `extractPreview(...)`, `sendKdeConnect(...)`, `sendLocalSend(...)`, `sendAuto(...)`.
- It currently polls KDE Connect devices about every 15 seconds and starts helper processes for device listing and KDE Connect file sharing.
- LocalSend detection and the LocalSend launch path must remain functional.

Do not rename/remove these fields or methods without first searching all QML call sites and providing compatible aliases.

### 4.4 `services/qmldir`

This file registers the service singletons. Existing `Notifications` and `DeviceShare` singleton registrations must remain. Add `PhoneBridge` consistently with the current registration style, after checking the current file.

### 4.5 `nix/home-manager-module.nix` and `flake.nix`

The module already defines `programs.quickshell-shell.enableSystemdService` and a `systemd.user.services.quickshell-shell` unit near the end of the module. That service launches Quickshell from either the configured package or the live config directory.

Add a separate user service for Phone Bridge. Do not overload the existing Quickshell UI service or change the meaning/default of `enableSystemdService`. Confirm how scripts are installed in both package mode and config mode before selecting the service `ExecStart` path. A custom `cfg.package` must not silently break the Phone Bridge path.

## 5. Target architecture

```text
KDE Connect daemon (existing, unchanged)
                 |
                 | user D-Bus, busctl, dbus-monitor
                 v
Phone Bridge Python service (systemd --user)
  - owns exactly one KDE notification watcher
  - restarts the watcher on failure
  - executes device/list/share/reply/dismiss requests
  - streams newline-delimited JSON events and responses
                 |
                 | Unix domain socket in XDG_RUNTIME_DIR
                 v
PhoneBridge.qml singleton
  - connects/reconnects
  - parses JSON-line protocol
  - correlates request IDs to responses
  - exposes a small stable API to QML
             /             \
            v               v
 Notifications.qml     DeviceShare.qml
            \               /
             Future Phone Hub UI
```

The Python bridge should be independent of the Quickshell process. Restarting Quickshell must not restart the KDE Connect watcher. The service may be tied to the graphical user session through `graphical-session.target`, but it must not be a child process of Quickshell.

## 6. IPC transport and protocol

Use a Unix domain stream socket, normally below `$XDG_RUNTIME_DIR`, for example:

`$XDG_RUNTIME_DIR/nimbush-phone-bridge.sock`

The precise socket filename should be defined once in the design and kept identical in Python, QML, logs, and tests. Do not hardcode a per-user home directory. Prefer the environment supplied by the user session and handle a missing `XDG_RUNTIME_DIR` with an explicit, safe fallback or a clear startup error.

### Security and lifecycle

- Keep the socket private to the user. Create it with restrictive permissions, typically mode `0600`.
- Do not use TCP, expose the socket on the LAN, or log notification bodies/reply text.
- Handle stale socket files safely: detect whether another live service owns the socket before removing a stale path.
- Handle SIGTERM/SIGINT, close client connections, stop the watcher process group, wait for children, and remove the socket on shutdown.
- Bound incoming JSON-line size and reject malformed JSON without crashing the service.
- A watcher crash must be retried with backoff and logged to journald.
- Ensure exactly one `kdeconnect-helper.py watch` instance is owned by the bridge. During migration, do not leave the old QML watcher running in parallel once the bridge watcher is enabled.
- When a client connects, provide a reliable current snapshot. Do not replay an arbitrary last event such as an old `removed` event as though it were current state. Cache the latest full `sync` snapshot or ask the helper for a fresh `list`/snapshot.

### Suggested message shapes

Requests from QML to Python:

```json
{"id":1,"command":"devices"}
{"id":2,"command":"list"}
{"id":3,"command":"share","device":"DEVICE_ID","files":["/path/to/file"]}
{"id":4,"command":"reply","replyId":"REPLY_ID","notifId":"NOTIF_ID","summary":"...","body":"...","message":"Hello"}
{"id":5,"command":"dismiss","notifId":"NOTIF_ID","summary":"...","body":"..."}
```

Responses:

```json
{"bridgeType":"response","id":1,"ok":true,"result":[],"error":""}
```

Events from Python to QML:

```json
{"bridgeType":"event","payload":{"event":"sync","activeIds":[],"notifications":[]}}
```

A startup/status message may also be used, but its schema must be documented and handled by QML. Every frame is one complete JSON object terminated by `\n`. Do not mix logs into stdout; logs belong on stderr/journald.

### Request handling rules

- Support multiple clients safely, though the normal setup usually has one QML client.
- Correlate responses by request ID and return useful errors for unknown commands or invalid fields.
- Keep command execution off the QML UI thread. The socket is asynchronous from the QML perspective.
- Add a timeout and cleanup for pending QML requests/callbacks.
- Bound the pending request queue. Do not indefinitely queue destructive or non-idempotent actions such as reply, dismiss, or share while the service is disconnected, because they could execute much later and unexpectedly. Either fail these requests promptly while disconnected or give them a short documented expiry. Query requests may be retried/queued only with explicit limits.
- On reconnect, request or receive a fresh notification/device snapshot; do not assume no events were missed.
- If bridge command `list` or `devices` output fails JSON parsing, return a clear error instead of treating invalid output as a successful result.

## 7. Quickshell API design

Create `services/PhoneBridge.qml` as a singleton registered through `services/qmldir`.

Recommended surface (adjust to fit existing QML style, but keep it small and stable):

- `property bool connected`
- `property string lastError` or equivalent diagnostic state
- `signal kdeNotificationEvent(var event)` for existing notification event shapes
- `signal requestCompleted(int requestId, bool ok, var result, string error)` or a typed/structured equivalent
- A generic `request(command, payload, callback)` method, plus small convenience methods if they materially simplify callers.

Use Quickshell's `Quickshell.Io.Socket` plus `SplitParser` for a JSON-lines client **only after checking the API supported by the installed Quickshell version**. `Socket.connected` is a target connection state; `Socket.write()` does nothing while disconnected and the final write should be flushed. The installed version may differ from online docs, so inspect the actual Nix-provided Quickshell API/version and test connection-state and reconnect behavior.

Reference docs for validation:

- https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/Socket/
- https://quickshell.org/docs/v0.3.0/types/Quickshell.Io/SplitParser/

Do not copy a QML example solely because it appears in docs for a different version. Verify the signals/properties available in the version used by this NixOS system.

## 8. Nix and systemd integration

Add a separate option/service in `nix/home-manager-module.nix`, consistent with existing module conventions. Naming proposal:

- Option: `programs.quickshell-shell.enablePhoneBridgeService`, default enabled when the shell itself is enabled, unless repository convention suggests a better conditional default.
- Unit: `systemd.user.services.phone-bridge`.
- Start at the appropriate user graphical session target so it has the user's session bus/runtime directory available.
- `Restart=on-failure` with a short restart delay.
- Keep stdout/stderr in journald.
- Do not use `pkexec`, root services, or global system services.
- The bridge service must be separate from `quickshell-shell`.

Script path handling is critical. The flake has both a config-source mode and a package mode. Inspect the actual defaults and how `cfg.package` is set before editing. Ensure `phone-bridge.py` and `kdeconnect-helper.py` are available in each supported mode. Prefer a stable declarative path that does not depend on a manually copied file. If the option is disabled, Quickshell must remain usable with the existing fallback behavior and the old watcher must not be removed in a way that silently disables notifications.

Do not assume starting the Phone Bridge service also starts KDE Connect. KDE Connect remains the existing backend daemon.

## 9. Migration phases

### Phase 0: Preflight and safety

1. Read the current repository files in full where relevant: `flake.nix`, `nix/home-manager-module.nix`, `scripts/kdeconnect-helper.py`, `services/Notifications.qml`, `services/DeviceShare.qml`, `services/qmldir`.
2. Search all imports and usages of `DeviceShare`, `Notifications`, the helper executable, `kdeWatcherProc`, `kdeLinkProc`, reply/dismiss processes, and any direct `kdeconnect-helper.py` invocations.
3. Confirm `git status --short` before editing. Do not overwrite user changes.
4. Check the installed Quickshell version/API and the actual package/config mode.
5. Write a short planned file list before applying edits.

### Phase 1: Backend in isolation

1. Implement the Python socket server and watcher manager without editing `Notifications.qml` or `DeviceShare.qml` yet.
2. Reuse `kdeconnect-helper.py` as the command/D-Bus compatibility layer.
3. Add protocol validation, safe lifecycle cleanup, watcher restart/backoff, request/response correlation, and snapshot semantics.
4. Add focused tests using a fake helper or injectable helper path. Do not require a real phone for protocol unit tests.
5. Manually verify the backend can start, listen on the private socket, accept a client, answer `devices`/`list`, and stop cleanly. Keep the old watcher untouched during this phase.

### Phase 2: Declarative service

1. Add the user systemd unit in the Home Manager module.
2. Validate script paths for both package mode and config mode.
3. Evaluate/build the flake or Home Manager configuration without switching the active system.
4. Confirm that logs are visible through `journalctl --user -u phone-bridge` and that a service restart cleans up the old socket and watcher.

### Phase 3: QML singleton and protocol test

1. Add and register `PhoneBridge.qml`.
2. Test connected/disconnected/reconnect state, JSON-line parsing, callback correlation, malformed responses, and pending-request timeout behavior.
3. Verify there is no QML syntax/API error by launching a test config or using the repository's existing Quickshell validation procedure.
4. Do not migrate callers until the singleton connects reliably and `devices`/`list` responses are decoded correctly.

### Phase 4: Notification watcher cutover

1. Replace only the watcher `Process` and restart `Timer` in `Notifications.qml` with a `Connections` handler subscribed to `PhoneBridge.kdeNotificationEvent`.
2. Route these event types to the same existing functions:
   - `sync` -> `syncKdeNotificationsWithActive(activeIds, notifications)`.
   - `removed` -> remove IDs, then apply active snapshot using the existing function behavior.
   - `all_removed` -> `removeAllKdeNotifications()`.
3. Preserve native freedesktop notifications and every existing notification-center feature.
4. Enable the new watcher only after the service is healthy. Ensure the old watcher no longer runs after cutover; never run both watchers simultaneously.
5. Test phone notification arrival, update, dismissal on phone, dismissal on desktop, history behavior, notification linking, reconnect after KDE Connect restart, and Quickshell restart.

### Phase 5: Route KDE Connect actions through the bridge

Migrate one category at a time:

1. `kdeLinkProc` / active notification lookup (`list`).
2. Inline reply (`reply`).
3. Dismiss and mark-as-read actions (`dismiss`).
4. Device listing and file transfer from `DeviceShare.qml` (`devices`, `share`).

Keep `DeviceShare.qml`'s existing public API and feedback state intact. Retain the LocalSend path as it is. Search and remove old direct helper invocations only when that specific call path is successfully migrated.

During the transition, every KDE Connect action must have exactly one live execution path. Avoid accidental duplicate replies, duplicate dismissals, or a hidden fallback that runs the same action twice.

### Phase 6: Phone Hub UI

Only after Phases 1 through 5 are stable, build the Phone Hub as a consumer of `PhoneBridge.qml` and the preserved `DeviceShare` / `Notifications` APIs.

Potential later UI scope:

- Connected device and connection state.
- Battery/network/device metadata only when reliably available from KDE Connect or another explicit API.
- Send-file entry points using existing sharing behavior.
- Shortcuts to open scrcpy or LocalSend, only on explicit user action.
- Notification/quick-action views only by reusing existing data models where practical.

Do not invent phone telemetry that KDE Connect does not expose. Do not make a new panel block backend stability work.

## 10. Testing and acceptance criteria

The migration is accepted only when all applicable checks pass:

### Static / build checks

- `git diff --check` passes.
- Python files pass `python3 -m py_compile`.
- QML loads without syntax or missing-singleton errors in the installed Quickshell version.
- Nix evaluation/build succeeds in the intended user configuration.
- All `services/qmldir` singleton entries match real file names and module names.
- The user may review a small readable diff; no large unrelated reformatting.

### Backend

- Starting the service creates one private socket under the expected runtime directory.
- The service receives commands and responds with the corresponding request ID.
- Malformed requests and unsupported commands return errors without killing the service.
- Watcher failure triggers restart/backoff and does not leave orphan `dbus-monitor` children.
- Service stop/restart removes stale sockets safely.
- A new client receives a trustworthy current snapshot rather than a stale removal event.
- Logs do not leak notification bodies, message contents, or reply text.

### Existing behavior

- Android notifications still arrive in Quickshell.
- Existing notification updates/removals and phone-side auto-dismiss synchronization work.
- Inline reply still sends exactly once.
- Desktop dismiss/mark-as-read still works.
- Notification history, popup timers, grouping, app icons, and native desktop notification actions remain intact.
- Device list refresh works and `DeviceShare.defaultDevice` / `hasKdeDevice` retain their behavior.
- KDE Connect file transfer works.
- LocalSend transfer path still works.
- Dynamic Island behavior and existing callers of `DeviceShare.qml` are unchanged.
- Stopping/restarting Quickshell does not spawn a second backend watcher.
- Stopping/restarting Phone Bridge leaves the UI in a recoverable disconnected state and reconnects when the service returns.

### Operational verification commands

Use commands adapted to the actual module and service names. Do not execute a system switch without the user asking.

```sh
# Repository review
 git -C ~/.config/quickshell status --short
 git -C ~/.config/quickshell diff --check

# Python syntax
 python3 -m py_compile ~/.config/quickshell/scripts/kdeconnect-helper.py
 python3 -m py_compile ~/.config/quickshell/scripts/phone-bridge.py

# Service diagnostics, after the user enables/activates the unit
 systemctl --user status phone-bridge
 journalctl --user -u phone-bridge -b --no-pager

# Verify only one watcher exists
 pgrep -af 'kdeconnect-helper.py watch'
```

Use the repository's existing Nix evaluation/build workflow. Prefer a dry evaluation/build before applying a new Home Manager generation. The agent must state exactly which command it ran and whether it actually switched the system.

## 11. Rollback plan

- Keep each phase in a separate, reviewable diff.
- Do not delete `kdeconnect-helper.py`; it remains the compatibility layer and can support a fallback during migration.
- If Phase 4 causes notification regressions, restore the old watcher block in `Notifications.qml` and disable the Phone Bridge watcher before further debugging.
- If a new Nix unit fails, disable the new option/service while leaving the existing `quickshell-shell` service unchanged.
- Do not auto-reset the whole repository or discard user changes.

## 12. Instructions to the coding agent

Implement this blueprint in the repository, not as a separate auto-patcher. Work in small stages, reviewable diffs, and stop after each phase to report what changed and what checks passed. Before editing, inspect the current files and `git status`. Do not assume file contents still match the planning snippets. Do not execute `nh-switch`, `home-manager switch`, or any system generation switch unless the user explicitly authorizes it.

The first response from the agent should be a short preflight summary: (1) current repository state, (2) exact files it plans to edit for Phase 1, (3) any mismatch between the current repository and this blueprint. Then implement only Phase 1 unless explicitly told to continue. Do not begin Phone Hub visual UI work until the backend migration is stable.
