# Contributing

## Ground rules

1. **Respect the boundary.** `ChanCore`, `ChanAPI`, and `ChanDB` must not import UIKit,
   SwiftUI, or AVFoundation. The Linux CI lane enforces this.
2. **Respect the API.** 4chan allows at most **1 request/second** and asks for
   `If-Modified-Since` on thread polls. Never add a code path that can burst past the
   shared rate limiter in `ChanAPI`.
3. **No secrets in the repo.** Tokens live in `~/.aich/config.json` or the environment.
4. **No analytics, no telemetry, no third-party servers.**

## Workflow

- Branch from `main`, open a PR, keep it focused.
- Conventional commits: `feat(catalog): ...`, `fix(api): ...`, `docs(plan): ...`, `chore(ci): ...`.
- CI must be green: core tests, iOS build, and the unsigned `.ipa` artifact.
- New behavior needs a test. Bug fixes need a regression test.
- Update the relevant doc when you change a decision: `docs/PLAN.md`, `docs/ARCHITECTURE.md`,
  or a new ADR under `docs/DECISIONS/`.

## Local development

There is no requirement for a local Mac — CI is the compiler. If you do have Xcode:

```bash
brew install xcodegen swiftlint swiftformat
xcodegen generate --spec project.yml
xcodebuild -project Ch4ios.xcodeproj -scheme Ch4ios \
  -destination 'generic/platform=iOS' build
swift test --package-path Packages/ChanCore
```

## Installing a build on device

1. Download the `Ch4ios-ipa` artifact from the latest CI run.
2. Unzip it and open the `.ipa` in TrollStore (iOS 15.6.1 supported).
3. Launch. Report anything broken with the run URL attached.
