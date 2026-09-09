#!/usr/bin/env python3
"""Fetch GitHub Actions job logs for viceduong/4chios.

GitHub redirects job-log requests to Azure blob storage; the Authorization
header must be dropped on the cross-host hop or the download 401s.

Usage:
    python .local/ci-logs.py                # errors from the latest run's failed jobs
    python .local/ci-logs.py <job_id> ...   # specific jobs
    python .local/ci-logs.py --full <job_id>
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

REPO = "viceduong/4chios"
TOKEN = json.load(open(os.path.expanduser("~/.aich/config.json")))["token"]
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {TOKEN}",
    "User-Agent": "4chios-ci-logs/0.1",
}


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    """Strip Authorization when a redirect leaves api.github.com."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None:
            src = urllib.parse.urlsplit(req.full_url).hostname
            dst = urllib.parse.urlsplit(newurl).hostname
            if src != dst:
                new.remove_header("Authorization")
        return new


OPENER = urllib.request.build_opener(SafeRedirect)


def api(path):
    req = urllib.request.Request("https://api.github.com" + path, headers=HEADERS)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as exc:
        return {"_error": exc.code}


def job_logs(job_id):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/actions/jobs/{job_id}/logs", headers=HEADERS
    )
    try:
        with OPENER.open(req) as resp:
            return resp.read().decode("utf-8", "replace").replace("\ufeff", "")
    except urllib.error.HTTPError as exc:
        return f"HTTP {exc.code}: {exc.read().decode()[:200]}"


def failed_jobs():
    runs = api(f"/repos/{REPO}/actions/runs?branch=main&per_page=1").get("workflow_runs") or []
    if not runs:
        return []
    run = runs[0]
    print(f"run #{run['run_number']} {run['head_sha'][:8]} -> {run['html_url']}")
    jobs = api(f"/repos/{REPO}/actions/runs/{run['id']}/jobs").get("jobs", [])
    out = []
    for job in jobs:
        mark = "ok" if job["conclusion"] == "success" else (job["conclusion"] or "?")
        print(f"  JOB {job['name']}: {mark}")
        if job["conclusion"] not in ("success", "skipped", None):
            out.append((job["id"], job["name"]))
    return out


def show(job_id, name, full=False):
    print(f"\n########## {name} ({job_id}) ##########")
    lines = job_logs(job_id).splitlines()
    if full:
        print("\n".join(lines[-250:]))
        return
    pattern = re.compile(r"error:|FAILED|XCTAssert|fatal error|undefined", re.I)
    hits = [i for i, line in enumerate(lines) if pattern.search(line)]
    seen = set()
    for i in hits[:20]:
        for k in range(max(0, i - 6), min(len(lines), i + 3)):
            if k not in seen:
                seen.add(k)
                print(lines[k])
        print("   ...")


def main():
    args = [a for a in sys.argv[1:]]
    full = "--full" in args
    args = [a for a in args if a != "--full"]
    jobs = [(int(a), f"job {a}") for a in args] if args else failed_jobs()
    for job_id, name in jobs:
        show(job_id, name, full=full)


if __name__ == "__main__":
    main()
