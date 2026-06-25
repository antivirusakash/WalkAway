# WalkAway

**Walk away. Your Mac locks. Come back. Keep working.**

WalkAway is a macOS menu-bar app that locks your Mac automatically when you step
away with your Apple Watch — and keeps it open while you're sitting there
working. It locks on *presence*, not on an idle timer, so it never locks
mid-sentence and never leaves your screen exposed after you've gone.

- **Presence, not timers.** Locks on distance, not inactivity.
- **Won't lock while you work.** Holds off while you're actively typing or moving the mouse.
- **Set your distance.** Default 6 meters, adjustable from 2 to 20.
- **Private.** Runs entirely on your Mac. No account, no cloud, no tracking. It only reads the Bluetooth signal strength of the watch you pick.
- **Quiet.** Lives in the menu bar; optional launch at login.

WalkAway only ever **locks** — it never unlocks, sleeps, or wakes your Mac, and
never touches running processes. Long-running terminal or agent tasks keep
running behind the lock screen. Unlocking stays with macOS (password, Touch ID,
or Apple Watch Auto Unlock).

## Requirements

- macOS 13 Ventura or later · Apple Silicon or Intel (universal build)
- An Apple Watch paired to the same Apple ID, with Bluetooth on
- Bluetooth permission (granted on first launch)

## Install

1. Download `WalkAway-<version>.dmg` from the
   [latest release](https://github.com/antivirusakash/WalkAway/releases/latest).
2. Open the DMG and drag **WalkAway** into **Applications**.
3. Launch WalkAway. The build is **signed with a Developer ID and notarized by
   Apple**, so it opens normally — no Gatekeeper right-click needed.
4. Grant **Bluetooth** permission when macOS asks.
5. Open the WalkAway menu-bar icon, pick your Apple Watch, set your lock
   distance, and walk away.

> Distributed directly as a notarized app — **not** on the Mac App Store. macOS
> has no public screen-lock API, so locking requires a mechanism the App Store
> sandbox forbids. This direct build is the complete app.

## How It Works

WalkAway watches the Bluetooth signal strength (RSSI) between your Mac and your
chosen Apple Watch, estimates distance, and locks the screen after a short grace
period once the watch is beyond your set distance — or its signal is lost. It
re-arms automatically when the watch returns. While you're actively using the
Mac, the lock is postponed until you've truly gone.

It is not sandboxed: it reads macOS Bluetooth data to find the watch and uses a
private lock symbol for immediate locking, with a public command-line fallback.

## What It Does Not Do

- It does not unlock the Mac or bypass the macOS lock screen.
- It does not sleep, wake, or caffeinate the Mac.
- It does not control terminal jobs or background agents.
- It does not store passwords or script authentication.

macOS remains responsible for real authentication. WalkAway is a convenience
layer that only locks.

## Build From Source

From the project root:

```bash
./script/build_and_run.sh --verify
```

The script stops any running WalkAway, builds the SwiftPM target, rebuilds icon
assets, stages `dist/WalkAway.app`, launches it, and verifies the process is
running.

Release packaging (universal build, Developer ID signing, notarization,
stapling, DMG + zip) is documented in [docs/RELEASE.md](docs/RELEASE.md) and
driven by [`script/package_release.sh`](script/package_release.sh).

## First-Use Flow

1. Launch the app and open the WalkAway menu-bar item.
2. Grant Bluetooth permission if macOS asks.
3. WalkAway auto-selects the watch if it's already visible in macOS Bluetooth
   data; otherwise use `Rescan` and pick it from the device list.
4. Confirm the menu-bar title shows an RSSI value, such as `WalkAway -45`.
5. Keep `Lock by distance` on and set your `Distance` (default 6 m).
6. Keep `Pause while active` on.
7. Walk away and confirm the Mac locks after the lock delay.

## Menu Controls

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

## Status Indicators

- Green menu-bar icon: the selected watch is visible to macOS or live RSSI is available.
- Muted menu-bar icon: the selected watch is not currently visible.
- `Present`: the selected watch is inside the configured threshold.
- `Leaving`: the watch is away and the grace timer is running.
- `Locked`: WalkAway fired the lock for the current absence.
- `Bluetooth unavailable`: Bluetooth is off, resetting, unauthorized, or unsupported.

## Distance Mode

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

## Recommended Settings

- `Lock by distance`: on
- `Distance`: start at the default `6 m`; lower it (toward 2–3 m) if you want it
  to lock sooner, raise it if it locks while you're still nearby
- `Lock delay`: `5 s`
- `Pause while active`: on
- `Lock if Bluetooth drops`: off until you trust the behavior

## Diagnostics

WalkAway logs its proximity decisions and on-device performance via Apple's
unified logging. See [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md). Live decisions,
including estimated distance:

```bash
/usr/bin/log show --predicate 'subsystem == "com.fizday.walkaway" && category == "decision"' --last 10m --info | grep dist=
```

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

## Security Notes

WalkAway is a convenience layer, not the only security boundary. macOS remains
responsible for authentication. Do not store a password in the app, script
password entry, or attempt to bypass macOS authentication. WalkAway
intentionally locks only.

See [docs/TECHNICAL_SPEC.md](docs/TECHNICAL_SPEC.md) for implementation details.
