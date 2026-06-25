# WalkAway Technical Specification

## Purpose

WalkAway is a macOS 13+ SwiftUI menu-bar app that locks the current user
session when a selected Apple Watch appears to move out of range. The app is
designed for personal use and intentionally avoids unlock, sleep, wake,
caffeinate, and agent-management behavior.

The product rule is:

```text
watch present -> do nothing
watch away for grace period -> lock screen once
watch returns -> re-arm
```

## Platform

- Target OS: macOS 13+
- Language: Swift
- UI: SwiftUI `MenuBarExtra`
- Package type: SwiftPM executable staged as a `.app` bundle
- App style: `LSUIElement = true`, no Dock icon, no main window
- Sandbox: not sandboxed
- Distribution: local/personal use

## External Frameworks And System APIs

- `SwiftUI`: menu-bar UI.
- `AppKit`: accessory activation, `NSApplication`, `NSImage`.
- `CoreBluetooth`: BLE scan and optional peripheral RSSI polling.
- `ServiceManagement`: launch-at-login registration.
- `CoreGraphics`: keyboard/mouse idle detection.
- `Darwin`: `dlopen` / `dlsym` for immediate lock.
- `/usr/sbin/system_profiler SPBluetoothDataType`: pragmatic system Bluetooth
  snapshot source for Apple Watch RSSI when CoreBluetooth does not expose the
  watch as a normal connectable peripheral.
- `/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession`:
  fallback lock command.

## Non-Goals

- Unlocking the Mac.
- Touch ID or Apple Watch Auto Unlock integration.
- Password storage or password entry.
- Sleep prevention.
- Agent supervision.
- Multi-watch policy.
- App Store distribution.

## App Entry

File:

```text
Sources/WalkAway/App/WalkAwayApp.swift
```

Responsibilities:

- Sets the app activation policy to `.accessory`.
- Creates the shared app services:
  - `SettingsStore`
  - `Locker`
  - `LockController`
  - `ProximityMonitor`
- Hosts the SwiftUI `MenuBarExtra`.
- Renders the template status icon.
- Tints the status icon green when the selected watch is visible or live RSSI
  exists.

The menu-bar icon is loaded from bundled PNG resources:

```text
WalkAwayStatusIcon.png
WalkAwayStatusIcon@2x.png
WalkAwayStatusIcon@3x.png
```

The PNG is marked as an `NSImage` template so macOS can tint it.

## Settings

File:

```text
Sources/WalkAway/Stores/SettingsStore.swift
```

All user-facing settings persist in `UserDefaults`.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `peripheralUUID` | `UUID?` | none | CoreBluetooth peripheral identifier for a selected BLE device. |
| `systemBluetoothAddress` | `String` | empty | System Bluetooth MAC-style address for the selected watch. |
| `peripheralName` | `String` | empty | Display name for the selected device. |
| `rssiThreshold` | `Int` | `-75` | Raw RSSI threshold in dBm. Below this is away in RSSI mode. |
| `useDistanceThreshold` | `Bool` | `false` | Enables distance mode. |
| `lockDistanceMeters` | `Double` | `3` | Lock when estimated distance is greater than this. Clamped to minimum 2 m. |
| `referenceRSSIAtOneMeter` | `Int` | `-55` | Calibration RSSI used as the 1 meter reference. |
| `pathLossExponent` | `Double` | `2.2` | Path loss exponent for distance estimation. |
| `referenceRSSIAtTwoMeters` | `Int` | `-62` | Calibration RSSI captured at 2 meters. |
| `lockWhenRSSIMissing` | `Bool` | `false` | In distance mode, optionally treats visible-without-RSSI as away. |
| `graceSeconds` | `Int` | `5` | Device must stay away this long before locking. |
| `noSignalTimeout` | `Int` | `10` | Seconds without RSSI before treating the watch as away. |
| `pauseWhileActive` | `Bool` | `true` | Defers locking while keyboard/mouse activity is recent. |
| `lockOnBluetoothUnavailable` | `Bool` | `false` | Treat Bluetooth radio failure as away. |

Launch-at-login state is read from `SMAppService.mainApp.status`; it is not
stored separately.

