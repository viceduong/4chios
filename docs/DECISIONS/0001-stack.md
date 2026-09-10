# ADR 0001 — Stack and platform decisions

- **Date:** 2026-09-09
- **Status:** accepted
- **Context:** greenfield iOS client targeting iOS 15.6.1, developed with **no local Xcode**
  (Windows host), distributed outside the App Store.

## Decisions

### 1. Deployment target: iOS 15.0

The device runs 15.6.1. Targeting 15.0 leaves margin and costs nothing. Xcode 26.x still
supports iOS 15 deployment targets, so the current toolchain works.

### 2. Swift 6 compiler, Swift 5 language mode

Swift concurrency back-deploys to iOS 13.2+, so `async/await` and actors are available.
Swift 5 language mode avoids strict-concurrency churn in M0–M5; modules migrate to Swift 6 mode
individually, starting with `ChanCore`.

### 3. No The Composable Architecture

TCA requires iOS 16. Rejected. A small in-house unidirectional layer (`@MainActor` stores with
`Action`-style intents) gives the same testability without the floor or the dependency.

### 4. Hybrid SwiftUI + UIKit for lists

iOS 15 lacks `UIHostingConfiguration` (iOS 16) and SwiftUI `List` is not fast enough for
thousands of posts on A9 hardware. Catalog and thread use `UICollectionView` with compositional
layout and a diffable data source; everything else is SwiftUI.

### 5. GRDB as the source of truth

SwiftData requires iOS 17. Core Data is workable but verbose and weak at FTS. GRDB 7 supports
iOS 13+, has first-class migrations, `ValueObservation`, and FTS5 — and runs on Linux, which
keeps the fast CI lane alive.

### 6. MobileVLCKit for webm

AVFoundation cannot decode VP8/VP9 on iOS 15. FFmpegKit was retired in January 2025 and its
successor ships no prebuilt iOS xcframework. VLCKit is the only practical native path. It is
isolated behind `MediaPlaybackEngine` and feature-flagged so it can be removed without touching
feature code.

### 7. CI-only build loop with two lanes

No local Xcode. Therefore the domain layer must be Linux-buildable (`swift test`, seconds) and
only the UI pays for a macOS runner. Builds are unsigned; TrollStore fakesigns on install, so no
Apple Developer account is required.

### 8. Distribution: TrollStore + AltStore source

Apple removes imageboard clients from the App Store. TrollStore covers iOS 14.0–16.6.1
(including 15.6.1) with permanent, non-expiring installs. An AltStore source JSON covers other
devices.

### 9. Naming: 4chios

Per the 4chan API ToS the product name must not contain "4chan". "4chios" satisfies that while
staying recognisable. Bundle identifier `com.viceduong.ch4ios` (Xcode target `Ch4ios`, display
name `4chios`).

## Consequences

- The Linux lane is a hard architectural constraint, not a convenience.
- Webm support costs ~250 MB of binary; it is the main size lever if the app ever needs to shrink.
- Posting is the highest-risk feature and stays behind a flag from day one.
