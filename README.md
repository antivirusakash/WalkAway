# WalkAway

WalkAway is a personal macOS menu-bar app that locks the Mac when a selected
nearby Apple Watch appears to move away. It never unlocks the Mac, never sleeps
the Mac, and does not manage running processes. Long-running terminal or agent
tasks keep running behind the lock screen.

The app is intentionally small: pick or auto-detect the watch, monitor proximity,
lock when the watch is away, and show status in the menu bar.

## What It Does

- Runs as a background menu-bar-only app.
- Uses macOS Bluetooth data to detect the selected Apple Watch.
- Reads RSSI when macOS exposes it for the watch.
- Estimates distance from RSSI when distance mode is enabled.
- Locks the screen after a grace period when the watch is away.
- Re-arms when the watch returns.
- Shows green connection status when a live RSSI reading is available.
- Shows `Nearby / Armed` when estimated distance is at or below 1 meter.
- Provides manual `Lock Now`, `Reconnect`, `Forget`, and `Rescan` actions.
- Optionally launches at login.

## What It Does Not Do

- It does not unlock the Mac.
- It does not bypass the macOS lock screen.
- It does not sleep, wake, or caffeinate the Mac.
- It does not control AI agents or terminal jobs.
- It does not use Apple's private Apple Watch unlock flow.
- It is not App Store-ready.

Unlocking should be handled by macOS itself through password, Touch ID, or
Apple Watch Auto Unlock.

## Current Status

This is prototype-ready for personal testing. It builds and runs cleanly, and it
can poll Apple Watch RSSI through macOS system Bluetooth data when that data is
available.

The main limitation is that Apple Watch RSSI from macOS is intermittent.
Sometimes `system_profiler SPBluetoothDataType` lists the watch with RSSI;
sometimes it lists the watch without RSSI. If the selected watch is still listed
without RSSI, WalkAway treats it as connected/present but cannot estimate
distance until RSSI returns.

## Requirements

- macOS 13 Ventura or newer.
- Apple Silicon or Intel Mac.
- Swift toolchain / Xcode Command Line Tools.
- Bluetooth enabled.
- Apple Watch visible to this Mac in macOS Bluetooth system data.

The app is not sandboxed. It uses a private lock symbol for immediate locking,
with a public command-line fallback.

## Build And Run

From the project root:

```bash
./script/build_and_run.sh --verify
```

The script:

1. Stops any running WalkAway process.
2. Builds the SwiftPM target.
3. Generates/rebuilds icon assets.
4. Stages `dist/WalkAway.app`.
5. Launches the app bundle.
6. Verifies the process is running.

The built app is staged at:

```text
dist/WalkAway.app
```

The Codex Run action is wired through:

```text
.codex/environments/environment.toml
```

## Release Build

Release packaging is documented in
[docs/RELEASE.md](docs/RELEASE.md).

## First-Use Flow

1. Run the app.
2. Open the WalkAway menu-bar item.
3. Grant Bluetooth permission if macOS asks.
4. If the Apple Watch is already visible in macOS system Bluetooth data,
   WalkAway can auto-select it.
5. If needed, use `Rescan` and select the watch from the device list.
6. Confirm the menu-bar title eventually shows an RSSI value, such as
   `WalkAway -45`.
7. Enable `Lock by distance` if you want meter-based behavior.
8. Set the lock distance, for example `2 m`, `3 m`, or `5 m`.
9. Keep `Pause while active` on.
10. Walk away and verify the Mac locks after the lock delay.

## Menu Controls

### Device

- `Rescan`: asks WalkAway to refresh CoreBluetooth and system Bluetooth data.
- `Reconnect`: restarts monitoring for the selected device.
- `Forget`: clears the selected device.

### Proximity

- `Lock by distance`: switches from raw RSSI threshold mode to estimated
  distance mode.
- `Distance`: lock when estimated distance is greater than this value. The
  minimum is 2 m to reduce false locks from RSSI noise.
- `Current`: live estimated distance from the latest smoothed RSSI. Hidden
  while RSSI is unavailable.
- `Lock delay`: how long the watch must stay away before locking.
- `Pause while active`: keeps postponing the lock while recent keyboard or
  mouse activity is detected.

### Advanced

- `Missing signal`: how long WalkAway waits without RSSI before treating the
  watch as away.
