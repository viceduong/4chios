# 4chan API — engineering notes

Distilled from the [official docs](https://github.com/4chan/4chan-API) and the
[unofficial posting deep-dive](https://github.com/catamphetamine/imageboard/blob/master/docs/engines/4chan.md).
Everything the data layer needs to be correct.

## Hosts

| Host | Purpose |
| --- | --- |
| `a.4cdn.org` | JSON: boards, catalogs, threads, archives |
| `i.4cdn.org` | Media: full files, previews, thumbnails |
| `s.4cdn.org` | Static: spoiler placeholders, flags, icons |
| `sys.4channel.org` | Posting (multipart upload) |
| `sys.4chan.org` | Captcha challenge, Pass auth |

## Hard rules

1. **At most 1 request/second.** Enforced by the shared `RateLimiter` actor. Never bypass it.
2. **Thread polling interval ≥ 10 s.** Prefer 20–30 s, and back off on errors.
3. **Send `If-Modified-Since`** with the last `Last-Modified` value. `304` means nothing changed.
4. Refresh only when the thread has new activity; stop polling archived/closed threads.

## Endpoints

| Endpoint | Returns |
| --- | --- |
| `GET /boards.json` | All boards with limits, flags, cooldowns |
| `GET /{board}/catalog.json` | Every OP with up to 5 `last_replies` |
| `GET /{board}/{page}.json` | One index page (`threads` array) |
| `GET /{board}/threads.json` | `{page, threads:[{no, last_modified, replies}]}` — cheap change detection |
| `GET /{board}/thread/{op}.json` | Full thread: OP + `posts[]` |
| `GET /{board}/thread/{op}-tail.json` | Only posts after `tail_id`; exists when a thread is long (~>101 posts) |
| `GET /{board}/archive.json` | Archived thread numbers |

`last_modified` on each post is the value to echo back in `If-Modified-Since`.

### Tail API

Long threads answer with `{tail_id, tail_size, posts[]}` where `posts` starts after `tail_id`.
Request the tail with the previous `tail_id` to fetch only what is new. This is the correct way
to implement live threads without re-downloading a 1000-post thread every 30 seconds.

## Media

| Variant | URL | Notes |
| --- | --- | --- |
| Thumbnail | `https://i.4cdn.org/{board}/{tim}s.jpg` | 250 px OP, 125 px reply |
| Preview | `https://i.4cdn.org/{board}/{tim}m.jpg` | ≤1024 px, **only when `m_img == 1`** |
| Full | `https://i.4cdn.org/{board}/{tim}{ext}` | Original upload |
| Spoiler | `https://s.4cdn.org/image/spoiler-{board}.png` | `custom_spoiler` 1–8 → `spoiler-{board}{n}.png` |

Loading order is always thumbnail → preview → full. `ext` values: `.jpg .png .gif .pdf .swf .webm`
(official docs) and `.mp4` (added later by 4chan; treat as supported but defensive).

**`.webm` is the dominant video format and AVFoundation cannot decode VP8/VP9 on iOS 15.**
That is why `ChanMedia` exposes `MediaPlaybackEngine` and ships MobileVLCKit behind it.

## Post markup

Post bodies are HTML fragments, not Markdown. Render exactly these:

| Markup | Meaning |
| --- | --- |
| `<br>` | Newline |
| `<b>`, `<strong>` | Bold |
| `<i>`, `<em>` | Italic |
| `<u>` | Underline |
| `<s>` | Spoiler text (blur / tap to reveal) |
| `<span class="quote">` | Greentext |
| `<a class="quotelink" href="#p123">` | Link to post 123 → jump + highlight |
| `<a class="deadlink">` | Link to a deleted post |
| `<pre class="prettyprint">` | Code block |
| `<span class="sjis">` | Shift-JIS text |
| `[math]...[/math]` | LaTeX |
| `<wbr>` | Discard entirely |
| Anything else | Unwrap and keep the children |

Quote links are rewritten to a custom scheme (`ch4ios://post/{board}/{no}`) and intercepted with
SwiftUI's `OpenURLAction`, which is how `Text` gets per-run tap handling on iOS 15.

## Posting (opt-in, feature-flagged)

```
POST https://sys.4channel.org/{board}/post        Content-Type: multipart/form-data
  mode=regist   resto={op or 0}   name   email   com   flag
  upfile        spoiler            filetag
  t-challenge   t-response
Accept: application/json   →   {"tid":123,"pid":456}  |  {"error":"..."}
```

Captcha flow:

1. `GET https://sys.4chan.org/captcha?board={b}&thread_id={op}&ticket={t}`
2. Response: `challenge`, `ttl`, `cd`, `img`/`bg` (base64 PNGs) — the user drags `img` onto `bg`
   and types the shown characters.
3. Submit `t-challenge` + `t-response`. Respect the `pcd`/ticket cooldown dance.

Pass flow: `POST https://sys.4chan.org/auth` with `id`, `pin`, `long_login` → cookies
`pass_id` and `pass_enabled`, which bypass the captcha.

Cloudflare may challenge any of these requests. Isolate all of it behind `CaptchaProvider` so a
change never touches the browsing code, and keep posting behind a feature flag.

## Search & archives

- Remote search: `GET https://p.4chan.org/api/search?q=&o=&l=&b=` — undocumented and
  Cloudflare-protected. Optional, never the primary path.
- Local search: SQLite FTS5 over cached post bodies. Always available, always fast.
- Archives: FoolFuuka API on `desuarchive.org`, `archive.4plebs.org`, `archived.moe`
  (`/_/api/chan/search/`). Useful for dead threads; M7.

## Terms of service

- Do **not** put "4chan" in the app name or branding.
- Disclose that data comes from 4chan, with a link, in the About screen.
- Do not claim to be official; do not clone or rehost the site.
- Respect the rate limit. Abuse gets clients blocked.
