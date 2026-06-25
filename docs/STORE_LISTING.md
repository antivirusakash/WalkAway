# WalkAway — Store / Landing Listing

Price: **Free**
Distribution: Developer ID direct (notarized DMG via GitHub Releases) — not the Mac App Store
Category: Utilities / Productivity / Security
Platform: macOS 13 (Ventura) and later · Universal (Apple Silicon + Intel)

---

## Name
WalkAway — Auto-Lock When You Leave

## Subtitle (30 char max)
Lock your Mac when you leave

## Promotional text (170 char max)
Walk away, your Mac locks itself. Sit down, it's right where you left it. Apple Watch presence locking—no idle timers, no exposed screen. Get peace of mind.

---

## Description

> ASO note: Apple does **not** index the description for search ranking — it's a
> pure conversion asset. No keyword stuffing. Keywords belong in the keyword
> field, subtitle, and **screenshot captions** (Apple indexes caption text as of
> June 2025). Front-load value; keep it scannable with headings + bullets.

**Walk away. Your Mac locks. Sit down. Keep working.**

WalkAway locks your Mac the moment you step away with your Apple Watch — and keeps it open while you're sitting right there. It locks on *presence*, not on an idle timer, so your screen is never left exposed to the room after you go, and never locks on you mid-sentence.

**Why WalkAway**
- **Presence, not timers.** Idle-lock timers lock while you're reading, or leave your Mac open for minutes after you've gone. WalkAway locks on distance.
- **Reliable departures.** Tuned so leaving always locks — an armed lock holds through brief signal blips, so a single stray reading can't cancel a lock in progress.
- **Stays out of your way.** Won't lock while you're actively typing or moving the mouse — it waits until you're truly gone.
- **Your distance.** Choose how far is "away." Default 6 meters, adjustable from 2 to 20.
- **Light and quiet.** Lives in the menu bar, sips resources, launches at login.

**How it works**
1. Pick your Apple Watch from the menu bar.
2. Set your lock distance and grace period.
3. Walk away — your Mac locks itself. Come back — it's right where you left it.

**Private by design**
WalkAway runs entirely on your Mac. No account, no cloud, no analytics, no tracking — nothing leaves your device. It only reads the Bluetooth signal strength of the watch you choose.

**Good to know**
WalkAway only locks — it never unlocks, sleeps, or wakes your Mac, and never touches your running apps. Long-running tasks keep going behind the lock screen. Unlocking stays with macOS (password, Touch ID, or Apple Watch Auto Unlock).

Free. Signed with a Developer ID and notarized by Apple.

---

## What's New (v1.0.0)
- First public release. Free, signed, and notarized.
- Reliable "walking away" detection: missing watch signal locks instead of stalling.
- An armed lock holds through transient signal blips — a single stray reading can't cancel a lock in progress.
- Smoothed readings (median + outlier rejection) with debounce on both leaving and returning.
- Default lock distance 6 meters (adjustable 2–20).

---

## Keywords
lock screen, auto lock, apple watch, proximity lock, walk away, mac security, privacy, menu bar, presence, away lock

## Requirements
- macOS 13.0 or later
- An Apple Watch paired to the same Apple ID, with Bluetooth on
- Bluetooth permission

## Screenshot captions (keyword-indexed since June 2025 — put keywords HERE)
1. Lock your Mac when you walk away
2. Apple Watch proximity, not idle timers
3. Stays open while you work
4. Set your away distance — 2 to 20 m
5. Private: no account, no cloud, no tracking

## Support / Privacy URLs
- Support: <https://github.com/antivirusakash/WalkAway/issues>
- Privacy: policy text in repo `PRIVACY.md`; public host to be published (Gist/Pages/landing). WalkAway collects and transmits no data.