## Device Discovery And Monitoring

File:

```text
Sources/WalkAway/Services/ProximityMonitor.swift
```

`ProximityMonitor` is the app's proximity input layer. It owns:

- `CBCentralManager`
- CoreBluetooth scan results
- selected peripheral connection
- RSSI polling timers
- system Bluetooth snapshot polling
- RSSI smoothing buffer
- no-signal timeout checks

Published state:

- `discoveredDevices`
- `smoothedRSSI`
- `lastRSSIDate`
- `bluetoothDescription`

### CoreBluetooth Path

The original path uses CoreBluetooth:

1. Scan for nearby BLE peripherals.
2. List discovered peripherals.
3. Persist selected `CBPeripheral.identifier`.
4. Reconnect with `retrievePeripherals(withIdentifiers:)`.
5. Poll `readRSSI()` once per second.
6. Push readings into the moving average.

This path is kept because it works for normal BLE peripherals and may work for
some watch-visible cases, but Apple Watch is not reliably exposed as a normal
connectable BLE peripheral.

### System Bluetooth Path

File:

```text
Sources/WalkAway/Services/SystemBluetoothSnapshot.swift
```

Because this Mac can see the Apple Watch in system Bluetooth data, WalkAway also
uses:

```bash
/usr/sbin/system_profiler SPBluetoothDataType
```

The parser extracts:

- device name
- address
- optional RSSI

`SystemBluetoothSnapshot.normalizeAddress(_:)` converts addresses to lowercase
dash-separated form, for example:

```text
3c-50-02-58-d2-23
```

When no device is selected, WalkAway auto-selects the first system Bluetooth
device whose normalized name contains `Apple Watch`.

When a system Bluetooth address is selected:

1. CoreBluetooth scanning stops.
2. WalkAway polls the system Bluetooth snapshot every 2 seconds.
3. If the selected address appears with RSSI, the RSSI enters the smoothing
   buffer.
4. If the selected address is present without RSSI, WalkAway treats it as
   connected/present but clears the distance reading.
5. If the selected address disappears for longer than `noSignalTimeout`, the
   watch is treated as away.
6. If `lockWhenRSSIMissing` is enabled, visible-without-RSSI is evaluated as no
   signal and can lock through the normal grace path.

This is pragmatic rather than pure. It matches the data macOS actually exposes
for Apple Watch on this machine.

## RSSI Smoothing

RSSI samples are smoothed with a simple moving average of the last 5 values:

```text
smoothedRSSI = rounded(mean(lastFiveRSSISamples))
```

The smoothed value feeds:

- menu-bar title
- connection indicator
- distance estimate
- lock state machine

No RSSI but selected system watch visible means:

- menu-bar icon stays green.
- distance estimate is unavailable.
- lock state stays present/re-armed.

No RSSI and no selected-system-watch visibility means:

- no-signal timeout can drive the app into away behavior.

## Distance Estimation

File:

```text
Sources/WalkAway/Services/DistanceEstimator.swift
```

Distance mode uses the log-distance path loss model:

```text
distanceMeters = 10 ^ ((referenceRSSIAtOneMeter - currentRSSI) / (10 * pathLossExponent))
```

Inputs:

- `currentRSSI`: smoothed RSSI.
- `referenceRSSIAtOneMeter`: calibration value captured by `Set 1 m`.
- `referenceRSSIAtTwoMeters`: calibration value captured by `Set 2 m`.
- `pathLossExponent`: environment factor, clamped to `1.2 ... 4.5`.

Default values:

```text
referenceRSSIAtOneMeter = -55
pathLossExponent = 2.2
lockDistanceMeters = 3
```

Two-point calibration recalculates path loss with:

```text
pathLossExponent = (referenceRSSIAtOneMeter - referenceRSSIAtTwoMeters) / (10 * log10(2))
```

The UI also shows the effective RSSI cutoff for the selected distance:

```text
cutoffRSSI = referenceRSSIAtOneMeter - (10 * pathLossExponent * log10(lockDistanceMeters))
```

Distance mode defines away as:

```text
estimatedDistance > lockDistanceMeters
```

RSSI mode defines away as:

