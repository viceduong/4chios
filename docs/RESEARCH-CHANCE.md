# Research: Chance (`moffatman/chan`) — what is worth adopting

**Date:** 2026-09-11
**Subject:** `https://github.com/moffatman/chan` (the app is called *Chance*)
**Question asked:** can its regex filter and saved thread/post/media features be adopted into 4chios?

## Verdict up front

**No code can be adopted. Three designs can, and two of them are worth doing.**

| Thing | Adoptable? | Why |
|---|---|---|
| Source code (any of it) | **No** | Written in Dart/Flutter; ours is Swift/UIKit+SwiftUI. Zero lines are portable, down to the widget layer. |
| Licence as-is | **No** | GPL-3.0. Copying or closely translating its code would relicense 4chios as GPL-3.0. |
| Filter **syntax** (4chanX-compatible) | **Yes — high value** | A grammar, not code. Users can paste existing 4chanX filter lists. |
| Filter **engine architecture** | **Yes — high value** | The layering (cache → regex group → manual override → reply-graph meta pass) solves problems we will hit. |
| Saved-item **model** (self-contained records, missing-item recovery, tags) | **Yes — high value** | Our saved posts currently degrade when the thread cache is dropped. |
| Saved-list **sort modes**, **undo**, **zombie detection** | **Yes — medium value** | Small, independent wins. |
| Its 5-pane master-detail Saved UI | **No** | iPad-first Flutter layout; our phone-first categories are the better fit. |

The legal line: **behaviour, syntax and architecture are not code.** I read its source to learn *what* it does and *how it is structured*, and everything below is written as a specification to reimplement in Swift. Nothing is translated line by line, and no Dart is copied into this repository (the local reference cache is now gitignored under `.local/`).

## What Chance is

| | |
|---|---|
| Language | Dart 97%, (0.9% Swift — the iOS shell) |
| Repo size | ~14 MB, 697 files |
| Licence | GPL-3.0 |
| Stars / forks | 521 / 21 |
| Last push | 2026-09-05 (actively maintained) |
| Platforms | iOS and Android, Flutter |
| Sites | multi-imageboard (4chan, 8kun-era sites, archives), not just 4chan |

Its feature list overlaps ours almost entirely (catalog, thread, gallery, webm, filters, saved collection, watched threads with notifications, captcha alignment). The differences that matter are below.

---

## 1. The filter system

### 1.1 Syntax

One filter per line. `#` at the start disables it, and a config block may contain comments because unparseable `#` lines are tolerated rather than thrown.

```
[#]label/pattern/flags[;qualifier][;qualifier]...
```

- `label` — optional display name, shown in the filter hit reason. `/` inside it is escaped as `%2F`.
- `pattern` — a regex, greedy up to the last `/`.
- `flags` — `i` = case-insensitive. `s` = **single-line**, i.e. `^`/`$` stop matching at line boundaries. Note this is the *inverse* of 4chanX, where `s` means dotall; Chance defaults to multiline matching, which is what post filtering actually wants. Worth copying the default, not the flag letter.
- Qualifiers, chained with `;`.

### 1.2 Anonymous first qualifier is a keyword, named ones take a value

| Qualifier | Effect |
|---|---|
| `highlight` | mark instead of hide |
| `top` | pin matching threads to the top of the catalog |
| `save` | auto-save matching threads |
| `watch` / `watch:push` / `watch:noPush` | auto-watch, optionally with push |
| `notify` | notify on match |
| `collapse` | collapse the post |
| `show` | force visible — overrides earlier filters |
| `hideReplies` | also hide the direct replies |
| `hideReplyChains` | also hide the entire reply subtree |
| `hideThumbnails` | hide the thumbnail, keep the post text |
| `type:a,b,c` | which fields the pattern is tested against |
| `boards:` / `board:` | scope to boards, supports `site/board` |
| `exclude:` | board exclusion |
| `site:` / `sites:`, `excludeSite:` / `excludeSites:` | multi-site scoping |
| `file:only` / `file:no` | has attachment or not |
| `thread` / `op:only`, `reply` / `op:no` | OP only, or replies only (`thread` is the 4chanX spelling) |
| `deleted:only` / `deleted:no` | deleted posts |
| `repliesToOP:only` / `repliesToOP:no` | whether it quotes the OP |
| `minReplied:` / `maxReplied:` | how many posts it quotes |
| `minReplyCount:` / `maxReplyCount:` | thread size |

Filter fields available to `type:` are richer than ours:

```
text, subject, name, filename, dimensions, postID, posterID, flag, flair, capcode, trip, email
```
default `subject, name, filename, text`.

