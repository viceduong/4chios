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
  "plugins": [{ "id": "web", "max_results": 4 }], ... }
```

Citations come back as `choices[0].message.annotations[].url_citation` with
`{ url, title }`. Costs roughly $4 per 1000 results.

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
