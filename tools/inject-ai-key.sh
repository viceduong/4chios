#!/usr/bin/env bash
# Bakes the General Compute API key into a *local* build, the same way CI does
# when the GENERALCOMPUTE_API_KEY repository secret is set.
#
# The key is read from pi's config and written into the generated Info.plist, so
# it ends up compiled into the .app without ever being committed to the repo.
#
#   tools/inject-ai-key.sh          # inject
#   tools/inject-ai-key.sh --clear  # remove again
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/App/Info.plist"
AUTH="${HOME}/.pi/agent/auth.json"

if [ ! -f "$PLIST" ]; then
  echo "error: $PLIST not found - run 'xcodegen generate' first" >&2
  exit 1
fi

if [ "${1:-}" = "--clear" ]; then
  python3 - "$PLIST" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    info = plistlib.load(handle)
info["GeneralComputeAPIKey"] = ""
with open(path, "wb") as handle:
    plistlib.dump(info, handle)
print("cleared GeneralComputeAPIKey")
PY
  exit 0
fi

if [ ! -f "$AUTH" ]; then
  echo "error: $AUTH not found; pass a key via Settings in the app instead" >&2
  exit 1
fi

python3 - "$PLIST" "$AUTH" <<'PY'
import json, plistlib, sys

plist_path, auth_path = sys.argv[1], sys.argv[2]
key = json.load(open(auth_path, encoding="utf-8"))["generalcompute"]["key"]

with open(plist_path, "rb") as handle:
    info = plistlib.load(handle)
info["GeneralComputeAPIKey"] = key
with open(plist_path, "wb") as handle:
    plistlib.dump(info, handle)

print(f"injected key {key[:6]}...({len(key)} chars) into {plist_path}")
PY
