#!/usr/bin/env python3
"""Post the tail of an xcodebuild log to the pull request that triggered CI.

The Actions log CDN is not reachable from every reviewer environment, and a
build that fails before Swift diagnostics exist (unparseable project file, a
broken build phase, packaging) leaves only "Process completed with exit code 2"
behind. This puts the last lines of the log somewhere that is always readable:
a comment on the PR.

Usage:
    python3 tools/post_build_log.py <log-file> <repo> <pr-number>

Reads the token from GITHUB_TOKEN. Pure stdlib, and always exits 0 — reporting a
failure must never be the thing that fails a job.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

#: Annotations/comments have practical limits; 200 lines covers the tail of an
#: xcodebuild run including the error summary.
MAX_LINES = 200
MAX_BYTES = 60_000


def tail(path: str) -> str:
    try:
        with open(path, "r", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError as exc:
        return f"(could not read the build log: {exc})"

    lines = [line for line in lines if line.strip()]
    if len(lines) > MAX_LINES:
        head_note = f"... {len(lines) - MAX_LINES} earlier lines omitted ...\n"
        lines = [head_note.rstrip("\n")] + lines[-MAX_LINES:]

    text = "\n".join(lines)
    if len(text.encode()) > MAX_BYTES:
        text = text[-MAX_BYTES:].decode(errors="replace")
    return text


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: post_build_log.py <log-file> <repo> <pr-number>", file=sys.stderr)
        return 0

    log_path, repo, pr_number = sys.argv[1], sys.argv[2], sys.argv[3]
    token = os.environ.get("GITHUB_TOKEN", "")
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    if not token or not pr_number.isdigit():
        print("no GITHUB_TOKEN or PR number; skipping")
        return 0

    body = (
        "### Build log tail\n\n"
        "The Actions log CDN was unreachable, so here is the end of the log.\n\n"
        "```log\n" + tail(log_path) + "\n```"
    )

    request = urllib.request.Request(
        f"{api}/repos/{repo}/issues/{pr_number}/comments",
        data=json.dumps({"body": body}).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "vexsign-ci",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print(f"posted log tail to PR #{pr_number} ({response.status})")
    except (urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"could not post the log tail: {exc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
