# WalkAway — Settings & Usage

Full reference for WalkAway's controls. For a quick start, see the
[README](../README.md).

## First-use flow

1. Launch the app and open the WalkAway menu-bar item.
2. Grant Bluetooth permission if macOS asks.
3. WalkAway auto-selects the watch if it's already visible in macOS Bluetooth
   data; otherwise use `Rescan` and pick it from the device list.
4. Confirm the menu-bar title shows an RSSI value, such as `WalkAway -45`.
5. Keep `Lock by distance` on and set your `Distance` (default 6 m).
6. Keep `Pause while active` on.
7. Walk away and confirm the Mac locks after the lock delay.

## Menu controls

### Device

- `Rescan`: refreshes CoreBluetooth and system Bluetooth data.
- `Reconnect`: restarts monitoring for the selected device.
- `Forget`: clears the selected device.

### Proximity

- `Lock by distance`: switches from raw RSSI threshold mode to estimated
  distance mode.
- `Distance`: lock when estimated distance is greater than this value. Minimum
  is 2 m to reduce false locks from RSSI noise.
- `Current`: live estimated distance from the latest smoothed RSSI. Hidden while
  RSSI is unavailable.
- `Lock delay`: how long the watch must stay away before locking.
- `Pause while active`: keeps postponing the lock while recent keyboard or mouse
  activity is detected.

### Advanced

- `Missing signal`: how long WalkAway waits without RSSI before treating the
  watch as away.
- `Lock when signal is lost`: treats a visible watch with no RSSI as away
  through the normal lock delay.
- `RSSI threshold`: raw dBm threshold for RSSI mode.
- `Lock if Bluetooth drops`: optionally treats Bluetooth radio loss as away.
- `Launch at login`: registers/unregisters the app with macOS login items.
- `Calibration` (shown only when RSSI is available): `Set 1 m` stores the
  current RSSI as the 1-meter reference; `Set 2 m` stores RSSI at 2 meters and
  recalculates the path-loss exponent; `Set away point` tunes the formula so the
  current RSSI maps to the configured lock distance.
- `Lock Now`: immediately locks the screen.
- `Quit`: exits WalkAway and stops all locking behavior.

## Status indicators

- Green menu-bar icon: the selected watch is visible to macOS or live RSSI is available.
- Muted menu-bar icon: the selected watch is not currently visible.
- `Present`: the selected watch is inside the configured threshold.
- `Leaving`: the watch is away and the grace timer is running.
- `Locked`: WalkAway fired the lock for the current absence.
- `Bluetooth unavailable`: Bluetooth is off, resetting, unauthorized, or unsupported.

## Distance mode

Distance is estimated from RSSI with the log-distance path-loss model:

```text
distanceMeters = 10 ^ ((referenceRSSIAtOneMeter - currentRSSI) / (10 * pathLossExponent))
```

Defaults:

- `referenceRSSIAtOneMeter`: `-55 dBm`
- `pathLossExponent`: `2.2`
- `lockDistanceMeters`: `6 m`

RSSI is noisy. Treat distance as an approximation — calibration improves it but
does not make it exact. WalkAway smooths readings (median + outlier rejection),
debounces both leaving and returning, and honors an armed lock through transient
signal blips so a single stray reading can't cancel a lock in progress.

## Recommended settings

- `Lock by distance`: on
- `Distance`: start at the default `6 m`; lower it (toward 2–3 m) to lock sooner,
  raise it if it locks while you're still nearby
- `Lock delay`: `5 s`
- `Pause while active`: on
- `Lock if Bluetooth drops`: off until you trust the behavior

## Troubleshooting

Check whether macOS currently reports Apple Watch RSSI:

```bash
system_profiler SPBluetoothDataType | grep -A2 'Apple Watch'
```

If the watch appears without RSSI, WalkAway treats it as present but cannot
estimate distance at that moment. Wait, move the watch, toggle Bluetooth, or try
`Reconnect` / `Rescan`.

If the lock happens too early: increase `Distance`, `Lock delay`, or
`Missing signal`, or recalibrate at 1 meter. If it happens too late: decrease
those values.

## Diagnostics

WalkAway logs its proximity decisions and on-device performance via Apple's
unified logging. See [DIAGNOSTICS.md](DIAGNOSTICS.md). Live decisions, including
estimated distance:

```bash
/usr/bin/log show --predicate 'subsystem == "com.fizday.walkaway" && category == "decision"' --last 10m --info | grep dist=
```

## Build from source

```bash
./script/build_and_run.sh --verify
```

Stops any running WalkAway, builds the SwiftPM target, rebuilds icon assets,
stages `dist/WalkAway.app`, launches it, and verifies the process is running.

Release packaging (universal build, Developer ID signing, notarization,
stapling, DMG + zip) is documented in [RELEASE.md](RELEASE.md) and driven by
[`../script/package_release.sh`](../script/package_release.sh).

## Security notes

WalkAway is a convenience layer, not the only security boundary. macOS remains
responsible for authentication. Do not store a password in the app, script
password entry, or attempt to bypass macOS authentication. WalkAway
intentionally locks only.

See [TECHNICAL_SPEC.md](TECHNICAL_SPEC.md) for implementation details.