Two of those stand out: **`posterID`** (the per-thread poster hash) and **`dimensions`**. `;type:posterID;hide` is how you mute one user in a thread, and `;type:dimensions;/^1x1$/` catches tracking pixels.

### 1.3 Engine architecture

Five layers, composed in this order. The ordering is the insight.

1. **`FilterCache`** — memoises the verdict per item in a weak map, keyed by imageboard. Regexes are not re-run when a cell is recycled. Relevant to us: we render through `UICollectionView` reuse, and our current engine runs on every cell configure.
2. **`FilterGroup<CustomFilter>`** — first match wins, stops at the first non-null result.
3. **`IDFilter`** — manual per-post `hide`/`show` sets. Composed *after* regex filters, so a manual decision always beats a pattern.
4. **`ThreadFilter`** — per-thread manual hides, plus "hide posts replying to a hidden post", plus hide-by-`posterID`.
5. **`MetaFilter`** — a second pass over the whole thread that propagates `hideReplies` / `hideReplyChains` transitively. It sorts by post id once, walks forward, and records which ids are "toxic"; a post whose `repliedToIds` includes a toxic id is itself hidden, with the reason string carried along so the UI can say *"In reply chain of 12345 (matched /spam/ filter)"*.

There is also a separate **`MD5Filter`** that hides posts by file hash, with a `depth` of 0/1/2 meaning "hide just this post / also its replies / also its whole chain". That is the cross-board repost filter.

Every filter returns `FilterResult(type, reason)`, and **the reason is user-visible**. The UI can explain why a post disappeared. We only have a stub action today; the reason string is a good idea on its own.

### 1.4 Gap against our filter engine

We have: field scoping, `/regex/flags`, exact matching, sfw/nsfw scopes, a stub action, per-rule enable, JSON storage (schema v3).

We lack, in rough order of value:

