# Nimbush Adaptive Performance Architecture Plan

> **Status:** Proposal / pre-implementation design  
> **Repository:** `YasirFadhil/Nimbush`  
> **Working branch:** `master`  
> **Audit snapshot:** `master` at tree SHA `3392f8715f26201876d571f62cdf07185c3aa3ef`  
> **Purpose:** Keep Nimbush responsive during sustained CPU, memory, and rendering pressure without unnecessarily sacrificing its Liquid Glass visual identity.

---

## 1. Executive summary

Nimbush already has useful foundations for an adaptive shell: a central `services/` layer, a system-monitor service, visibility-aware timers in some components, a CAVA service with consumer tracking, and a `Loader`-based lazy-loading example for Settings.

The main opportunity is to make those practices consistent across the shell.

The proposed work has four goals:

1. **Avoid work that has no visible consumer.** Defer transient windows and stop decorative animations when their owner is hidden or inactive.
2. **Give recurring work one owner.** Consolidate duplicate MPRIS position heartbeats and network-state polling.
3. **Adapt visual quality to system pressure.** Introduce a central `Performance` service with Normal, Balanced, and Critical profiles.
4. **Measure before and after.** Establish CPU, memory, frame-time, and interaction baselines before changing animation behavior.

The first implementation should be conservative: remove redundant work and fix lifecycle conditions before changing visual design or rewriting large QML files.

## 2. Scope and audit notes

This design is based on a **static source inspection of the `master` working branch**, not the repository's default `main` branch.

The inspected areas include:

- `shell.qml`
- `modules/bar/components/DynamicIsland.qml`
- `modules/bar/components/StatusTray.qml`
- `modules/lockscreen/Lockscreen.qml`
- `modules/controlcenter/ControlCenter.qml`
- `modules/dock/Dock.qml`
- `modules/media/NowPlaying.qml`
- `services/Mpris.qml`
- `services/Sysmon.qml`
- `services/Cava.qml`
- `services/Compositor.qml`
- `scripts/sysmon-helper.sh`
- `scripts/compositor-helper.py`
- `nix/home-manager-module.nix`

The counts below describe declarations found in source, **not the number of animations or processes active at runtime**.

| Component | Timers | Animation declarations | Behaviors | MultiEffect | Layer enabled |
|---|---:|---:|---:|---:|---:|
| Dynamic Island | 22 | 262 | 102 | 3 | 8 |
| Lockscreen | 15 | 130 | 85 | 2 | 2 |
| Control Center | 2 | 100 | 74 | 0 | 0 |
| Dock | 2 | 25 | 16 | 0 | 0 |
| Status Tray | 3 | 34 | 28 | 0 | 0 |
| Now Playing | 1 | 14 | 14 | 1 | 1 |

These numbers are a complexity signal, not proof of a performance defect. Runtime profiling is required to confirm which declarations are expensive and when they run.

## 3. Findings and proposed fixes

### 3.1 Eager construction of transient windows

