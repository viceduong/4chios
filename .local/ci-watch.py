#!/usr/bin/env python3
"""Watch the latest CI run for viceduong/4chios and print job/step results.

Local tooling only (gitignored). Reads the GitHub token from ~/.aich/config.json.
Usage: python -u .local/ci-watch.py
"""
import json
import os
import time
import urllib.error
import urllib.request

REPO = "viceduong/4chios"
TOKEN = json.load(open(os.path.expanduser("~/.aich/config.json")))["token"]
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "4chios-ci-watch/0.1",
}


def api(path, raw=False):
    req = urllib.request.Request("https://api.github.com" + path, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
            return data if raw else json.loads(data or b"{}")
    except urllib.error.HTTPError as exc:
        return exc.read() if raw else {"_error": exc.code}


def latest_run():
    data = api(f"/repos/{REPO}/actions/runs?branch=main&per_page=1")
    runs = data.get("workflow_runs") or []
    return runs[0] if runs else None


run = None
for _ in range(160):
    current = latest_run()
    if current:
        if run is None or current["id"] != run["id"]:
            run = current
            print(f"RUN #{current['run_number']} {current['head_sha'][:8]} -> {current['html_url']}", flush=True)
        print(f"  [{time.strftime('%H:%M:%S')}] {current['status']} {current['conclusion'] or ''}", flush=True)
        if current["status"] == "completed":
            break
    time.sleep(15)

if run and run["status"] == "completed":
    jobs = api(f"/repos/{REPO}/actions/runs/{run['id']}/jobs")
    failed = []
    for job in jobs.get("jobs", []):
        print(f"JOB {job['name']}: {job['conclusion']}", flush=True)
        for step in job["steps"]:
            mark = "ok" if step["conclusion"] == "success" else (step["conclusion"] or "?")
            print(f"   - {step['name']}: {mark}", flush=True)
        if job["conclusion"] not in ("success", "skipped", None):
            failed.append(job)

    for job in failed:
        print(f"\n=== LOG TAIL: {job['name']} ===", flush=True)
        raw = api(f"/repos/{REPO}/actions/jobs/{job['id']}/logs", raw=True)
        if isinstance(raw, bytes):
            lines = raw.decode("utf-8", "replace").splitlines()
            print("\n".join(lines[-180:]), flush=True)
        else:
            print("log unavailable", flush=True)

print("DONE", flush=True)