| Missing | Value |
|---|---|
| `highlight` (mark, don't hide) | **High** — the most-used action after hide |
| `hideReplies` / `hideReplyChains` | **High** — kills an entire derail in one rule |
| Manual hide/show override (`IDFilter`) | **High** — cheap for us, we just added the context menu |
| Count predicates (`min/maxReplyCount`, `min/maxReplied`) | Medium — "hide threads under 10 replies" |
| `posterID` field | Medium — muting one poster |
| `repliesToOP`, `file:only/no`, `op:only/no` | Medium |
| 4chanX-compatible syntax + multi-line paste | **High** — import/export, and users arrive with existing lists |
| Result caching | Medium — perf, not features |
| `MD5Filter` | Low — we have no md5 index; the API gives md5 per attachment |
| `top`, `save`, `watch`, `notify`, `collapse` | Low–Medium, and `save`/`watch` interact with features we already have |
| `deleted:only` | Low — we do not model deletions |
| `dimensions` field | Low |

---

## 2. The saved collection

### 2.1 It confirms our thread model

Saving a thread in Chance is `threadState.savedTime = Date`. The saved thread *is* the cached thread state with a marker — exactly our `bookmark` flag on the cached thread. No separate storage, so no duplication. Our design is right, independently arrived at.

### 2.2 Where they differ, and where they are better

**Saved posts and attachments are self-contained records.**

```dart
class SavedPost        { Post post; DateTime savedTime; }
class SavedAttachment  { Attachment attachment; DateTime savedTime; List<int> tags; String? savedExt; }
```

Both store the *whole object*, not a key. Ours stores a reference and resolves the snippet out of our `post` table at read time. That is why our Saved → Posts row degrades to "(no text)" if the thread cache is gone — which is exactly the situation where a saved post matters most. Chance's saved post still renders its text years later.

`tags` is a user-assignable integer set on saved attachments: user-defined categorisation *on top of* the type categorisation. We have Threads/Posts/Media; this would be an orthogonal axis (folders/labels).

`savedExt` exists because they transcode: a GIF or webm may be stored as `.mp4`, so the extension on disk differs from the remote one and must be recorded. We store the remote extension and never transcode, so it is not a gap today — but it is the reason our `SavedMediaStore.fileName(tim:ext:)` should keep ext as an input rather than derive it.

**Missing-item recovery.** They compute two sets at load: threads that no longer exist and attachments that are no longer on disk. `MissingThreadsControls` / `MissingAttachmentsControls` render a banner with a count, a *fixer* closure per item, and a give-up path. A saved thing that cannot be loaded is a first-class state with a repair action, not a silent blank row. We have nothing here: a deleted file currently shows the "no longer on the device" placeholder in the viewer with no way to re-fetch it.

**Sort modes for saved threads:** by title, by last post time, by the time it was saved, by the thread's own post time. We have one implicit order (save time).

**Undo on destructive actions.** `unsaveAllSavedThreads`, `unsaveAllSavedPosts`, `removeAllWatches`, `markAllWatchedThreadsAsRead` and history deletion all snapshot the affected records first, perform the delete, then show an undo toast that restores them. Our Settings "Delete all downloaded media" is immediate and irreversible.

**Zombie watches.** A watch whose thread has been pruned or archived is flagged `zombie`, and "Remove archived" clears them in bulk. We poll threads already, so detecting a 404 is nearly free.

**History clearing by time window** (this session / today / last week / all time), plus a setting to protect threads you posted in. We keep read state but have no history-clearing UI.

**Saved items are filterable.** `SavedAttachment implements Filterable`, so the same regex engine can hide things in your own saved list. Unusual but coherent once filters and saved items share a protocol.

### 2.3 Its Saved UI is not for us

`MultiMasterDetailPage5State` with five panes (watches, thread-or-post identifiers, thread+post combos, saved posts, saved attachments). That is an iPad multi-column layout. Our Threads/Posts/Media segmented control is the right shape for a phone.

---

## 3. Proposed adoption plan

Ordered by value per unit of risk. Each phase is independently shippable.

### Phase 1 — Saved items become self-contained (recommended first)

Small schema work, fixes a real degradation we already have.

1. Schema v8: `post_bookmark` gains a `json` column holding the post snapshot; write it on bookmark.
2. Schema v8: `saved_media` gains `tags` (nullable CSV/JSON) and an `on_disk_ext` column.
3. `SavedStore` resolves a saved post from its snapshot, falling back to the live `post` table (so nothing already saved is lost).
4. UI: a **missing** state for saved media whose file is gone, with a "Download again" action, reusing `MediaDownloader.saveSingle`.
5. UI: sort modes for the saved list (saved time / thread title / last post time).

*Effort: M. Risk: low. Touches ChanDB + SavedScreen + SavedStore only.*

### Phase 2 — Filter actions and manual overrides

1. Add `highlight` — render a highlighted background/accent bar on the post.
2. Add manual hide/show per post, persisted per thread, composed **after** regex filters so manual wins. Entry points: the long-press menu we added, plus a "show hidden" affordance that reveals what was hidden and why.
3. Add `hideReplies` and `hideReplyChains` via a meta pass over `PostGraph`, which we already build.
4. Surface `reason` text on every filtered post.

*Effort: M–L. Risk: medium — touches the thread render path, so it needs care with the diffable snapshot.*

### Phase 3 — Filter syntax and breadth

1. Extend the parser to accept the full qualifier vocabulary; keep our existing JSON storage and add a text representation per rule.
2. Import/export: paste a 4chanX list, get rules; export ours in the compatible form.
3. Add fields `posterID`, `dimensions`, `trip`, `capcode`, `flag`, `flair`, `email`.
4. Add count predicates and `repliesToOP` / `file:` / `op:` predicates.
5. Memoise filter verdicts per post id, invalidated when the rule set changes.

*Effort: L. Risk: low–medium (mostly parser and engine, well covered by unit tests — ChanCore is testable on Linux, so this is cheap to verify).*

### Phase 4 — Polish worth copying regardless

- Undo toast for destructive actions (media delete, unsave all).
- Zombie detection for watched threads.
- History clearing by time window.

*Effort: S each.*

## 4. Deliberately not adopted

| | Why |
|---|---|
| Any Dart source, translated or not | GPL-3.0 and a different language; a close translation is a derivative work. Reimplemented from the behaviour only. |
| Five-pane master-detail Saved layout | iPad-first; our phone-first categories are better here. |
| Multi-imageboard support | Out of scope — 4chios is a 4chan client. It is why `site:` qualifiers exist, so we would implement board scoping only. |
| `MD5Filter` | Needs a file-hash index we do not have and the 1 req/s budget makes re-fetching expensive. Revisit if we ever index md5s at fetch time, which we could: the API returns the md5 with each attachment. |
| `deleted:` predicates | We do not model deletion. |

## 5. Legal note

GPL-3.0 is copyleft. Reading it to learn behaviour is fine; copying code, or translating it closely enough to be a derivative work, would oblige us to license 4chios under GPL-3.0 and offer source to every recipient. The repo is public, but that is a licensing decision, not a technical one, and it is not one this document should make by accident. Everything in the plan above is specified from observed behaviour and is to be written fresh in Swift.

The reference copy of their sources used for this research lives in `.local/chance/`, which is now gitignored.