```text
smoothedRSSI < rssiThreshold
```

Distance estimates are approximate and should not be treated as physical truth.
RSSI changes with body position, desk placement, walls, radio interference, and
watch behavior.

## Lock State Machine

File:

```text
Sources/WalkAway/Services/LockController.swift
```

State enum:

```text
noDevice
bluetoothUnavailable(message)
scanning
connecting
present
leaving(deadline)
locked
```

Core state transitions:

```text
no device selected -> noDevice
device selected -> connecting
RSSI/distance inside threshold -> present
RSSI/distance outside threshold -> leaving(deadline)
leaving past deadline -> lock -> locked
device returns inside threshold -> present and re-arm
```

The `locked` state is per absence. After WalkAway fires a lock, it does not lock
again until the watch returns inside threshold and clears
`hasLockedForCurrentAbsence`.

### Pause While Active

Before locking, `LockController` checks `ActivityMonitor` if `pauseWhileActive`
is enabled. If recent keyboard or mouse activity exists, it pushes the leaving
deadline out by at least the configured `graceSeconds` value instead of locking.

This check runs both when the app first enters `leaving` and again when the
deadline expires. As long as the user keeps typing, moving the pointer, clicking,
dragging, or scrolling, each away reading extends the deadline again. That makes
local activity stronger than noisy RSSI or distance estimates.

## User Activity Detection

File:

```text
Sources/WalkAway/Services/ActivityMonitor.swift
```

Uses:

```swift
CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: ...)
```

Events checked:

- key down
- mouse down
- mouse moved
- mouse dragged
- scroll wheel

The current active window/application does not matter. This is session-wide
activity. WalkAway treats activity inside the last 8 seconds as recent.

## Lock Implementation

File:

```text
Sources/WalkAway/Services/Locker.swift
```

Primary lock path:

```swift
dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
dlsym(handle, "SACLockScreenImmediate")
```

The private `SACLockScreenImmediate` symbol locks the current session without
sleeping the Mac.

Fallback:

```bash
/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession -suspend
```

Both paths lock the session only. Running processes continue.

## UI Specification

File:

```text
Sources/WalkAway/Views/MenuBarView.swift
```

The UI is a compact menu-bar window with:

- status header
- device section
- tuning section
- action row

### Status Header

Displays:

- state icon
- state title
- selected device and live reading
- connection dot

Visual connection rules:

- Green icon/dot if `smoothedRSSI != nil`.
- Muted icon/dot if RSSI is missing.

Nearby / armed rule:

```text
if state == present and estimatedDistance <= 1m:
  title = "Nearby / Armed"
  icon = checkmark.shield
  title color = green
```

This is visual only. It does not unlock the Mac. It tells the user WalkAway has
re-armed after the watch returned close.

### Device Section

Shows:

- selected device name
- selected UUID or system Bluetooth address
- `Reconnect`
- `Forget`
- discovered devices list
- `Rescan`

System Bluetooth devices show `System` in their subtitle.

### Tuning Section

Controls:

Primary:

- `Lock by distance`
- `Distance`
- `Current`
- `Lock delay`
- `Pause while active`

Advanced:

- `Missing signal`
- `Lock when signal is lost`
- `RSSI threshold`
- `Lock if Bluetooth drops`
- `Launch at login`
- `Calibration`
- `Set 1 m`
- `Set 2 m`
- `Set away point`

`RSSI threshold` is visible only in Advanced and only when distance mode is off.
Distance mode keeps using the stored raw RSSI threshold as a fallback setting,
but it does not show that control in the primary tuning surface.

`Current` is visible only while a live RSSI value is available. `Calibration` is
inside Advanced and is also visible only while RSSI exists. This keeps the normal
menu from showing disabled calibration controls or empty distance readouts.

`Set away point` recalculates the path-loss exponent so the current RSSI
maps to the configured `lockDistanceMeters`. When the configured distance is
near 2 meters, it also stores that RSSI as `referenceRSSIAtTwoMeters`.

### Action Section

Controls:

- `Lock Now`
- `Quit`

## App Icons

Icon generation script:

```text
script/generate_app_icon.swift
```

Outputs:

