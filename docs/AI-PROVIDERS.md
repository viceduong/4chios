# AI provider capabilities

Findings verified against the live services on 2026-09-10, with the probes used,
so this does not need re-investigating.

## General Compute — `https://api.generalcompute.com/v1`

### The entire API surface is five routes

From their published OpenAPI spec (`https://docs.generalcompute.com/api-reference/openapi.json`):

```
POST  /v1/chat/completions
POST  /v1/models/list
GET   /v1/public/models
GET   /health
GET   /health/ready
```

Models: `gemma-4-31B-it`, `gpt-oss-120b`, `deepseek-v3.1`, `deepseek-v3.2`, `minimax-m2.7`.

### Web search: not available

Six independent confirmations:

| Probe | Result |
| --- | --- |
| Docs: `search` / `browse` / `web_search` / `online` across all 16 pages | **0 mentions** |
| OpenAPI spec: `web_search`, `web search` | **0 occurrences** |
| `plugins: [{"id":"web"}]` (OpenRouter style) | HTTP 200, **silently ignored** — byte-identical 3-token reply |
| `web_search_options: {}` (OpenAI style) | HTTP 200, **silently ignored** — byte-identical reply |
| `tools: [{"type":"web_search"}]` | HTTP 400 `"tools[0]" must have a "function" key` |
| `model: "gemma-4-31B-it:online"` | HTTP 404 `model_not_found` |

The control question ("what is the current stable Python, and today's date?")
returned literally `NO LIVE DATA` — the model knows it cannot browse.

Note the third and fourth rows: unknown parameters are **silently accepted**, so
the absence of an error is not evidence of support. Only `tools` is validated.

### Function calling: available, and verified

The 400 above proves `tools` is parsed. With a proper definition the model emits
a tool call as expected:

```json
{ "type": "function",
  "function": { "name": "web_search",
                "parameters": { "type": "object",
                                "properties": { "query": { "type": "string" } },
                                "required": ["query"] } } }
```

→ `finish_reason: "tool_calls"`, `content: ""`,
`tool_calls: [{ "name": "web_search",
                "arguments": "{\"query\":\"current stable release version of Python\"}" }]`

So General Compute **can decide to search but cannot perform one**. Tools run on
the client; there is no built-in browsing or retrieval.

### Credit balance: not available

No billing endpoint exists. `credit`, `balance` and `billing` appear **0 times**
in the spec, and every plausible path 404s:

```
/v1/credits  /v1/balance  /v1/account  /v1/me  /v1/usage  /v1/billing
/v1/dashboard/billing/credit_grants  /v1/dashboard/billing/subscription
```

What the API *does* return is a `usage` object on every completion
(`prompt_tokens`, `completion_tokens`, `total_tokens`, plus latency and
throughput). Published prices cover `minimax-m2.7` ($0.28/$1.20 per 1M),
`deepseek-v3.2` ($0.25/$0.38), `deepseek-v3.1` ($0.21/$0.79) and
`gpt-oss-120b` ($0.21/$0.79). **Gemma is not in that table**, so the app reports
tokens without a dollar figure for it rather than guessing.

## OpenRouter — `https://openrouter.ai/api/v1`

Has a server-side search plugin, verified working:

```json
{ "model": "google/gemini-2.5-flash-lite",
  "plugins": [{ "id": "web", "max_results": 10 }], ... }
```

Citations come back as `choices[0].message.annotations[].url_citation` with
`{ url, title }`.

### Pricing is per request, not per result

Each request includes **up to 10 results**; further results cost $0.001 each.
Asking for two results costs exactly the same as asking for ten, so a small
`max_results` saves nothing and only weakens the answer.

| Engine / mode | Per request | Per 1,000 | Notes |
| --- | --- | --- | --- |
| Exa `auto` (plugin default) | $0.007 | $7 | Keyword + embeddings |
| Exa `instant` / `fast` | $0.007 | $7 | Lower latency |
| Exa `deep-lite` / `deep` | $0.012 | $12 | 4–15 s |
| Exa `deep-reasoning` | $0.015 | $15 | 12–40 s |
| Parallel `turbo` / `fast` | $0.001 | $1 | ~200 ms, English + Japanese only |
| Parallel `basic` / `advanced` | $0.005 | $5 | ~1–3 s, broad language support |
| Perplexity | $0.005 | $5 | |
| Firecrawl | your Firecrawl credits | — | 2 credits / 10 results + 5 per result scrape |
| Native (Anthropic, Google, OpenAI, Perplexity, SpaceXAI) | provider passthrough | — | |

Non-native models are served by **Exa**. Native search applies to the model
families listed above; `gemini-2.5-flash-lite` measured as Exa, so the plugin
path does not get Google's native grounding.