**Priority:** High  
**Location:** [`shell.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/shell.qml#L27-L50)

`ShellRoot` directly declares several windows and modules, including Launcher, Emoji Picker, Dashboard, Clipboard History, Power Menu, Control Center, Battery, Volume, Sysmon, Calendar, Lockscreen, and Welcome. Settings already demonstrates a `Loader` with `active: false`.

A hidden window is not necessarily free: the QML object tree exists, bindings can still be evaluated, and timers or animations may continue unless their lifecycle is explicitly gated.

**Proposal**

- Keep always-needed shell surfaces resident: Wallpaper, Bar/Dynamic Island, Dock, and essential notification infrastructure.
- Keep Lockscreen preloaded if profiling confirms that lazy creation would cause an unacceptable lock-screen delay.
- Use `Loader` for transient windows such as Launcher, Emoji Picker, Dashboard, Clipboard History, Control Center, Battery, Volume, Sysmon, Calendar, and Welcome.
- Unload only after the close transition completes. Use a short unload grace period to avoid repeated construction during quick reopen actions.
- Preserve the existing IPC names and public behavior while moving the implementation behind loaders.

**Acceptance criteria**

- Opening and closing each transient module still works through existing IPC actions.
- Reopening a recently closed module does not produce visible layout jumps or broken focus.
- Hidden, unloaded modules do not retain active timers, processes, or animation loops.
- Shell startup and idle memory are measured before and after.

### 3.2 Duplicate MPRIS position heartbeats

**Priority:** High  
**Locations:**

- [`services/Mpris.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/services/Mpris.qml#L104-L114)
- [`modules/bar/components/DynamicIsland.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/bar/components/DynamicIsland.qml#L2176-L2182)
- [`modules/lockscreen/Lockscreen.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/lockscreen/Lockscreen.qml#L127-L133)
- [`modules/media/NowPlaying.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/media/NowPlaying.qml#L27-L32)

The repository currently contains position refresh timers in multiple consumers:

| Owner | Interval | Running condition |
|---|---:|---|
| `Mpris.qml` | 250 ms | Active player is playing |
| Dynamic Island | 500 ms | `mediaPlaying` |
| Lockscreen | 500 ms | Locked and playing |
| Now Playing | 500 ms | Card player is playing |

These timers can call `positionChanged()` on the same player. The combined cost depends on the number of active consumers and the MPRIS implementation, but the ownership is unnecessarily distributed.

**Proposal**

- Make `services/Mpris.qml` the only owner of the position heartbeat.
- Consumers read the shared player's position and react to the shared position-change signal.
- Keep one normal heartbeat initially at 250 ms, then evaluate 500 ms during Balanced/Critical profiles.
- Do not add consumer-specific fallback timers unless there is a verified player compatibility issue.
- Confirm that seeking, progress bars, lock-screen media controls, and track changes remain correct.

**Acceptance criteria**

- Only one periodic position heartbeat exists for the active player.
- Progress remains smooth enough in Normal mode.
- Position updates slow down under pressure without breaking seek or playback controls.

### 3.3 Dynamic Island recurring polling and decorative animation

**Priority:** High  
**Location:** [`DynamicIsland.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/bar/components/DynamicIsland.qml)

Relevant recurring work found in `master`:

| Work | Current interval / condition | Concern |
|---|---|---|
| Camera / recording probe | 1,800 ms, always running | Repeated Python process launch and PipeWire/process inspection |
| CapsLock probe | 1,200 ms, always running | Repeated shell + grep process launch |
| MPRIS refresh | 500 ms while media plays | Duplicates the central MPRIS heartbeat |
| Media marquee | Infinite while media plays and lock is not blocking | Does not express every visual-consumer condition in its running predicate |
| Vinyl rotation | 12-second infinite animation | Must be proven to stop outside the media-peek presentation |
| Satellite indicators | Several infinite animations | Some are already visibility-gated; preserve these gates and apply profile policy |

**Proposal**

- Trace camera and recording detection before changing semantics. Prefer a persistent event/watch mechanism where the relevant PipeWire or process events are available. If polling remains necessary, make its cadence profile-aware and avoid spawning a new helper when the previous one is still running.
- Replace CapsLock shell polling with an input/event source if a reliable Quickshell or system event API is available. Otherwise use a lower-frequency fallback and avoid polling when the indicator is not needed.
- Remove the Island-local MPRIS heartbeat after the shared service is verified.
- Gate marquee on all of: media playing, relevant text actually overflows, presentation visible, not locked, and decorative motion enabled.
- Gate vinyl rotation on the exact media-peek state and stop it when the relevant item is hidden or destroyed.
- Preserve essential recording/camera state indicators in every profile. In Balanced/Critical, make their presentation static rather than hiding the information.
- Keep existing notification, transfer, and satellite state transitions deterministic. Do not replace state transitions with arbitrary animation-duration changes.

**Acceptance criteria**

- No decorative infinite animation runs when its visual owner is hidden.
- Camera/recording state remains correct through app start/stop and screen-share transitions.
- CapsLock state remains accurate enough for the chosen event or fallback method.
- No indicator flicker or media-state handoff regression.

### 3.4 Lockscreen effects and animation lifecycle

**Priority:** High  
**Location:** [`Lockscreen.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/lockscreen/Lockscreen.qml)

The Lockscreen contains wallpaper blur (`MultiEffect`), clock reflection/mask effects, layer-backed items, a Canvas-drawn Face ID element, and many transitions. It also contains a 500 ms MPRIS timer and multiple animations that should be audited for visibility and state ownership.

The wallpaper image currently uses `asynchronous: false` with a comment explaining that synchronous upload avoids a one-frame texture blink during compositor switching. **Do not change this blindly.** Any change to image upload or lock/unlock timing must be tested against the existing transition choreography.

**Proposal**

- Preserve the existing lock/unlock state machine and timing as the first constraint.
- Move expensive decorative effects behind `Services.Performance` gates.
- Normal: keep configured wallpaper blur and clock reflection.
- Balanced: disable wallpaper blur and reflection/mask decoration; retain a readable wallpaper dim/tint treatment.
- Critical: use a simple translucent/solid overlay and keep only essential state transitions.
- Stop decorative marquee, pulse, and rotation animations when the Lockscreen is not visible or their content is inactive.
- Keep Face ID feedback, lock state, password input, focus, and unlock confirmation responsive in every profile.
- Avoid adding `layer.enabled` to more elements by default. Use layers only when profiling shows a net benefit for a specific animated subtree.

**Acceptance criteria**

- Lock, unlock, Genie transition, Face ID, password entry, and compositor handoff remain visually correct.
- Critical mode does not delay authentication or lock-state transitions.
- Blur and clock effects can be disabled without changing geometry or focus behavior.

### 3.5 Duplicate Ethernet detection

**Priority:** Medium  
**Locations:**

- [`StatusTray.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/bar/components/StatusTray.qml#L18-L69)
- [`ControlCenter.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/modules/controlcenter/ControlCenter.qml#L38-L91)

Both components have their own Ethernet detection process. Status Tray also owns an always-running `ip monitor` process and a 5-second fallback poll. Control Center starts another monitor while visible and a 3-second fallback poll while visible.

This can duplicate network-state work while Control Center is open.

**Proposal**

- Move Ethernet state into a shared service, for example `services/NetworkState.qml`.
- The service owns one initial query, one `ip monitor` watcher, and one fallback timer used only if the watcher is unavailable or fails.
- Status Tray and Control Center become read-only consumers of `connected`, `interfaceName`, and `ipv4Address`.
- Debounce bursts of monitor output before querying `/sys/class/net` and IP state.

**Acceptance criteria**

- One network watcher and one fallback strategy serve both consumers.
- Cable plug/unplug and DHCP address changes still update both interfaces promptly.

### 3.6 Sysmon as the basis for shared system metrics

**Priority:** Medium  
**Location:** [`Sysmon.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/services/Sysmon.qml#L41-L80), [`sysmon-helper.sh`](https://github.com/YasirFadhil/Nimbush/blob/master/scripts/sysmon-helper.sh)

Sysmon currently polls basic stats every 2.5 seconds when the tray metric is enabled or the Sysmon panel is open. Task enumeration is separately polled every 4 seconds only when the Sysmon panel is visible and not paused.

The basic helper reads `/proc/stat`, `/proc/meminfo`, thermal sysfs, disk usage, and uptime. This is a useful starting point for a shared metrics source.

**Proposal**

- Separate **system metric sampling** from **task-list enumeration**.
- Reuse one metrics snapshot for Sysmon UI and the Performance service. Do not launch a second sampler solely for the governor.
- Add optional Linux Pressure Stall Information (PSI) readings from `/proc/pressure/cpu` and `/proc/pressure/memory` when available.
- Keep GPU utilization optional and capability-detected. On Intel systems, a supported DRM sysfs metric may be exposed, but the service must work without it.
- Consider a 1.0-1.5 second metric sample cadence as an initial test value. This is a proposal, not a benchmark-derived optimum.
- Keep task process enumeration on its existing slower, panel-only path.
- Ensure the metric source is active whenever automatic performance mode is enabled, even when the Sysmon panel is closed.

**Acceptance criteria**

- Only one source computes CPU and memory snapshots for Sysmon and Performance.
- Missing PSI/GPU metrics do not cause errors or disable adaptive profiles.
- Task enumeration never runs just because the Performance service is active.

### 3.7 CAVA visual update throttling

**Priority:** Medium  
**Locations:** [`Cava.qml`](https://github.com/YasirFadhil/Nimbush/blob/master/services/Cava.qml), [`cava.conf`](https://github.com/YasirFadhil/Nimbush/blob/master/assets/cava.conf)

The current CAVA configuration requests 35 FPS. `Cava.qml` already has useful lifecycle conditions: it runs only when CAVA is available/enabled, local media is playing, the screen is unlocked, and at least one consumer is active.

**Proposal**

- Keep 35 FPS in Normal mode initially.
- In Balanced mode, coalesce visual property updates to approximately 15 FPS. This reduces QML/UI update frequency even if the CAVA process continues producing samples at 35 FPS.
- In Critical mode, stop the CAVA process by including the Performance profile in `shouldRun`, while keeping a static media indicator.
- Do not restart CAVA repeatedly on every profile fluctuation. Use stable profile transitions and the existing restart debounce.

**Acceptance criteria**

- CAVA starts only when a real visual consumer exists.
- Balanced mode reduces QML update frequency without introducing waveform jitter.
- Critical mode stops unnecessary CAVA work and restores it cleanly.

### 3.8 QML layout and transition strategy

**Priority:** Medium  
**Locations:** Control Center, Dock, Status Tray, Dashboard, and other animated panels.

The codebase has many `Behavior` declarations on width, height, x/y, opacity, scale, and `Layout.preferredHeight`. These are not inherently problematic, but repeated geometry changes can cause layout recalculation across a subtree.

**Proposal**

- Keep layout geometry stable where possible.
- Animate a wrapper item using `opacity`, `scale`, or transforms rather than continuously changing the preferred size of a complex layout.
- Use `Layout.preferredWidth` / `Layout.preferredHeight` animation only when the layout change is part of the intended interaction.
- Do not animate every child independently if a parent transform can achieve the same visual result.
- Use `visible` and lifecycle gates in addition to `opacity: 0`; opacity alone is not a reliable stop condition for timers or animations.

**Acceptance criteria**

- No overlapping layout animations produce width/height oscillation or content reflow glitches.
- Panel opening/closing remains consistent across Normal, Balanced, and Critical.

### 3.9 Security and code-hygiene follow-up

**Priority:** Separate review; not a performance blocker.

` scripts/compositor-helper.py` contains a `subprocess.Popen(..., shell=True, ...)` call around line 2362. The command construction and data flow should be inspected before deciding whether it is exploitable. Prefer argument arrays with `shell=False` when shell syntax is not required.

The repository also tracks several `.bak` files and an unusual root-level file named `\`. These do not directly explain animation stutter. Review whether they are intentional, then remove obsolete artifacts in a separate cleanup commit so performance changes remain easy to review and bisect.

---

## 4. Proposed architecture

### 4.1 New central service: `services/Performance.qml`

Create a singleton service that owns profile selection and publishes simple, read-only quality flags to consumers. Register it in `services/qmldir` using the same singleton conventions as the existing services, then verify that it is reachable through the current `import "services" as Services` pattern.

The service should **not** independently launch a second CPU/RAM sampler. It should consume the shared metrics snapshot proposed in section 3.6.

Suggested public API:

```qml
Services.Performance.profile                 // "normal" | "balanced" | "critical"
Services.Performance.isAutomatic             // automatic mode enabled
Services.Performance.highLoad                // compatibility boolean
Services.Performance.decorativeMotion        // decorative loops allowed
Services.Performance.blurEnabled             // expensive blur allowed
Services.Performance.reflectionEnabled       // glass reflection/mask allowed
Services.Performance.waveformEnabled         // CAVA waveform allowed
Services.Performance.marqueeEnabled          // text marquee allowed
Services.Performance.positionUpdateInterval // 250 or 500, milliseconds
Services.Performance.transitionScale         // profile-specific duration multiplier
```

The API is illustrative. Names should be finalized before implementation and then kept stable to avoid churn across QML files.

### 4.2 Data flow

```text
                  /proc + sysfs (+ PSI when available)
                                |
                                v
                    Shared System Metrics
                    (one sampling owner)
                         |            |
                         v            v
                       Sysmon     Performance
                       display     Governor
                                      |
                         +------------+-------------+
                         |            |             |
                         v            v             v
                     Dynamic       Lockscreen    CAVA / panels
                      Island
```

Responsibilities:

- **Metrics source:** sample CPU, MemAvailable, PSI, temperature, and optional GPU utilization.
- **Sysmon:** display metrics and run task-list operations only when its panel requires them.
- **Performance Governor:** classify pressure, apply hysteresis, and publish a profile.
- **UI modules:** consume flags; they do not calculate system load independently.

### 4.3 Performance profiles

| Capability | Normal | Balanced | Critical |
|---|---|---|---|
| Essential interaction transitions | Full | Preserved, slightly shorter | Preserved, simplified |
| Decorative infinite animations | Enabled when visible/needed | Disabled | Disabled |
| Dynamic Island marquee | Conditional | Disabled unless essential | Disabled |
| Vinyl rotation / decorative pulses | Enabled when visible | Disabled | Disabled |
| Wallpaper blur | User setting | Disabled | Disabled |
| Clock reflection/mask | User setting | Disabled | Disabled |
| CAVA UI updates | Up to current 35 FPS | Coalesce to ~15 FPS | Stop CAVA |
| Media position heartbeat | 250 ms | 500 ms | 500 ms |
| Camera/recording detection | Normal validated cadence | Slower/event-driven preferred | Preserve state accuracy; use event-driven or a safe fallback |
| Essential indicators | Animated where appropriate | Static where possible | Static, always visible |

**Important:** Critical does not mean disabling all animation or hiding important information. Unlock, focus, notifications, transfer status, privacy state, and other essential feedback must remain understandable and responsive.

### 4.4 Initial automatic thresholds

The following are **starting values for testing**, not final tuning or guaranteed thresholds for every machine.

| Trigger | Candidate action |
|---|---|
| CPU usage above 75% for 3 consecutive samples | Enter Balanced |
| MemAvailable below 15% of MemTotal | Enter Balanced |
| CPU usage above 90% for 5 seconds | Enter Critical |
| MemAvailable below 8% of MemTotal | Enter Critical |
| Memory PSI `some avg10` indicates sustained reclaim/stall pressure | Escalate one profile level, after validation |
| Metrics unavailable | Fall back to Normal or a user-selected fixed profile; never crash |

**Hysteresis and recovery**

- Require sustained pressure before escalating. Do not switch profile on one noisy sample.
- Require at least 10-15 seconds of stable recovery before dropping one profile level.
- Recover one level at a time: Critical -> Balanced -> Normal.
- Use a minimum dwell time to prevent rapid toggling.
- Avoid coupling profile recovery to short CPU spikes caused by Nimbush itself opening a panel.
- Log profile transitions for diagnosis, but do not write a log line every metric sample.

The thresholds should be calibrated on the actual target device and during realistic workloads. CPU utilization alone is insufficient to represent GPU/render pressure.

### 4.5 Manual override

Provide a user setting with four choices:

- `Auto` (default)
- `Normal`
- `Balanced`
- `Critical`

Manual selection overrides automatic classification but does not disable the metrics display. Persist the choice through the existing Config system. Provide an explicit reset to `Auto`.

---

## 5. Implementation phases

### Phase 0 — Baseline and instrumentation

1. Capture an idle baseline after login.
2. Capture an animation-heavy baseline: media playing, Dynamic Island expanded, CAVA active, Dock hover, and Control Center open.
3. Capture a high-load baseline with a separate CPU and memory workload.
4. Record Quickshell CPU/RSS, system memory available, frame-time/render timing, and interaction latency.
5. Record which processes are launched by Dynamic Island, Sysmon, and network indicators.

**Deliverable:** `docs/performance/baseline.md` with hardware, software versions, commands, test scenarios, and results.

### Phase 1 — Remove redundant recurring work

1. Centralize MPRIS position updates in `services/Mpris.qml`.
2. Remove the consumer heartbeats from Dynamic Island, Lockscreen, and Now Playing after validating the shared signal path.
3. Consolidate Ethernet monitoring into a singleton Network State service.
4. Trace and improve Camera/CapsLock polling lifecycle.
5. Gate decorative animations on actual visibility and presentation state.

**Deliverable:** one focused commit per subsystem, with before/after process and timing notes.

### Phase 2 — Lazy-load transient modules

1. Introduce a consistent Loader pattern in `shell.qml`.
2. Migrate one module at a time, starting with modules that are expensive and infrequently opened.
3. Preserve IPC, focus, screen assignment, overlay registration, and close animation semantics.
4. Keep Lockscreen preloaded until startup/lock latency is measured and proven safe to change.

**Deliverable:** transient modules are created on demand and unload safely.

### Phase 3 — Shared metrics and Performance Governor

1. Refactor Sysmon metrics into a shared snapshot provider.
2. Add optional PSI and optional GPU metrics with capability detection.
3. Implement `services/Performance.qml` with Normal, Balanced, Critical, hysteresis, recovery, and manual override.
4. Add a small read-only profile indicator to Sysmon or Settings for test visibility.
5. Keep all consumer flags deterministic and default to safe values when a metric source fails.

**Deliverable:** a working central profile service with unit-like logic tests for thresholds and transitions.

### Phase 4 — Adaptive rendering and motion

1. Apply profile flags to Dynamic Island decorative animations.
2. Apply profile flags to Lockscreen blur/reflection and decorative loops.
3. Apply profile flags to CAVA updates and process lifecycle.
4. Apply profile-aware transition durations only after state-transition tests pass.
5. Audit remaining modules for hidden infinite animations and layout-heavy geometry changes.

**Deliverable:** all visual consumers honor the central profile without duplicating load detection.

### Phase 5 — Regression and tuning

1. Run the complete interaction matrix in section 6.
2. Compare the baseline and final measurements.
3. Tune thresholds based on repeated tests, not a single run.
4. Test thermal throttling and memory pressure separately from CPU saturation.
5. Document known hardware/API limitations.

**Deliverable:** performance report and a stable default configuration.

---

## 6. Test matrix and acceptance criteria

| Scenario | Expected result |
|---|---|
| Idle desktop, no media | No decorative loops without visible consumers; low and stable shell CPU |
| Media playing, collapsed Island | Metadata and progress update; no off-screen marquee or vinyl rotation |
| Media playing, Now Playing open | Smooth progress with only one MPRIS heartbeat |
| Lockscreen visible | Clock, auth, Face ID, and lock controls remain responsive |
| Lock/unlock during media playback | No blink, stale artwork, duplicate progress timer, or broken handoff |
| Control Center opened | Ethernet state updates from the shared service; no second monitor/polling stack |
| Camera starts/stops | Privacy indicator tracks state correctly without excessive process spawning |
| Screen recording starts/stops | Recording indicator remains correct; do not confuse generic screen nodes with recording evidence |
| CAVA active | Normal waveform behaves as before; Balanced updates are coalesced; Critical stops CAVA safely |
| Sustained CPU load | Profile escalates after the configured delay; essential interactions remain responsive |
| Memory pressure | Profile escalates before the shell becomes unresponsive; no destructive cache-clearing behavior |
| Load recovery | Profile steps down gradually and does not oscillate |
| Metrics source unavailable | Shell continues operating with a safe fallback profile |
| Manual profile override | Selected profile remains active until returned to Auto |

### Suggested success indicators

- No duplicate 250/500 ms MPRIS position heartbeat in consumer components.
- No recurring timer in a hidden module unless explicitly justified.
- No decorative infinite animation while its visual item is hidden.
- Fewer helper process launches during idle and animation-heavy scenarios.
- Reduced QML update/render work in Balanced and Critical modes.
- No regression in lock/unlock, notification handoff, media transitions, transfer state, or input focus.
- Improved or unchanged panel interaction latency under sustained load.

Do not declare a performance win based only on a lower animation count. Compare Quickshell CPU/RSS, render timing, and interaction behavior under identical scenarios.

## 7. Profiling and diagnostic commands

Use diagnostics as temporary test instrumentation, not permanent user-facing environment defaults.

```sh
# Quickshell / Qt Quick scene graph diagnostics
QSG_INFO=1 quickshell
QSG_RENDER_TIMING=1 quickshell

# Process resource usage
ps -o pid,ppid,%cpu,%mem,rss,stat,comm -C quickshell -C qs

# Memory availability and pressure
cat /proc/meminfo | grep -E 'MemTotal|MemAvailable'
cat /proc/pressure/memory 2>/dev/null
cat /proc/pressure/cpu 2>/dev/null

# Intel GPU utilization, if exposed by the active DRM driver
for f in /sys/class/drm/card*/device/gt_busy_percent; do
    [ -r "$f" ] && printf '%s: ' "$f" && cat "$f"
done
```

`QSG_RENDER_TIMING` and `QSG_INFO` output should be captured during a controlled run. Use the QML Profiler from Qt Creator or the matching Qt tooling to locate excessive binding reevaluation, JavaScript execution, signal activity, and object creation.

The shell may be launched through a wrapper or service in the actual NixOS setup. Adapt the diagnostic environment variables to the real launch path rather than starting a second shell instance alongside the active one.

## 8. Design constraints and non-goals

### Must preserve

- Existing visual identity and layout in Normal mode.
- Existing IPC entry points and module behavior.
- Lock/unlock timing, Face ID, password focus, and compositor handoff.
- Notification ownership and Dynamic Island handoff logic.
- Media controls, seeking, album art, and player selection.
- Camera/recording privacy indicators and transfer state.
- NixOS/Home Manager integration and existing configuration conventions.

### Must avoid

- A separate CPU/RAM polling loop in every component.
- Blindly replacing transitions with zero-duration changes.
- Using `opacity: 0` as the only lifecycle gate.
- Killing/restarting CAVA or helper processes repeatedly during profile oscillation.
- Disabling important state feedback in Critical mode.
- Broad refactors of Dynamic Island and Lockscreen in the same commit.
- Treating source-code declaration counts as runtime performance measurements.

## 9. Recommended first pull-request sequence

Keep the changes small and reversible:

1. `perf(mpris): centralize position heartbeat`
2. `perf(network): share ethernet state watcher`
3. `perf(island): gate decorative animation lifecycle`
4. `perf(metrics): expose shared system pressure snapshot`
5. `feat(performance): add adaptive performance governor`
6. `perf(shell): lazy-load transient modules`
7. `perf(rendering): apply balanced and critical visual profiles`

Each PR should include its own test notes. Avoid mixing security cleanup or backup-file deletion into the performance commits.

## 10. Final recommendation

Start with **Phase 0 and Phase 1**. They offer the best chance of reducing unnecessary work while keeping the UI design intact. Once those changes are measured and stable, add the shared metrics provider and Performance Governor.

The intended result is not a permanently stripped-down shell. It is a shell that uses its full visual capability when resources are available, sheds decorative work under pressure, and restores quality gradually without losing interaction state.
