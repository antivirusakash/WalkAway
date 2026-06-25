# WalkAway — Diagnostics & Performance

All telemetry is **local**. Nothing leaves the Mac (no account, no network).

## In-app
Menu → **Diagnostics** disclosure shows live:
- **Memory** — process footprint (matches Activity Monitor "Memory").
- **CPU (app)** — this process's own CPU. Excludes the spawned `system_profiler`.
- **Poll cost** — rolling average wall time of each Bluetooth poll (the
  `system_profiler` spawn dominates this).
- **Locks / Away events / Deferred** — cumulative usage counters (persisted).
- **Uptime**, plus a **Reset stats** button.

## Logs (Console / `log`)
> The `log` command is shadowed in some shells — use the absolute path.

Performance (one line every 30s):
```
/usr/bin/log stream --predicate 'subsystem == "com.fizday.walkaway" && category == "perf"'
```
Lock decisions (every reading):
```
/usr/bin/log stream --predicate 'subsystem == "com.fizday.walkaway" && category == "decision"'
```
Historical (no live stream): `/usr/bin/log show --last 1h --predicate '…' --info`.

## Measured baseline (Apple Silicon, watch present)
- Memory footprint: **~13 MB**
- App CPU: **0.25–0.5 %**
- Poll cost: **~200 ms every 2 s** — almost entirely the `system_profiler`
  child process. This is the dominant resource cost (CPU bursts + a wake every
  2 s). Watch `avgPollMillis` over time; if battery/CPU matters, the fix is
  **adaptive polling** (slow the interval when the watch is present and the
  signal is steady, speed up when leaving). Not yet implemented — it interacts
  with the away-detection tuning.
