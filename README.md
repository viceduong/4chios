# 4chios

A native, offline-first imageboard client for **iOS 15.6.1+**, built with SwiftUI and UIKit.
Aiming for Apollo-for-Reddit polish: smooth 60/120 fps scrolling, a real local database,
4chan-X-grade filters, live threads, and native posting.

> **Status:** `0.10.0` — feature-complete read + post client, AI summaries, catalog sorting. CI green.
> Full design lives in [`docs/PLAN.md`](docs/PLAN.md).

## Features

- **Boards** — full board list, search, favorites, work-safe badges
- **Catalog** — two-column card grid with thumbnails, reply/image counts, sticky/closed badges
- **Threads** — self-sizing post timeline, greentext, spoilers, code blocks, quote links that jump and flash
- **Live** — tail-API polling every 20s, incremental inserts, no scroll jumps
- **Media** — Nuke pipeline (memory + disk), animated GIF, pinch-zoom viewer, native mp4, **webm via VLCKit**
- **Offline** — every board/thread you open is cached in SQLite (GRDB); images cached on disk
- **Saved** — bookmarks + watchlist with unread reply counts and background notifications
- **Search** — instant offline full-text search (SQLite FTS5)
- **Filters** — keyword/regex/poster ID/tripcode/capcode/filename rules, per board or global
- **Posting** — replies and new threads, native captcha (drag + type) and 4chan Pass, photo attachments
- **Craft** — light/dark/OLED themes, adjustable type size, haptics, Dynamic Type, iOS 15 navigation backport

![CI](https://github.com/viceduong/4chios/actions/workflows/ci.yml/badge.svg)

## Why another client?

Every existing open-source client is missing a critical piece:

| Project | Missing |
| --- | --- |
| `swiftchan` | No database, no offline, no filters, no posting |
| `TheChan` | Abandoned, no offline, poor code quality |
| `NekoSurf` | Flutter engine cost on A9 devices |

`4chios` combines offline-first persistence, a real filter engine, live tail updates,
native posting (captcha + Pass), and a genuinely smooth UI on the oldest supported hardware.

## Stack

- **Swift 6 compiler, Swift 5 language mode** — iOS 15.0 deployment target
- **SwiftUI** shell + **UICollectionView** (compositional layout, diffable data source) for heavy lists
- **GRDB/SQLite** (WAL + FTS5) as the single source of truth
- **Nuke** image pipeline · **MobileVLCKit** for `.webm`, AVPlayer for `.mp4`
- **XcodeGen** + **GitHub Actions** — CI-only build loop, no local Xcode required

## Repository layout

```
App/                    Composition root (thin)
Packages/
  ChanCore/             Models, HTML→AttributedString, filters   (platform-agnostic)
  ChanAPI/              Endpoints, rate limiter, auth            (platform-agnostic)
  ChanDB/               GRDB schema, migrations, FTS5            (platform-agnostic)
  ChanMedia/            Image pipeline, playback engine          (Apple)
  ChanUI/               Design system, components, motion        (Apple)
  ChanFeatures/         Screens + stores                         (Apple)
Tests/                  App-level tests
docs/                   PLAN, ARCHITECTURE, API-NOTES, ADRs
```

**Hard rule:** `ChanCore`, `ChanAPI`, and `ChanDB` must never import UIKit, SwiftUI,
or AVFoundation. They compile and test on Linux, which is what makes the fast CI lane possible.

## Build & CI

Two lanes, both in [`.github/workflows/ci.yml`](.github/workflows/ci.yml):

1. **Core tests (ubuntu, seconds)** — `swift test` for the three platform-agnostic packages.
2. **iOS build (macOS)** — XcodeGen → `xcodebuild` (signing disabled) → unsigned `.ipa` artifact.

The unsigned `.ipa` installs directly with [TrollStore](https://github.com/opa334/TrollStore)
on iOS 14.0–16.6.1, which covers the 15.6.1 target. No Apple Developer account needed.

## AI providers

Summaries and chat run on General Compute (`gemma-4-31B-it`); turns that need
live web results route through OpenRouter's search plugin. What each provider
actually supports — and the probes that established it — is documented in
[`docs/AI-PROVIDERS.md`](docs/AI-PROVIDERS.md). Short version: General Compute
has no server-side search and no billing endpoint, but its function calling does
work.

## Legal

- Not affiliated with 4chan. Data is provided by 4chan via its public read API.
- Per the [4chan API rules](https://github.com/4chan/4chan-API), this app does not use
  "4chan" in its product name and identifies its data source in-app.
- Read-only by default; posting is opt-in and uses 4chan's own captcha/Pass flow.
