# Architecture

## Module graph

```
                    ┌──────────────┐
                    │     App      │  composition root, DI, scene
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │ ChanFeatures │  screens + stores (SwiftUI + UIKit)
                    └──┬──┬──┬──┬──┘
          ┌────────────┘  │  │  └────────────┐
          │               │  │               │
   ┌──────▼─────┐  ┌──────▼──┐  ┌───▼─────┐  │
   │  ChanUI    │  │ChanMedia│  │ ChanAPI │  │
   └──────┬─────┘  └────┬────┘  └───┬─────┘  │
          │             │           │        │
          │        ┌────▼───────────▼────┐   │
          └────────►       ChanCore       ◄───┘
                   └──────────────────────┘
                            ▲
                       ┌────┴────┐
                       │  ChanDB │
                       └─────────┘
```

## The one hard rule

`ChanCore`, `ChanAPI`, and `ChanDB` **must not import UIKit, SwiftUI, AVFoundation, or Photos.**
They are pure Swift + Foundation and therefore compile and test on Linux. This is not a style
preference — it is the mechanism that makes the CI-only development loop viable:

- **Linux lane (seconds):** `swift test` for `ChanCore` and `ChanAPI` catches domain, parsing,
  URL, and filter regressions before a Mac runner is even allocated.
  (`ChanDB` runs on macOS instead: GRDB links SQLite's snapshot API, which Ubuntu's
  `libsqlite3` does not build.)
- **Apple lane (minutes):** `ChanDB` tests, then the iOS app build, simulator tests, and the
  unsigned `.ipa`. `ChanUI`/`ChanMedia`/`ChanFeatures` are iOS-only (UIKit, Nuke's macOS
  `NSImage` Sendable issue) and are compiled by the app build.

A leaked Apple import fails the Linux lane immediately. That is the guardrail.

## Layer responsibilities

| Module | Owns | Never does |
| --- | --- | --- |
| `ChanCore` | Domain types (`BoardID`, `PostNumber`), HTML→`AttributedString`, filter engine, error taxonomy | Networking, persistence, rendering |
| `ChanAPI` | Endpoint construction, DTOs, the 1 req/s rate limiter, conditional GETs, captcha/Pass auth | Touching the database |
| `ChanDB` | GRDB stack, schema + migrations, DAOs, FTS5 search, `ValueObservation` streams | Networking |
| `ChanMedia` | Nuke pipeline config, GIF handling, `MediaPlaybackEngine` (AVPlayer/VLCKit) | Deciding what to display |
| `ChanUI` | Theme tokens, shared components, bottom-sheet container, haptics, motion | Business logic |
| `ChanFeatures` | Screens, `@MainActor` stores, navigation routes, UIKit bridges | Direct SQL or HTTP |

## Data flow

```
View ──intent──► Store (@MainActor, ObservableObject)
                    │
                    ├─► UseCase (async) ─► Repository
                    │                          ├─► ChanAPI  (network, rate-limited)
                    │                          └─► ChanDB   (SQLite, source of truth)
                    │
                    └──state──► View   ◄── ValueObservation ──┘
```

The database is the single source of truth. A screen renders what is in SQLite; the network
only writes into SQLite. That is what makes offline browsing fall out for free rather than
being a separate feature.

## Concurrency

- `RateLimiter` is an `actor` shared by every caller; there is no way to bypass it.
- `DatabasePool` (GRDB) is the only writer; reads use the same pool.
- Stores are `@MainActor`; all I/O hops off the main actor.
- Thread updates arrive as `AsyncStream<ThreadEvent>`; tasks are cancelled on view disappear.
- Swift 6 language mode is adopted module-by-module, starting with `ChanCore`.

## Navigation

iOS 15 has no `NavigationStack`, so one `UINavigationController` bridge owns the stack and
exposes a typed `Route` enum (`push`, `pop`, `popToRoot`, `replace`). SwiftUI screens request
navigation through it. When the deployment target eventually rises to iOS 16, the bridge can be
swapped for `NavigationStack` without touching feature code.

## Heavy lists

The catalog and thread timeline use `UICollectionView` with compositional layout and a diffable
data source. Reasons:

1. iOS 15 has no `UIHostingConfiguration`, so SwiftUI cells would pay a hosting-controller cost.
2. A9 devices (iPhone 6s/8) must hold 60 fps with thousands of posts.
3. Diffable snapshots give correct animated insertion for live threads with no scroll jump.

Everything else — settings, search, gallery chrome, composer, sheets — is SwiftUI.

## Testing

| Layer | Where | What |
| --- | --- | --- |
| Unit | Linux | DTO decoding, URL building, HTML parser, filters, migrations |
| Integration | Linux | GRDB round-trips, FTS queries, `URLProtocol` fixtures |
| UI | macOS simulator | Snapshot tests per theme + Dynamic Type size |
| Performance | macOS simulator | XCTest metrics: cold launch, 1000-post scroll |
| Device | iOS 15.6.1 | Authoritative check — install the CI `.ipa` via TrollStore |

## CI/CD

Two lanes in `.github/workflows/ci.yml` (see the file for exact steps). Releases additionally
emit `build-manifest.json` with the commit SHA, toolchain versions, resolved dependencies, and
artifact checksums so any build can be reproduced byte-for-byte.
