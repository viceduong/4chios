# 4chios — SOTA 4chan client for iOS 15.6.1

> Per 4chan API ToS the shipped app **must not** contain "4chan" in its name/branding; "4chios" complies.
> Plan version: `0.4.0` · Date: 2026-09-09 · Status: **M0–M4, M6 implemented; CI green**
> Repository: https://github.com/viceduong/4chios

---

## 0. TL;DR

Build a **native SwiftUI + UIKit-hybrid** imageboard client targeting **iOS 15.6.1** (A9 → A15 devices),
distributed **outside the App Store via TrollStore / AltStore**, with an Apollo-for-Reddit-grade UX.

- **Stack:** Swift 6 compiler / Swift 5 language mode, SwiftUI for shell & light screens,
  `UICollectionView` + Compositional Layout + Diffable Data Source for the two heavy screens
  (catalog grid, thread timeline). No TCA (requires iOS 16).
- **Data:** GRDB/SQLite (WAL + FTS5) as the single source of truth; full offline browsing.
- **Media:** Nuke/NukeUI image pipeline; MobileVLCKit for `.webm`, AVPlayer for `.mp4`.
- **Correctness:** a global 1 req/s token-bucket actor, `If-Modified-Since`/ETag, `-tail.json` for live threads.
- **Differentiators:** offline-first, 4chan-X-grade filters, thread watcher + notifications,
  native posting with captcha **and** Pass, archive search, and genuinely smooth scrolling on an iPhone 8.

### Locked decisions (2026-09-09)

| Decision | Choice | Consequence |
|---|---|---|
| Build environment | **CI-only (GitHub Actions)** | No local Xcode. Domain layer must be platform-agnostic for a fast Linux test lane; device QA happens on the user's 15.6.1 device via TrollStore. |
| v1 scope | **Read-only first (M0–M5)** | Posting (M6) is a fast-follow, feature-flagged. |
| List engine | **Hybrid UIKit + SwiftUI** | `UICollectionView` for catalog + thread; SwiftUI everywhere else. |
| Video | **Bundle MobileVLCKit** | Native webm + mp4, isolated behind `MediaPlaybackEngine` + feature flag. |
| Name | **4chios** | Bundle `com.viceduong.ch4ios`, Xcode target `Ch4ios`, display name `4chios`. |
| Repository | **viceduong/4chios** (public) | Free macOS Actions minutes; unsigned `.ipa` artifacts. |

---

## 1. Research — the open-source landscape

### 1.1 Existing iOS clients