### Measured, not assumed

Same question, four configurations:

| Configuration | Plugin fee | Model | Total |
| --- | --- | --- | --- |
| No plugin (control) | — | $0.000007 | $0.000007 |
| Exa auto, `max_results: 2` | $0.007000 | $0.000054 | $0.007054 |
| Exa auto, `max_results: 10` | $0.007000 | $0.000199 | $0.007199 |
| Parallel turbo, `max_results: 10` | $0.001000 | $0.000536 | $0.001536 |

Two things fall out of this. The plugin fee is flat across 2 and 10 results,
confirming the per-request model. And the model cost rises with result count —
Exa returns 2,000–4,000 character highlights per result, so ten results added
1,889 prompt tokens against 436 for two — but it stays in the ten-thousandths of
a dollar, i.e. the search fee is ~97% of the cost of a search turn.

Parallel turbo is **7× cheaper per search** than the Exa default, at the price
of English/Japanese only.

### Server tool (now the default path)

`openrouter:web_search` is a *server tool*: the model decides whether to search,
OpenRouter executes it, and it can run zero or more times per request. Measured
against the live API with the same model:

| Question | Cost | Search fee | Citations |
| --- | --- | --- | --- |
| "What is 2+2?" | $0.000037 | **$0.000000** | 0 |
| "Current stable Python version?" | $0.007210 | $0.007000 | 5 |

The same question through the plugin would have been billed $0.007 either way.
That is the whole argument for the server tool: enabling search costs nothing on
turns that do not need it.

Request shape:

```json
{ "tools": [{ "type": "openrouter:web_search",
              "parameters": { "engine": "exa", "max_results": 10,
                              "max_total_results": 20 } }] }
```

`engine` accepts `auto`, `native`, `exa`, `firecrawl`, `parallel` or
`perplexity`; `max_total_results` caps the total across every search in one
request, which stops a model that keeps searching from running up a bill.
Citations arrive in the same `annotations[].url_citation` shape as the plugin,
so source parsing is shared. Server tools are in **beta**.

Because the model decides, `usedWebSearch` on the reply is derived from whether
citations came back, not from whether search was requested.

## What the app does

| Need | Where it goes |
| --- | --- |
| Summary, chat, grounded follow-ups | General Compute, `gemma-4-31B-it` |
| A turn that needs live web results | OpenRouter, `web` plugin, cited sources |
| Deciding *when* to search | Client-side heuristics + globe toggle + `AIChatClient.canSearch` |
| Usage figures | Local ledger from the `usage` object; dashboard link for the balance |

## Client-side search: verified possible

The full loop was exercised against the live API, including the step that
decides feasibility — whether a tool *result* can be handed back:

**Turn 1** — question + `tools` → `finish_reason: "tool_calls"`

```json
{ "id": "call_75a2de8609ab4d5999", "type": "function",
  "function": { "name": "web_search",
                "arguments": "{\"query\":\"current stable release version of Python\"}" } }
```

**Turn 2** — the assistant message echoed back, plus a result message:

```json
{ "role": "tool", "tool_call_id": "call_75a2de8609ab4d5999",
  "name": "web_search", "content": "{\"results\":[{\"title\":\"Python Downloads\", ...}]}" }
```

→ `finish_reason: "stop"`, `content: "The current stable release version of Python is **3.14.7**."`

The model used the injected results and stopped. `tool_choice: "required"` also
works, forcing a call. So the loop closes: **General Compute can drive a search
and synthesise from the results.**

### The one thing it does not solve

Function calling decides *whether* and *what* to search; it does not perform the
search. Something still has to execute the query:

| Executor | Key | Notes |
| --- | --- | --- |
| OpenRouter `web` plugin, used only for retrieval | existing | Works today; ~$4 / 1000 results; returns titles + URLs |
| Brave / Tavily / Exa / Serper | new | Purpose-built search APIs, cleaner result payloads |
| DuckDuckGo instant answers / Wikipedia | none | Keyless but weak for general queries |

### Trade-offs against the current design

| | Single-call (now) | Client-side tool loop |
| --- | --- | --- |
| Requests per search | 1 | 2+ (the model can ask again if results were thin) |
| Model writing the answer | gemini-2.5-flash-lite | gemma-4-31B-it, same as summaries and chat |
| Thread grounding in the answer | full context is sent | full context, same model, consistent voice |
| Latency | one round trip | two round trips, though both are in parallel-safe sequence |
| Failure modes | one | needs a tool-loop bound to avoid runaway requests |

The current single-call routing is simpler and already carries the full thread
context into the search turn, which is why it is still the default.
