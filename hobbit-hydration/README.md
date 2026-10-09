# 🌿 Hobbit Hydration

A tiny, hobbit-themed macOS menu bar app that reminds you to drink water — at random-ish intervals, like a surprise visit from Gandalf.

> "Second breakfast is nothing without water."

<!-- Add a screenshot: ![Screenshot](screenshot.png) -->

## Features

- **Lives in your menu bar** — shows `🍺 24/75 oz · 🔥3` (today's intake / goal · streak)
- **Pick your vessel** — Teacup (8 oz), Mug (12 oz), Tankard (20 oz), Flagon (32 oz), or a custom size
- **Smart goal** — daily goal is half your body weight (lb) in ounces; the app tells you how much to sip per reminder
- **You choose the interval** — 5 to 120 minutes. Reminders arrive at a random time between 70% and 130% of your interval, so they feel like surprises
- **Notifications** with random hobbit-flavored messages
- **Progress through Middle-earth** — from "Still snug in Bag End" to "Quest complete — the Ring is in the fire! 🔥"
- **Streaks** — hit your daily goal to extend your streak; miss a day and it resets. Your best streak is saved
- **Open at login** toggle
- Everything is saved locally; no accounts, no network, no tracking

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (only needed to build)

## Build & install as a regular app

1. In Xcode: **File → New → Project → macOS → App**. Choose **SwiftUI** and name it `HobbitHydration`. Set the deployment target to **macOS 13.0**.
2. Delete the generated `ContentView.swift` and the generated `@main` app file, then add `HobbitHydrationApp.swift` from this repo.
3. Select the project → target → **Info** tab → add the key **Application is agent (UIElement)** = `YES`. This hides the Dock icon so the app lives only in the menu bar.
4. Build a standalone app:
   - **Product → Show Build Folder in Finder**, open `Products/Debug`, and copy `HobbitHydration.app` to your **Applications** folder, **or**
   - **Product → Archive → Distribute App → Custom → Copy App** for a Release build.
5. Open it from Applications, allow notifications when asked, and (optionally) switch on **Open at login** inside the app.

You no longer need Xcode to run it.

> **Sharing the built app?** Apps built without an Apple Developer ID are unsigned. Other Macs will block it at first; right-click the app → **Open** (or allow it in System Settings → Privacy & Security).

## How it works

| Thing | Rule |
| --- | --- |
| Daily goal | body weight (lb) ÷ 2 = ounces |
| Sip per reminder | goal ÷ (hours awake × 60 ÷ interval) |
| Reminder timing | random between 70% and 130% of your interval |
| Streak | +1 each day you reach your goal; resets if you miss a full day |
| Day boundary | local midnight |

Settings and progress are stored in `UserDefaults`.

## Customizing

All the fun lives in `HobbitHydrationApp.swift`:

- **Reminder messages** — the `lines` array in `Shire`
- **Vessels** — the `vessels` array at the top
- **Colors and fonts** — the `Theme` enum
- **Goal formula** — `Prefs.goal`
- **Timing randomness** — `Double.random(in: 0.7...1.3)` in `Shire.start()`

## Roadmap ideas

- Quiet hours
- Clickable "I drank it" button on the notification
- History chart
- Metric (ml) units

## License

MIT — do whatever you like. Stay hydrated. 🍺