- `Resources/WalkAway.icns`
- `Resources/WalkAway.iconset/*`
- `Resources/WalkAway-icon-preview.png`
- `Resources/WalkAwayStatusIcon.png`
- `Resources/WalkAwayStatusIcon@2x.png`
- `Resources/WalkAwayStatusIcon@3x.png`

The icon uses a generic smartwatch silhouette and lock mark. It intentionally
does not use the Apple logo, Apple Watch UI, or Apple-provided marketing
graphics.

## Build Script

File:

```text
script/build_and_run.sh
```

The script:

1. Kills the old process with `pkill -x WalkAway`.
2. Runs `swift build`.
3. Regenerates icons.
4. Creates `dist/WalkAway.app`.
5. Copies the executable and resources.
6. Writes `Contents/Info.plist`.
7. Opens the bundle with `/usr/bin/open -n`.

Important Info.plist keys:

```text
CFBundleExecutable = WalkAway
CFBundleIdentifier = com.fizday.walkaway
CFBundleIconFile = WalkAway
CFBundleIconName = WalkAway
LSMinimumSystemVersion = 13.0
NSApplicationActivationPolicy = Accessory
NSBluetoothAlwaysUsageDescription = Detects when your watch leaves to lock the Mac.
NSPrincipalClass = NSApplication
LSUIElement = true
```

Supported script modes:

- `run`
- `--debug`
- `--logs`
- `--telemetry`
- `--verify`

## Privacy

WalkAway stores only local settings in `UserDefaults`. It does not send network
requests. It shells out to local macOS tooling for Bluetooth data.

Stored device identifiers:

- CoreBluetooth UUID, when using CoreBluetooth selection.
- System Bluetooth address, when using the Apple Watch system path.
- Display name.

## Security Model

WalkAway can only strengthen the lock path by locking sooner. It does not
weaken unlock because it has no unlock implementation.

Unlock remains controlled by macOS authentication. This is intentional.

Unsafe approaches that are deliberately excluded:

- storing the user's password
- typing the password into the lock screen
- spoofing unlock events
- using private unlock APIs
- disabling lock-screen protections

## Known Limitations

1. Apple Watch RSSI is intermittent in macOS system Bluetooth data.
2. RSSI distance estimates are noisy.
3. `system_profiler SPBluetoothDataType` is slower than direct BLE polling.
4. Apple Watch is not reliably available as a normal CoreBluetooth peripheral.
5. The private lock symbol could move in a future macOS release.
6. Launch-at-login behavior depends on local signing/bundle context.

## Manual Verification Plan

### Build

```bash
swift build
./script/build_and_run.sh --verify
```

Expected:

- build succeeds
- `pgrep -x WalkAway` succeeds
- menu-bar item appears

### System Watch Visibility

```bash
system_profiler SPBluetoothDataType | grep -A2 'Apple Watch'
```

Expected best case:

```text
Akash's Apple Watch:
    Address: ...
    RSSI: -45
```

If RSSI is missing, distance mode cannot update until macOS reports RSSI again.

### Proximity

1. Open WalkAway.
2. Confirm green connected icon once RSSI appears.
3. Enable `Lock by distance`.
4. Stand 1 meter from the Mac.
5. Open `Calibration` and click `Set 1 m`.
6. Set distance to `3 m` or `5 m`.
7. Walk away.
8. Confirm state becomes `Leaving`.
9. Wait through `Lock delay`.
10. Confirm screen locks.
11. Unlock manually with macOS.
12. Return near the Mac.
13. Confirm state returns to `Nearby / Armed`.

### Agent/Process Continuity

1. Start a long-running command or agent task.
2. Trigger WalkAway lock.
3. Unlock manually.
4. Confirm the task continued while locked.

## Future Improvements

- Replace `system_profiler` polling with a faster local Bluetooth source if one
  proves reliable for Apple Watch RSSI.
- Add a small diagnostics panel showing raw system Bluetooth snapshot status.
- Add a cooldown after lock to avoid repeated lock attempts in edge cases.
- Add a local-only export/import of settings.
- Add unit tests for `SystemBluetoothSnapshot.parse` and `DistanceEstimator`.
- Add structured logging behind a debug toggle.