| Project | Stack | ★ | Last push | Assessment |
|---|---|---|---|---|
| [vanities/swiftchan](https://github.com/vanities/swiftchan) | SwiftUI + MVVM, CocoaPods (`FourChanAPI`, `URLImage`, `MobileVLCKit`), GPL-3 | 25 | 2026-08 | Closest modern app. Rich settings, VLC webm. **No DB/offline, no posting, no filters, no tests.** |
| [TheChanDev/TheChan](https://github.com/TheChanDev/TheChan) | Obj-C/Swift + MobileVLCKit, GPL-3, iOS 14+ | 12 | archived-ish | Most feature-complete (posting + captcha, gallery). Author abandoned it; code quality poor. |
| [NekoSurf/NekoSurf](https://github.com/NekoSurf/NekoSurf) | Flutter, GPL-3 | 78 | active | Most polished UX today, AltStore/SideStore + TestFlight. **Not native**, Flutter engine cost on A9. |
| [ArtichOwO/4channer](https://github.com/ArtichOwO/4channer) | SwiftUI, GPL-3 | 10 | 2022 | Read-only toy. |
| iChan (`egoistos`, `Zchandev`) | cross-platform | — | 2024 | webm + webm→mp4 converter, sideload only, closed-ish. |
| Channy, Dokusha, CocoaChan, Bump, Chanology | various | <15 | dead | Reference only. |
| [ccd0/4chan-X](https://github.com/ccd0/4chan-X) | JS userscript | 1k+ | active | **Gold standard for feature depth** (filters, inline quoting, thread watcher). Mine it for spec. |

**Verdict:** nobody has combined (a) native performance on iOS 15, (b) offline-first persistence,
(c) 4chan-X-grade filtering, (d) live thread updating, (e) native posting. That is the gap.

### 1.2 4chan API (authoritative facts)

Domains: `a.4cdn.org` (JSON) · `i.4cdn.org` (media) · `s.4cdn.org` (static) · `sys.4chan.org` (post/auth).

Endpoints:

| Endpoint | Use |
|---|---|
| `/boards.json` | board list + per-board limits/flags |
| `/{board}/catalog.json` | catalog (OPs + `last_replies`) |
| `/{board}/{page}.json` | index page |
| `/{board}/threads.json` | thread IDs + `last_modified` + `replies` |
| `/{board}/thread/{op}.json` | full thread |
| `/{board}/thread/{op}-tail.json` | **incremental** thread update (`tail_id`, `tail_size`; exists ~>101 replies) |
| `/{board}/archive.json` | archived thread IDs |

Hard rules:

1. **≤ 1 request/second** (global).
2. Thread refresh ≥ 10 s (prefer more).
3. Send `If-Modified-Since`; handle `304`.
4. **ToS:** no "4chan" in the app name/branding, must disclose 4chan as the data source with a link,
   must not claim to be official, must not clone/rehost.

Media:

- Thumbnail `https://i.4cdn.org/{board}/{tim}s.jpg` (250 px OP / 125 px reply)
- Mid-size `https://i.4cdn.org/{board}/{tim}m.jpg` when `m_img == 1` (≤1024 px) — **key for fast hi-res preview**
- Full `https://i.4cdn.org/{board}/{tim}{ext}`
- `ext` ∈ `.jpg .png .gif .pdf .swf .webm` (docs) — `.mp4` support was added by 4chan (~Nov 2024, confirmed via 4chan-X); treat as supported but defensive.
- Spoilers: `spoiler`/`custom_spoiler` → `s.4cdn.org/image/spoiler.png`, `spoiler-{board}{n}.png`.

Post markup to render: `<br>`, `<b>/<strong>`, `<i>/<em>`, `<u>`, `<s>` (spoiler),
`<span class="quote">` (greentext), `<a class="quotelink" href="#pN">` (post link),
`<a class="deadlink">`, `<pre class="prettyprint">` (code), `<span class="sjis">`, `[math]`,
`<wbr>` (discard), and unknown tags → unwrap children.

Posting (unofficial but stable):

- `POST https://sys.4channel.org/{board}/post` `multipart/form-data`,
  `mode=regist`, `resto`, `name`, `email`, `com`, `flag`, `upfile`, `spoiler`, `filetag`,
  `t-challenge`, `t-response`; `Accept: application/json` → `{tid, pid}` or `{error}`.
- Captcha: `GET https://sys.4chan.org/captcha?board=&thread_id=&ticket=` → `challenge`, `ttl`,
  `cd`, `img`/`bg` (base64) → drag-to-align + type; `pcd`/`ticket` cooldown dance; CF may interfere.
- Pass: `POST https://sys.4chan.org/auth` (`id`, `pin`, `long_login`) → `pass_id`/`pass_enabled` cookies → bypass captcha.
- Search: `GET https://p.4chan.org/api/search?q=&o=&l=&b=` (undocumented, CF-protected) — experimental.
- Archives: FoolFuuka API on `desuarchive.org`, `archive.4plebs.org`, `archived.moe` (`/_/api/chan/search/`).

---

## 2. Research — iOS 15.6.1 platform constraints

**Toolchain:** Xcode 26.x still supports deployment targets **iOS 15+** (Xcode 26.6 lists iOS 15–26.5).
Xcode 26 requires macOS Sequoia 15.6+. Swift concurrency (async/await, actors, `@MainActor`)
back-deploys to iOS 13.2+, so it is fully available.

**Not available on iOS 15** (plan around these):

| API | Min iOS | Workaround |
|---|---|---|
| `NavigationStack` / `NavigationSplitView` | 16 | `UINavigationController` bridge (single source of navigation truth) |
| `UIHostingConfiguration` | 16 | UIKit cell subclasses / `UIHostingController` hosting |
| `@Observable` / Observation | 17 | `ObservableObject` + `@Published` |
| SwiftData | 17 | GRDB |
| `.presentationDetents` | 16 | custom bottom-sheet container |
| `ShareLink`, `ImageRenderer`, `Charts` | 16 | `UIActivityViewController`, `UIGraphicsImageRenderer`, custom charts |
| `.scrollPosition`, `.symbolEffect`, `contentTransition` | 17/16 | `UIScrollView` APIs, manual animations |

**Available on iOS 15** (use freely): `.searchable`, `.refreshable`, `.task`, `AsyncImage`,
`LazyVGrid`/`LazyVStack`, `matchedGeometryEffect`, `.safeAreaInset`, `OpenURLAction`,
`AttributedString` + `Text(AttributedString)`, `.swipeActions`, `.badge`, `Canvas`, `Material`,
`@FocusState`, `.overlay(alignment:)`, `BGAppRefreshTask`.

**Dependency compatibility:**

- **The Composable Architecture → excluded** (requires iOS 16). Use a lightweight in-house unidirectional layer.
- **GRDB 7** → iOS 13+, Swift 6.1+/Xcode 16.3+ ✅
- **Nuke 12 / NukeUI** → iOS 13+ ✅. ⚠️ NukeUI 12 no longer plays GIFs → pair with **Gifu** (or SDWebImageSwiftUI) for animated GIF.
- **MobileVLCKit 3.7.3** (Feb 2026) → iOS 8.4+, but **~250 MB** uncompressed / ~385 MB xcframework. LGPL-2.1 → link dynamically.
- **FFmpegKit retired Jan 2025**; FFmpegKitNext ships source-only (no prebuilt iOS xcframework) → **VLCKit is the pragmatic webm path**.
- **Performance:** iOS 15.6.1 spans A9 (iPhone 6s) → A15 (13 Pro, 120 Hz ProMotion). This is why heavy lists use UIKit.

**Distribution:** App Store is not viable (Apple removed TheChan; 4chan content policy).
**TrollStore supports iOS 14.0–16.6.1 → 15.6.1 is fully covered** (permanent, no expiry, no dev account).
AltStore/SideStore (7-day refresh) + an AltStore source JSON for updates covers other devices.

---

## 3. Product definition

### 3.1 Non-negotiables (SOTA bar)

1. **Smoothness:** locked 60 fps on A9, 120 fps on ProMotion; no jank on a 1000-post thread.
2. **Offline-first:** every board/thread you open is browsable offline, with media cached on demand.
3. **Live threads:** tail-API polling with animated insertion, "N new posts" pill, no scroll jumps.
4. **Native posting:** captcha + Pass, drafts, cooldowns, clear error mapping.
5. **4chan-X-grade filters:** keyword/regex, poster ID, tripcode, capcode, thread hiding, (You) highlighting.
6. **Craft:** haptics, custom transitions, hero image zoom, OLED black theme, Dynamic Type, VoiceOver.

### 3.2 Deliberate non-goals (v1)

- Multiple imageboards (2ch/8kun) — 4chan only, but behind a provider protocol.
- Cloud sync / accounts / analytics — none. Local-only, no telemetry.
- In-app purchases, ads, or any server component.

---

## 4. Stack decisions

| Concern | Choice | Rationale |
|---|---|---|
| Language | Swift 6 compiler, **Swift 5 language mode** initially | iOS 15 back-deployment; migrate to Swift 6 mode module-by-module |
| Project gen | **XcodeGen** (or Tuist) + SPM | No `.xcodeproj` merge hell; reproducible |
| UI | SwiftUI shell + UIKit for catalog/thread lists | iOS 15 lacks `UIHostingConfiguration`; UIKit wins on A9 |
| State | In-house `Store` (ObservableObject) + unidirectional `Action`/`Reducer`-lite | TCA needs iOS 16 |
| DI | tiny `AppEnvironment` struct + protocols | Zero-dependency, testable |
| Persistence | **GRDB 7** (SQLite WAL + FTS5) | Mature, iOS 13+, fast, migrations, FTS |
| Networking | `URLSession` + async/await + actors | No deps; full control of caching/rate limit |
| Images | **Nuke + NukeUI** + **Gifu** | Best perf; explicit GIF support |
| Video | protocol `MediaPlaybackEngine`: **AVPlayer** (mp4) + **MobileVLCKit** (webm) | AVFoundation cannot decode VP8/VP9 on iOS 15 |
| HTML → text | in-house tokenizer → `AttributedString` (SwiftSoup as fallback only) | Control, no WebView, fast |
| Lint/format | SwiftLint + SwiftFormat | CI-enforced |
| CI | GitHub Actions macOS runner + fastlane | Unsigned `.ipa` + AltStore source artifact |

---

## 5. Architecture

```
Yotsuba/
├─ App/                     # composition root, scene, tab bar, deep links, DI wiring
├─ Packages/
│  ├─ ChanCore/             # models, IDs, HTML→AttributedString, filters engine, formatting, errors
│  ├─ ChanAPI/              # endpoints, DTOs, RateLimiter actor, HTTP cache, retry/backoff, auth (pass/captcha)
│  ├─ ChanDB/               # GRDB schema, migrations, DAOs, FTS5, reactive observation
│  ├─ ChanMedia/            # Nuke pipeline config, disk cache, GIF, MediaPlaybackEngine, prefetch
│  ├─ ChanUI/               # design tokens, components (cards, pills, sheets), haptics, transitions
│  └─ Features/
│     ├─ BoardList/  Catalog/  Thread/  Gallery/  Composer/
│     └─ Watchlist/  Search/   Filters/ Settings/
└─ docs/                    # PLAN.md, ARCHITECTURE.md, API-NOTES.md, DECISIONS/*.md
```

**Platform-agnostic core (critical for the CI-only loop):** `ChanCore`, `ChanAPI`, and `ChanDB`
import **no UIKit/SwiftUI/AVFoundation** — pure Swift + Foundation + GRDB. That lets ~70% of the
codebase compile and unit-test on a cheap `ubuntu-latest` runner with `swift test` in seconds,
while only the UI packages need the slower macOS runner. Any Apple-only import leaking into the core
is treated as a build error.

**Data flow:** `View → Store (MainActor, ObservableObject) → UseCase → Repository → (ChanAPI | ChanDB) → Store`.

**Concurrency:** `NetworkActor` (rate-limited) and `DatabaseWriter` (GRDB) are actors.
Stores are `@MainActor`. Thread updates stream via `AsyncStream<ThreadEvent>`.
DB observation → `ValueObservation` → store → view.

**Single navigation source of truth:** one `UINavigationController` bridge exposing
`push/pop/popToRoot/replace` + a typed `Route` enum; SwiftUI views request navigation through it.
This gives iOS 16-like programmatic navigation on iOS 15 and survives a future `NavigationStack` swap.

---

## 6. Data model (GRDB)

```
boards(board_id PK, title, ws_board, per_page, pages, bump_limit, image_limit,
       max_filesize, max_webm_filesize, max_webm_duration, max_comment_chars,
       spoilers, custom_spoilers, user_ids, country_flags, is_archived, cooldowns_json, flags_json)
threads(board_id, op_no PK, sub, com, time, last_modified, replies, images, sticky,
        closed, archived, bumplimit, imagelimit, unique_ips, semantic_url, seen_at)
posts(board_id, no PK, resto, op_no, time, name, trip, id, capcode, country, country_name,
      board_flag, flag_name, subject, com_html, com_plain, since4pass, is_op,
      replies, images, last_modified)
attachments(post_no PK, board_id, tim, filename, ext, fsize, md5, w, h, tn_w, tn_h,
            spoiler, custom_spoiler, m_img, filedeleted)
bookmarks(board_id, op_no PK, note, added_at, last_seen_reply)
watchlist(board_id, op_no PK, notify, added_at, last_seen_reply, last_checked)
filters(id PK, board_id NULL, kind, pattern, action, enabled, created_at)   -- kind: keyword|regex|poster|tripcode|capcode|filename
read_state(board_id, op_no PK, last_read_no, scroll_offset)
drafts(id PK, board_id, resto, name, email, subject, com, file_path, spoiler, updated_at)
posts_fts(com_plain, content='posts', content_rowid='rowid')               -- FTS5
meta(key PK, value)                                                        -- schema_version, etags, last_catalog_sync
```

All writes go through repositories; every mutation is a GRDB transaction.
Migrations are additive and versioned; a migration test suite runs the full chain from empty.

---

## 7. Networking & rate limiting

- `RateLimiter` actor: global token bucket at **1 req/s**, per-host, with priority lanes
  (`userInitiated > threadPoll > prefetch > backgroundSync`) and cancellation.
- Conditional GETs: persist `ETag`/`Last-Modified` per URL in `meta`; treat `304` as success.
- Thread polling uses `-tail.json` when available, full fetch otherwise; backoff on errors
  (10 s → 20 s → 40 s, cap 120 s), pause when app backgrounded or screen off.
- Gzip via `URLSession` defaults; realistic UA; cookie storage only for the Pass flow.
- Catalog sync for favorites is staggered across the 1 req/s budget; no request storms.
- Everything is cancel-on-disappear; no orphaned tasks.

---

## 8. UI/UX — the Apollo-grade layer

**Design system (`ChanUI`):** semantic color tokens, 3 themes (Light / Dark / OLED Black) + accent picker,
type scale, spacing/radius scale, elevation, motion tokens (spring curves, durations),
haptics wrappers, and a `BottomSheet` container (replaces `.presentationDetents`).

**Signature interactions:**

- Floating blurred tab bar (Boards · Watchlist · Search · Settings) with scroll-driven collapse.
- Board switcher: horizontal swipe between favorite boards with a subtle parallax indicator.
- Catalog: card grid (thumbnail, title, reply/image counts, sticky/closed/archived badges,
  new-reply dot) with a grid↔list toggle and sort modes (bump/newest/replies/images).
- Thread: card-based posts, OP as a hero card, reply lines, (You) highlight, tap `>>N` to
  **jump + flash-highlight** the target, long-press for a quote preview popover.
- Inline media: tap thumbnail → **hero zoom transition** into the gallery; pinch/pan/double-tap zoom;
  swipe-down to dismiss; GIF autoplay with a mute/pause control; video plays inline with custom controls.
- Composer: bottom sheet, live preview using the same HTML renderer, attachment picker
  (Photos/Files/Camera), spoiler toggle, captcha align-slider + text field, cooldown countdown.
- Filters: a real rule builder with live match counts, per-board or global, reversible.
- "N new posts" pill + smooth insertion without losing scroll position.
- Accessibility: Dynamic Type up to AX5, VoiceOver labels/rotors, Reduce Motion/Transparency,
  high-contrast; full iPad layout (split view, keyboard shortcuts, pointer support).

**Rendering:** one HTML→`AttributedString` compiler shared by catalog/thread/composer-preview.
Quote links become custom-scheme URLs (`yotsuba://post/{board}/{no}`) intercepted via `OpenURLAction`
so `Text` gains per-run tap handling on iOS 15. Spoilers render as blurred, tap-to-reveal runs.
Code blocks get a monospaced, horizontally-scrollable container.

---

## 9. Media pipeline

- Three-tier loading: thumbnail → mid-size (`m_img`) → full; progressive/blur-up placeholders.
- Nuke pipeline: memory + disk cache with size/cost limits, request coalescing, priority,
  prefetching scoped to visible ± 1 screen, cancel on scroll-off.
- GIF via Gifu (NukeUI 12 dropped animation); `Reduce Motion` disables autoplay.
- Video: `MediaPlaybackEngine` protocol; AVPlayer for `.mp4`, MobileVLCKit for `.webm`.
  Single custom player surface, muted-by-default unless the board sets `webm_audio`.
  VLCKit is isolated behind the protocol and **feature-flagged** so the binary can ship without it
  if size/compliance becomes a problem (graceful "open in Safari" fallback).
- Save to Photos (`PHPhotoLibrary`), share sheet, "save all media in thread".

---

## 10. Posting pipeline

```
Composer → PostRequest → CaptchaProvider (native challenge | Pass cookie | none)
        → multipart POST sys.4channel.org/{board}/post → {tid,pid} | {error}
        → optimistic local insert + deep-link to new post
```

- Captcha solved natively: superimpose `img` on `bg`, drag-align, type the text → `t-challenge`/`t-response`.
- Pass: `POST /auth`, store `pass_id`/`pass_enabled` in the keychain-adjacent cookie store; bypass captcha.
- Full error taxonomy mapped to human messages (cooldown, closed thread, banned, spam, wrong captcha).
- Drafts persisted; retry-safe; never double-posts (idempotency guard around the in-flight request).

---

## 11. Testing & QA

- **Unit:** DTO decoding (fixture JSON incl. edge cases), rate limiter, HTML parser golden files,
  filter engine, URL builders, error mapping.
- **DB:** migration chain from empty, WAL concurrency, FTS queries, offline round-trips.
- **Integration:** recorded HTTP fixtures via `URLProtocol` (no live 4chan in CI).
- **UI:** snapshot tests for catalog/thread/composer across themes + Dynamic Type sizes.
- **Performance:** XCTest metrics for cold launch, catalog scroll, 1000-post thread scroll on the
  oldest supported device class; frame-time instrumentation in Debug.
- **Manual matrix:** iPhone 6s/8/X/13 Pro × iOS 15.6.1, light/dark/OLED, RTL, AX5, airplane mode.

---

## 12. Build, CI, distribution, reproducibility (CI-only)

There is **no local Xcode** on the development host, so the pipeline is the compiler.

**Two-lane CI:**

1. **Fast lane — `ubuntu-latest`:** `swift test` for `ChanCore` / `ChanAPI` / `ChanDB`.
   Seconds, not minutes; catches ~70% of regressions before the Mac runner is even scheduled.
2. **Apple lane — `macos-26` runner** (pinned Xcode): `xcodegen generate` → `xcodebuild build`
   → `xcodebuild test` on the default simulator → SwiftLint/SwiftFormat → archive with
   `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → wrap `.app` in `Payload/` → **unsigned `.ipa`**
   → upload artifact. TrollStore fakesigns on install, so **no Apple Developer account is required**.

**Device QA loop:** CI produces the `.ipa` → user installs on the 15.6.1 device via TrollStore →
reports issues. Because the minimum-OS runtime may not be installable on the runner, this on-device
pass is the authoritative iOS 15.6.1 check; CI simulators validate logic and UI regressions only.

**Reproducibility:** every release emits `build-manifest.json` (commit SHA, Xcode/Swift versions, SDK,
deployment target, resolved dependency versions, build config, artifact checksums) next to the `.ipa`.
`Package.resolved` and the Xcode version are pinned and committed.

**Distribution:** TrollStore `.ipa` (primary, iOS 15.6.1) + `altstore-source.json` for
AltStore/SideStore updates. No App Store. The About screen discloses "Data provided by 4chan" with a
link, per the API ToS.

**Repository:** `viceduong/4chios` (public, created 2026-09-09). GitHub REST automation uses the
classic PAT stored in `~/.aich/config.json`; there is no `gh` CLI on the host.

---

## 13. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| MobileVLCKit size (~250 MB) & LGPL | App bloat, compliance | Isolate behind protocol + feature flag; consider a trimmed VLCKit build; dynamic linking |
| Captcha/Cloudflare changes | Posting breaks | Feature-flag posting; Pass path as fallback; isolate in `CaptchaProvider` |
| 1 req/s global limit | Slow multi-board refresh | Priority lanes + staggered sync + aggressive conditional GETs |
| iOS 15 SwiftUI gaps | Missing UX primitives | UIKit bridges for nav, sheets, heavy lists (already planned) |
| A9 performance | Jank | UIKit collection views, cell reuse, attributed-text layout cache, image downsampling |
| 4chan ToS / App Store | Legal/distribution | No "4chan" branding, source disclosure, sideload-only |
| No local Xcode (Windows host) | Can't build here | **Need a Mac or CI-based build loop** (see open decisions) |
| Undocumented search API | Feature may break | Treat remote search as optional; local FTS5 is primary |

---

## 14. Milestones

| # | Milestone | Deliverable | Exit criteria |
|---|---|---|---|
| **M0** | Scaffold & CI | XcodeGen project, 7 SPM modules, lint, CI green, unsigned `.ipa` | CI builds + tests on every push | ✅ |
| **M1** | Data core | ChanAPI client, rate limiter, GRDB schema + migrations, boards list, offline cache | Boards + catalog browsable offline | ✅ |
| **M2** | Browsing | Catalog grid/list, thread timeline (UIKit), HTML renderer, jump-to-post, pull-to-refresh | 60 fps on iPhone 8 with a 500-post thread | ✅ |
| **M3** | Media | Nuke pipeline, gallery with hero zoom, GIF, mp4/webm player, save/share | All media types play/zoom smoothly | ✅ (webm via VLCKit) |
| **M4** | Live & offline | Tail polling, watchlist, notifications, FTS search, bookmarks | New posts appear without scroll jump | ✅ |
| **M5** | Craft | Themes, motion, haptics, a11y, iPad, perf passes | AX5 + 120 fps on 13 Pro | partial |
| **M6** | Posting | Composer, captcha, Pass, drafts, error taxonomy | Successful reply + new thread on-device | ✅ (drafts pending) |
| **M7** | Power features | Filter rule builder, archive search, export/backup | 4chan-X parity on filters | filters ✅, archive pending |
| **M8** | Release | TrollStore `.ipa`, AltStore source, docs, build manifest | Install + browse on a clean 15.6.1 device | in progress |

Suggested cadence: M0–M2 are the critical path; M6 is the highest-risk milestone and should be
feature-flagged from day one.

### M0 breakdown (first PR series)

1. `git init` + `.gitignore` (Xcode, SwiftPM, macOS) + repo docs skeleton.
2. `project.yml` (XcodeGen) defining the app target (iOS 15.0 deployment target), 7 SPM modules,
   and the `Yotsuba.entitlements` / Info.plist (background refresh, photo add, no analytics).
3. Package manifests: platform-agnostic core (no Apple imports) + Apple-only UI packages.
4. `Package.swift` dependency pins: GRDB 7, Nuke/NukeUI 12, Gifu, MobileVLCKit 3.7.x.
5. GitHub Actions: `ci.yml` (ubuntu fast lane + macos-26 Apple lane + unsigned `.ipa` artifact).
6. SwiftLint + SwiftFormat configs, `.swift-version`/Xcode pin, PR template, `CONTRIBUTING.md`.
7. `docs/ARCHITECTURE.md` + `docs/API-NOTES.md` + `docs/DECISIONS/0001-stack.md`.

Exit criteria: CI green on an empty-but-wired app, unsigned `.ipa` downloadable from the run,
installs and launches on the 15.6.1 device.

---

## 15. Decisions

Resolved 2026-09-09:

1. **Build environment** → CI-only (GitHub Actions); two-lane pipeline. ✅
2. **v1 scope** → read-only first (M0–M5); posting feature-flagged as fast-follow. ✅
3. **Heavy-list rendering** → hybrid UIKit + SwiftUI. ✅
4. **Video** → bundle MobileVLCKit behind `MediaPlaybackEngine`. ✅

Still open:

5. **App name / branding** → **4chios**. ✅
6. **Distribution extras** — TrollStore + AltStore source is the default; add TestFlight later only if wanted.
7. **GitHub remote** → **viceduong/4chios** (public). ✅

---

## Appendix — references

- 4chan API docs — https://github.com/4chan/4chan-API
- Unofficial posting/captcha/auth deep-dive — https://github.com/catamphetamine/imageboard/blob/master/docs/engines/4chan.md
- 4chan-X feature spec — https://github.com/ccd0/4chan-X
- Xcode SDK/deployment matrix — https://developer.apple.com/xcode/system-requirements/
- TrollStore compatibility — https://github.com/opa334/TrollStore
- GRDB — https://github.com/groue/GRDB.swift · Nuke — https://github.com/kean/Nuke
- MobileVLCKit — https://code.videolan.org/videolan/VLCKit
- FoolFuuka archive API — https://foolfuuka.readthedocs.io/en/latest/code_guide/documentation/api.html