- `Lock when signal is lost`: treats a visible watch with no RSSI as away
  through the normal lock delay.
- `RSSI threshold`: raw dBm threshold for RSSI mode.
- `Lock if Bluetooth drops`: optionally treats Bluetooth radio loss as away.
  Keep this off until you trust the behavior.
- `Launch at login`: registers/unregisters the app with macOS login items.
- `Calibration`: optional controls shown only when RSSI is available.
- `Set 1 m`: stores the current RSSI as the reference RSSI at 1 meter.
- `Set 2 m`: stores the current RSSI at 2 meters and recalculates the
  path-loss exponent.
- `Set away point`: tunes the distance formula so the current RSSI maps to the
  configured lock distance.
- `Lock Now`: immediately locks the screen.
- `Quit`: exits WalkAway and stops all locking behavior.

## Status Indicators

- Green menu-bar icon: the selected watch is visible to macOS or live RSSI is available.
- Muted menu-bar icon: the selected watch is not currently visible.
- `Nearby / Armed`: estimated distance is at or below 1 meter and the app is
  ready to lock on the next absence.
- `Present`: the selected watch is inside the configured threshold.
- `Leaving`: the selected watch is away and the grace timer is running.
- `Locked`: WalkAway fired the lock for the current absence.
- `Bluetooth unavailable`: Bluetooth is off, resetting, unauthorized, or
  unsupported.

## Distance Mode

Distance is estimated from RSSI with the log-distance path loss model:

```text
distanceMeters = 10 ^ ((referenceRSSIAtOneMeter - currentRSSI) / (10 * pathLossExponent))
```

Defaults:

- `referenceRSSIAtOneMeter`: `-55 dBm`
- `pathLossExponent`: `2.2`
- `lockDistanceMeters`: `3 m`

RSSI is noisy. Treat distance as an approximation. Calibration improves it but
does not make it exact.

## Recommended Settings

For first testing:

- `Lock by distance`: on
- `Distance`: `2 m` to `5 m`; start around `3 m`
- `Lock delay`: `5 s`
- `Pause while active`: on
- `Missing signal`: `10 s` to `20 s` in Advanced
- `Lock if Bluetooth drops`: off

Once you trust the behavior, tune distance and timeout values to match your room
and watch behavior.

## Security Notes

WalkAway is a convenience layer, not the only security boundary. macOS remains
responsible for real authentication.

Do not store a password in the app. Do not script password entry into the lock
screen. Do not attempt to bypass macOS authentication. WalkAway intentionally
locks only.

## Troubleshooting

Check whether macOS currently reports Apple Watch RSSI:

```bash
system_profiler SPBluetoothDataType | grep -A2 'Apple Watch'
```

If the watch appears without RSSI, WalkAway treats it as connected but cannot
estimate distance at that moment. Wait, move the watch, toggle Bluetooth, or try
`Reconnect` / `Rescan`.

If the app does not appear in the menu bar:

```bash
pgrep -lf WalkAway
```

If it is not running, relaunch it:

```bash
./script/build_and_run.sh --verify
```

If the lock happens too early:

- Increase `Distance`.
- Increase `Lock delay`.
- Increase `Missing signal`.
- Recalibrate at 1 meter.

If the lock happens too late:

- Decrease `Distance`.
- Decrease `Lock delay`.
- Lower `Missing signal`.

## Project Layout

```text
Sources/WalkAway/App/WalkAwayApp.swift
Sources/WalkAway/Views/MenuBarView.swift
Sources/WalkAway/Stores/SettingsStore.swift
Sources/WalkAway/Services/ProximityMonitor.swift
Sources/WalkAway/Services/SystemBluetoothSnapshot.swift
Sources/WalkAway/Services/LockController.swift
Sources/WalkAway/Services/Locker.swift
Sources/WalkAway/Services/DistanceEstimator.swift
Sources/WalkAway/Services/ActivityMonitor.swift
Sources/WalkAway/Models/DiscoveredDevice.swift
Sources/WalkAway/Models/PresenceState.swift
Sources/WalkAway/Support/Formatters.swift
script/build_and_run.sh
script/generate_app_icon.swift
Resources/
```

See [docs/TECHNICAL_SPEC.md](docs/TECHNICAL_SPEC.md) for implementation details.
