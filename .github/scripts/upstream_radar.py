#!/usr/bin/env python3
"""Upstream feature radar: what did the other signers ship, and what is worth porting?

Scans the projects listed in upstream_sources.json (Feather, FeatherPlus, Ksign,
KorSign, RyukSign, MySignReincarnated, SideStore, LiveContainer, ...) through
the GitHub API, collects recent releases and commits, drops noise (merges,
chores, translations, things VexSign already has), maps every touched file
onto VexSign's layout to estimate how cleanly a commit would apply, and turns
the result into a **checklist**: a GitHub issue where each candidate is a task
box. Tick what you want, comment `/prepare`, and the merge-kit workflow builds
a branch + draft PR from exactly those commits. Nothing is merged on its own.

    python3 upstream_radar.py --repo owner/name --since-days 30 --out radar/ [--create-issue]
    python3 upstream_radar.py --dry-run --sources feather,ryuksign        # local preview

Environment: GITHUB_TOKEN (or GH_TOKEN), GITHUB_REPOSITORY, GITHUB_STEP_SUMMARY,
GITHUB_OUTPUT. Pure stdlib.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEFAULT_CONFIG = HERE / "upstream_sources.json"
MARKER_HEAD = "<!-- vexsign-radar v1"
ITEM_MARKER_RE = re.compile(r"<!-- radar:(?P<key>[a-z0-9-]+):(?P<sha>[0-9a-f]{40}) -->")
CONVENTIONAL_RE = re.compile(r"^(?P<type>[a-zA-Z]+)(?:\((?P<scope>[^)]*)\))?!?:\s*(?P<rest>.*)$")
PR_SUFFIX_RE = re.compile(r"\s*\(#\d+\)\s*$")

UA = "vexsign-upstream-radar"


# --------------------------------------------------------------------------
# GitHub API (stdlib only)
# --------------------------------------------------------------------------

class RateLimited(Exception):
    pass


class GitHub:
    def __init__(self, token: str | None, api: str = "https://api.github.com") -> None:
        self.token = token
        self.api = api.rstrip("/")
        self.remaining: int | None = None
        self.calls = 0

    def _request(self, method: str, path: str, params: dict | None = None, body: dict | None = None):
        url = path if path.startswith("http") else f"{self.api}/{path.lstrip('/')}"
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Accept": "application/vnd.github+json", "User-Agent": UA, "X-GitHub-Api-Version": "2022-11-28"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    self.calls += 1
                    remaining = response.headers.get("X-RateLimit-Remaining")
                    if remaining is not None and remaining.isdigit():
                        self.remaining = int(remaining)
                    raw = response.read()
                    return response.status, response.headers, (json.loads(raw) if raw else None)
            except urllib.error.HTTPError as exc:
                self.calls += 1
                remaining = exc.headers.get("X-RateLimit-Remaining") if exc.headers else None
                if exc.code in (403, 429) and remaining == "0":
                    reset = int(exc.headers.get("X-RateLimit-Reset", "0") or 0)
                    wait = max(0, reset - int(time.time()))
                    if wait <= 120:
                        print(f"::notice::GitHub API rate limit hit, sleeping {wait}s")
                        time.sleep(wait + 1)
                        continue
                    raise RateLimited(f"rate limit exhausted, resets in {wait}s") from exc
                if exc.code in (404, 410):
                    return exc.code, exc.headers, None
                if exc.code >= 500 and attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                detail = ""
                try:
                    detail = exc.read().decode(errors="replace")[:300]
                except Exception:  # noqa: BLE001
                    pass
                raise RuntimeError(f"{method} {url} -> HTTP {exc.code}: {detail}") from exc
            except (urllib.error.URLError, TimeoutError) as exc:
                if attempt < 3:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError(f"{method} {url} failed: {exc}") from exc
        raise RuntimeError(f"{method} {url}: giving up")

    def get(self, path: str, params: dict | None = None, default=None):
        status, _, payload = self._request("GET", path, params=params)
        return default if status in (404, 410) else payload

    def paginate(self, path: str, params: dict | None = None, max_pages: int = 3) -> list:
        items: list = []
        params = dict(params or {})
        params.setdefault("per_page", 100)
        for page in range(1, max_pages + 1):
            params["page"] = page
            status, _, payload = self._request("GET", path, params=params)
            if status in (404, 410) or not payload:
                break
            items.extend(payload)
            if len(payload) < params["per_page"]:
                break
        return items

    def post(self, path: str, body: dict):
        _, _, payload = self._request("POST", path, body=body)
        return payload

    def patch(self, path: str, body: dict):
        _, _, payload = self._request("PATCH", path, body=body)
        return payload


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def glob_to_regex(pattern: str) -> re.Pattern:
    out = ""
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
            continue
        if pattern.startswith("**", i):
            out += ".*"
            i += 2
            continue
        if ch == "*":
            out += "[^/]*"
        elif ch == "?":
            out += "[^/]"
        else:
            out += re.escape(ch)
        i += 1
    return re.compile(f"^{out}$")


class GlobList:
    def __init__(self, patterns: list[str]) -> None:
        self.patterns = [(p, glob_to_regex(p)) for p in patterns]

    def match(self, path: str) -> str | None:
        base = path.rsplit("/", 1)[-1]
        for pattern, regex in self.patterns:
            if regex.match(path) or ("/" not in pattern and regex.match(base)):
                return pattern
        return None


def map_path(path: str, path_map: dict[str, str]) -> str | None:
    """Longest-prefix rewrite of an upstream path onto VexSign's layout."""
    for prefix in sorted(path_map, key=len, reverse=True):
        if path == prefix or (prefix.endswith("/") and path.startswith(prefix)):
            return path_map[prefix] + path[len(prefix):]
    return None


def normalize_subject(subject: str) -> str:
    text = subject.strip()
    match = CONVENTIONAL_RE.match(text)
    if match and len(match["type"]) <= 12:
        text = match["rest"]
    text = PR_SUFFIX_RE.sub("", text)
    text = re.sub(r"\s+", " ", text).strip().lower().rstrip(".")
    return text


def md_escape(text: str) -> str:
    """Neutralise Markdown/HTML in commit subjects (also stops '#123' from linking to VexSign issues)."""
    text = text.replace("\r", " ").replace("\n", " ")
    html = {"<": "&lt;", ">": "&gt;", "|": "&#124;"}

    def repl(match: re.Match) -> str:
        ch = match.group(0)
        return html.get(ch, "\\" + ch)

    return re.sub(r"[\\`*_{}\[\]<>|~#]", repl, text).strip()


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def git(*args: str, cwd: Path = ROOT) -> str:
    try:
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


# --------------------------------------------------------------------------
# what VexSign already has
# --------------------------------------------------------------------------

def local_known() -> tuple[set[str], set[str]]:
    """Subjects and upstream references already present in VexSign's history."""
    subjects: set[str] = set()
    refs: set[str] = set()
    log = git("log", "--no-merges", "-n", "6000", "--format=%s%x00%b%x1e")
    for record in log.split("\x1e"):
        if not record.strip():
            continue
        subject, _, body = record.partition("\x00")
        subjects.add(normalize_subject(subject))
        for match in re.finditer(r"Upstream-Source:\s*([\w.-]+/[\w.-]+)@([0-9a-f]{7,40})", body):
            refs.add(match.group(2)[:7])
        for match in re.finditer(r"cherry picked from commit ([0-9a-f]{7,40})", body):
            refs.add(match.group(1)[:7])
    return subjects, refs


def previously_shown(gh: GitHub, repo: str, label: str) -> tuple[set[tuple[str, str]], list[dict]]:
    seen: set[tuple[str, str]] = set()
    issues: list[dict] = []
    try:
        items = gh.paginate(f"repos/{repo}/issues", {"labels": label, "state": "all", "sort": "created", "direction": "desc"}, max_pages=1)
    except RuntimeError as exc:
        print(f"::warning::could not list previous radar issues: {exc}")
        return seen, issues
    for item in items or []:
        if "pull_request" in item or MARKER_HEAD not in (item.get("body") or ""):
            continue
        issues.append(item)
        for match in ITEM_MARKER_RE.finditer(item.get("body") or ""):
            seen.add((match["key"], match["sha"]))
    return seen, issues


# --------------------------------------------------------------------------
# classification
# --------------------------------------------------------------------------

def classify(subject: str, config: dict) -> tuple[str, str]:
    """-> (category, reason). category: feat | fix | other | skip"""
    text = subject.strip()
    for pattern in config.get("ignore_commit_patterns", []):
        if re.search(pattern, text):
            return "skip", f"matches `{pattern}`"
    match = CONVENTIONAL_RE.match(text)
    if match and len(match["type"]) <= 12:
        kind = match["type"].lower()
        if kind in {"feat", "feature"}:
            return "feat", "conventional feat"
        if kind in {"fix", "hotfix", "bugfix"}:
            return "fix", "conventional fix"
        if kind in {"perf", "refactor", "revert"}:
            return "other", f"conventional {kind}"
    lowered = " " + re.sub(r"[^a-z0-9 ]+", " ", text.lower()) + " "
    for word in config.get("feature_keywords", []):
        if f" {word} " in lowered:
            return "feat", f"keyword '{word}'"
    for word in config.get("fix_keywords", []):
        if f" {word} " in lowered:
            return "fix", f"keyword '{word}'"
    return "other", "unclassified"


def feasibility(files: list[dict], source: dict) -> dict:
    if source.get("family") == "reference" or not source.get("path_map"):
        return {"emoji": "📖", "label": "reference only (different codebase)", "code": "reference"}
    existing = sum(1 for f in files if f["role"] == "code" and f["exists"])
    new = sum(1 for f in files if f["role"] == "code" and not f["exists"])
    unmapped = sum(1 for f in files if f["role"] == "unmapped")
    manual = sum(1 for f in files if f["role"] == "manual")
    skipped = sum(1 for f in files if f["role"] == "skipped")
    if existing == 0 and new == 0 and unmapped == 0:
        code = "noncode"
        emoji, label = "🧹", "non-code change" + (" (strings/assets → manual)" if manual else "")
    elif unmapped:
        code = "partial"
        emoji, label = "🟡", f"partial ({unmapped} file(s) outside the mapped layout)"
    elif existing == 0:
        code = "new"
        emoji, label = "🆕", f"new files only ({new})"
    else:
        code = "direct"
        emoji, label = "✅", f"likely applies ({existing} existing, {new} new)"
    extras = []
    if manual:
        extras.append("🌐 strings/assets need Xcode")
    if skipped:
        extras.append("🧩 project/docs hunks dropped")
    return {"emoji": emoji, "label": label + (" · " + " · ".join(extras) if extras else ""), "code": code,
            "existing": existing, "new": new, "unmapped": unmapped, "manual": manual, "skipped": skipped}


# --------------------------------------------------------------------------
# scanning
# --------------------------------------------------------------------------

def scan_source(gh: GitHub, source: dict, config: dict, since: dt.datetime, seen: set, known_subjects: set,
                known_refs: set, attributed: dict, include_seen: bool, limits: dict) -> dict:
    repo = source["repo"]
    result = {"key": source["key"], "name": source["name"], "repo": repo, "license": source.get("license", "?"),
              "family": source.get("family", "feather"), "notes": source.get("notes", ""), "url": f"https://github.com/{repo}",
              "status": "ok", "releases": [], "candidates": [], "skipped": [], "counts": {}}
    meta = gh.get(f"repos/{repo}")
    if not meta:
        result["status"] = "unresolved"
        result["error"] = f"https://github.com/{repo} was not found (moved or renamed?). Fix `repo` in upstream_sources.json."
        return result
    branch = source.get("branch") or meta.get("default_branch") or "main"
    result.update({"branch": branch, "url": meta.get("html_url", result["url"]), "stars": meta.get("stargazers_count"),
                   "pushed_at": meta.get("pushed_at"), "description": meta.get("description") or ""})
    if meta.get("license", {}) and meta["license"].get("spdx_id") not in (None, "NOASSERTION"):
        result["license"] = meta["license"]["spdx_id"]
    if meta.get("archived"):
        result["status"] = "archived"

    # Releases in the window (or the latest one, marked as such).
    # Newest first. Everything inside the window is listed (max 4); when
    # nothing was released in the window the latest release is shown, marked.
    releases = gh.get(f"repos/{repo}/releases", {"per_page": 10}, default=[]) or []
    for rel in releases:
        published = parse_iso(rel.get("published_at"))
        if rel.get("draft") or not published:
            continue
        item = {"tag": rel.get("tag_name"), "name": rel.get("name") or rel.get("tag_name"), "date": published.date().isoformat(),
                "url": rel.get("html_url"), "prerelease": bool(rel.get("prerelease")),
                "body": re.sub(r"<!--.*?-->|!\[[^\]]*\]\([^)]*\)", "", rel.get("body") or "", flags=re.S).strip()[:700]}
        if published >= since:
            result["releases"].append(item)
            if len(result["releases"]) >= 4:
                break
            continue
        if not result["releases"]:
            item["latest_only"] = True
            result["releases"].append(item)
        break

    commits = gh.paginate(f"repos/{repo}/commits", {"sha": branch, "since": iso(since)},
                          max_pages=max(1, limits["max_commits_per_source"] // 100))
    commits = commits[: limits["max_commits_per_source"]]
    result["counts"]["commits_in_window"] = len(commits)

    skip_globs = GlobList(config.get("skip_paths", []))
    manual_globs = GlobList(config.get("manual_paths", []))
    detail_budget = limits["max_detail_lookups_per_source"]
    seen_here = 0

    for commit in commits:
        sha = commit["sha"]
        message = (commit.get("commit", {}).get("message") or "").strip()
        subject, _, body = message.partition("\n")
        subject = subject.strip()
        author = commit.get("author") or {}
        commit_author = commit.get("commit", {}).get("author") or {}
        author_info = {"login": author.get("login"), "id": author.get("id"), "name": commit_author.get("name"),
                       "email": commit_author.get("email")}
        date = parse_iso(commit_author.get("date"))
        entry = {"sha": sha, "short": sha[:7], "url": commit.get("html_url"), "subject": subject, "body": body.strip(),
                 "author": author_info, "date": date.date().isoformat() if date else "", "source": source["key"]}

        if len(commit.get("parents") or []) > 1:
            result["skipped"].append({**entry, "reason": "merge commit"})
            continue
        if (author.get("login") or "").endswith("[bot]") or (author.get("type") == "Bot"):
            result["skipped"].append({**entry, "reason": "bot"})
            continue
        category, why = classify(subject, config)
        if category == "skip":
            result["skipped"].append({**entry, "reason": f"chore/noise ({why})"})
            continue
        norm = normalize_subject(subject)
        if sha[:7] in known_refs or norm in known_subjects:
            result["skipped"].append({**entry, "reason": "already in VexSign"})
            continue
        prior = attributed.get(sha) or attributed.get("subject:" + norm)
        if prior and prior != source["key"]:
            result["skipped"].append({**entry, "reason": f"same change listed under {prior}"})
            continue
        if not include_seen and (source["key"], sha) in seen:
            seen_here += 1
            continue

        attributed[sha] = source["key"]
        attributed["subject:" + norm] = source["key"]
        entry["category"] = category
        entry["why"] = why

        files: list[dict] = []
        flags: list[str] = []
        if detail_budget > 0 and (gh.remaining is None or gh.remaining > 40):
            detail_budget -= 1
            detail = gh.get(f"repos/{repo}/commits/{sha}") or {}
            entry["stats"] = detail.get("stats") or {}
            for item in detail.get("files") or []:
                path = item.get("filename") or ""
                patch = item.get("patch") or ""
                mapped = map_path(path, source.get("path_map") or {})
                if skip_globs.match(path) or (mapped and skip_globs.match(mapped)):
                    role = "skipped"
                elif manual_globs.match(path) or (mapped and manual_globs.match(mapped)):
                    role = "manual"
                elif mapped is None:
                    role = "unmapped" if source.get("path_map") else "reference"
                else:
                    role = "code"
                exists = bool(mapped) and (ROOT / mapped).exists()
                files.append({"path": path, "mapped": mapped, "role": role, "exists": exists, "status": item.get("status"),
                              "additions": item.get("additions", 0), "deletions": item.get("deletions", 0)})
                if "XCRemoteSwiftPackageReference" in patch and "+" in patch:
                    flags.append("adds a Swift package")
                if path.endswith(".pbxproj") and re.search(r"^\+.*(IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION|OTHER_LDFLAGS)", patch, re.M):
                    flags.append("changes build settings")
                if path.endswith(".entitlements") and "+" in patch:
                    flags.append("touches entitlements")
                brand = source.get("brand")
                if brand and patch and role in ("code", "unmapped") and source.get("family") != "reference":
                    added = [line for line in patch.splitlines() if line.startswith("+") and not line.startswith("+++")]
                    if any(brand.lower() in line.lower() for line in added):
                        flags.append(f"mentions '{brand}' (rename to VexSign)")
        entry["files"] = files
        entry["flags"] = sorted(set(flags))
        entry["feasibility"] = feasibility(files, source) if files else (
            {"emoji": "📖", "label": "reference only (different codebase)", "code": "reference"}
            if source.get("family") == "reference" else {"emoji": "❔", "label": "details not fetched", "code": "unknown"})
        result["candidates"].append(entry)

    result["counts"]["candidates"] = len(result["candidates"])
    result["counts"]["skipped"] = len(result["skipped"])
    result["counts"]["seen_before"] = seen_here
    # Features first, then fixes, then the rest; newest first inside a group.
    order = {"feat": 0, "fix": 1, "other": 2}
    result["candidates"].sort(key=lambda c: c["date"], reverse=True)
    result["candidates"].sort(key=lambda c: order.get(c["category"], 3))
    return result


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def render_candidate(c: dict, checked: bool = False) -> str:
    box = "[x]" if checked else "[ ]"
    feas = c.get("feasibility") or {}
    author = f"@{c['author']['login']}" if c["author"].get("login") else (c["author"].get("name") or "unknown")
    files = c.get("files") or []
    detail = f"{len(files)} file{'s' if len(files) != 1 else ''}" if files else "files n/a"
    flags = f" · ⚠️ {', '.join(c['flags'])}" if c.get("flags") else ""
    return (f"- {box} {feas.get('emoji', '❔')} **{c['category']}** {md_escape(c['subject'])} — "
            f"[`{c['short']}`]({c['url']}) · {md_escape(author)} · {c['date']} · {detail} · {feas.get('label', '')}{flags} "
            f"<!-- radar:{c['source']}:{c['sha']} -->")


def render_source(result: dict, max_candidates: int) -> list[str]:
    out: list[str] = []
    title = f"## {result['name']} · [{result['repo']}]({result['url']}) · {result['license']}"
    if result.get("status") == "archived":
        title += " · _archived_"
    out.append(title)
    if result.get("status") == "unresolved":
        out.append(f"> ⚠️ {result['error']}")
        out.append("")
        return out
    if result.get("notes"):
        out.append(f"_{md_escape(result['notes'])}_")
    if result["family"] == "reference":
        out.append("> 📖 Different codebase under **AGPL-3.0**: use these as ideas to re-implement. Copying code into VexSign (GPL-3.0) would require keeping the AGPL terms for that code.")
    out.append("")
    if result["releases"]:
        parts = []
        for rel in result["releases"]:
            tag = f"[`{rel['tag']}`]({rel['url']}) ({rel['date']}{', pre-release' if rel['prerelease'] else ''}{', latest, before window' if rel.get('latest_only') else ''})"
            parts.append(tag)
        out.append("**Releases:** " + " · ".join(parts))
        for rel in result["releases"][:2]:
            if rel["body"]:
                out.append("<details><summary>Release notes " + md_escape(rel["name"] or rel["tag"]) + "</summary>")
                out.append("")
                out.append("\n".join("> " + line for line in rel["body"].splitlines()[:25]))
                out.append("")
                out.append("</details>")
        out.append("")
    cands = result["candidates"]
    if not cands:
        out.append(f"No new candidates ({result['counts'].get('commits_in_window', 0)} commits in window, "
                   f"{result['counts'].get('skipped', 0)} skipped, {result['counts'].get('seen_before', 0)} shown previously).")
        out.append("")
    else:
        out.append(f"**Candidates ({len(cands)})** — tick what you want:")
        out.append("")
        for c in cands[:max_candidates]:
            out.append(render_candidate(c))
        if len(cands) > max_candidates:
            out.append(f"- … {len(cands) - max_candidates} more in the workflow artifact (`report.md`), or re-run with a higher `max_per_source`.")
        out.append("")
    if result["skipped"]:
        out.append(f"<details><summary>Not listed ({len(result['skipped'])}): merges, chores, translations, already in VexSign</summary>")
        out.append("")
        for s in result["skipped"][:40]:
            out.append(f"- [`{s['short']}`]({s['url']}) {md_escape(s['subject'])[:90]} — {s['reason']}")
        if len(result["skipped"]) > 40:
            out.append(f"- … {len(result['skipped']) - 40} more")
        out.append("")
        out.append("</details>")
        out.append("")
    return out


def render_report(results: list[dict], meta: dict, max_candidates: int, for_issue: bool) -> str:
    total = sum(len(r["candidates"]) for r in results)
    already = sum(1 for r in results for s in r["skipped"] if s["reason"] == "already in VexSign")
    skipped = sum(len(r["skipped"]) for r in results) - already
    out: list[str] = []
    if for_issue:
        out.append(f"{MARKER_HEAD} {json.dumps({'generated': meta['generated'], 'since_days': meta['since_days'], 'sources': [r['key'] for r in results]})} -->")
    out.append(f"### Upstream feature radar — {meta['generated'][:10]}")
    out.append("")
    out.append(f"Scanned **{len(results)} sources** for the last **{meta['since_days']} days** · "
               f"**{total} new candidates** · {already} already in VexSign · {skipped} skipped as merges/chores/translations.")
    out.append("")
    out.append("**How to choose**")
    out.append("")
    out.append("1. Tick the boxes of the items you want ported into VexSign.")
    out.append(f"2. Comment `/prepare` on this issue, or add the `{meta['prepare_label']}` label.")
    out.append("3. The **Upstream merge kit** workflow creates branch `upstream-kit/issue-<n>`, applies the ticked commits with "
               "paths rewritten to VexSign's layout, opens a **draft PR** with a per-commit result table and attaches patch files "
               "for anything that did not apply cleanly. Nothing is merged automatically - review, fix, build, then merge or close.")
    out.append("")
    out.append("Legend: ✅ likely applies · 🆕 new files only · 🟡 partial (files outside the mapped layout) · 🧹 non-code · "
               "🌐 string catalog / assets need Xcode · 🧩 project-file hunks dropped · 📖 reference only · ⚠️ needs attention")
    out.append("")
    out.append("---")
    out.append("")
    for result in results:
        out.extend(render_source(result, max_candidates))
    out.append("---")
    out.append("")
    out.append(f"<sub>Generated by the <b>Upstream feature radar</b> workflow for VexSign, maintained by @{meta['owner']}. "
               "Upstream projects are scanned read-only; every item links to its original commit and author. "
               "Ported code keeps its provenance (repository, commit, author, license) in commit trailers, as GPL-3.0/AGPL-3.0 require. "
               f"API calls: {meta.get('api_calls', '?')}.</sub>")
    return "\n".join(out)


def fit_issue_body(results: list[dict], meta: dict, max_candidates: int, limit: int) -> str:
    body = render_report(results, meta, max_candidates, for_issue=True)
    while len(body) > limit and max_candidates > 3:
        max_candidates = max(3, max_candidates // 2)
        body = render_report(results, meta, max_candidates, for_issue=True)
    if len(body) > limit:
        trimmed = [dict(r, skipped=[]) for r in results]
        body = render_report(trimmed, meta, max_candidates, for_issue=True)
    if len(body) > limit:
        body = body[: limit - 200] + "\n\n… truncated - the full report is attached to the workflow run as an artifact."
    return body


# --------------------------------------------------------------------------
# issue plumbing
# --------------------------------------------------------------------------

def ensure_label(gh: GitHub, repo: str, name: str, color: str, description: str) -> None:
    if gh.get(f"repos/{repo}/labels/{urllib.parse.quote(name)}"):
        return
    try:
        gh.post(f"repos/{repo}/labels", {"name": name, "color": color, "description": description})
    except RuntimeError as exc:
        if "422" not in str(exc):
            print(f"::warning::could not create label {name}: {exc}")


def publish_issue(gh: GitHub, repo: str, title: str, body: str, label: str, previous: list[dict]) -> dict:
    issue = gh.post(f"repos/{repo}/issues", {"title": title, "body": body, "labels": [label]})
    number = issue["number"]
    for old in previous:
        if old.get("state") != "open" or old["number"] == number:
            continue
        try:
            gh.post(f"repos/{repo}/issues/{old['number']}/comments",
                    {"body": f"Superseded by #{number}. Unticked items are not repeated there; re-run the radar with "
                             f"`include_seen = true` to list everything again, or `/prepare` here - the merge kit works on closed issues too."})
            gh.patch(f"repos/{repo}/issues/{old['number']}", {"state": "closed", "state_reason": "not_planned"})
        except RuntimeError as exc:
            print(f"::warning::could not close previous radar issue #{old['number']}: {exc}")
    return issue


def set_output(name: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "iamsmmh/VexSign"), help="owner/name of this repository")
    parser.add_argument("--sources", default="all", help="'all' or comma-separated source keys")
    parser.add_argument("--since-days", type=int, default=None)
    parser.add_argument("--max-per-source", type=int, default=None, help="candidates listed per source in the issue")
    parser.add_argument("--include-seen", action="store_true", help="list items that were already shown in earlier radar issues")
    parser.add_argument("--out", default="radar", help="output directory for report.md / candidates.json")
    parser.add_argument("--create-issue", action="store_true", help="open a GitHub issue with the checklist")
    parser.add_argument("--always-issue", action="store_true", help="open an issue even when nothing new was found")
    parser.add_argument("--dry-run", action="store_true", help="never write to GitHub")
    args = parser.parse_args()

    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    radar_cfg = config.get("radar", {})
    since_days = args.since_days or radar_cfg.get("since_days", 30)
    max_per_source = args.max_per_source or radar_cfg.get("max_candidates_per_source", 25)
    limits = {"max_commits_per_source": radar_cfg.get("max_commits_per_source", 120),
              "max_detail_lookups_per_source": radar_cfg.get("max_detail_lookups_per_source", 40)}
    labels = config.get("labels", {})
    radar_label = labels.get("radar", "upstream-radar")
    prepare_label = labels.get("prepare", "prepare-merge")

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        print("::warning::no GITHUB_TOKEN - unauthenticated requests are limited to 60/hour")
    gh = GitHub(token, os.environ.get("GITHUB_API_URL", "https://api.github.com"))

    wanted = [s.strip().lower() for s in args.sources.split(",") if s.strip()]
    sources = config["sources"] if "all" in wanted else [s for s in config["sources"] if s["key"] in wanted]
    unknown = [w for w in wanted if w != "all" and w not in {s["key"] for s in config["sources"]}]
    for key in unknown:
        print(f"::warning::unknown source key '{key}' (known: {', '.join(s['key'] for s in config['sources'])})")
    if not sources:
        print("::error::no sources selected")
        return 1

    now = dt.datetime.now(dt.timezone.utc)
    since = now - dt.timedelta(days=since_days)
    known_subjects, known_refs = local_known()
    seen, previous = (set(), []) if args.include_seen else previously_shown(gh, args.repo, radar_label)
    if args.include_seen:
        _, previous = previously_shown(gh, args.repo, radar_label)
    print(f"VexSign history: {len(known_subjects)} subjects, {len(known_refs)} upstream refs; "
          f"{len(seen)} items shown in {len(previous)} earlier radar issue(s)")

    attributed: dict[str, str] = {}
    results: list[dict] = []
    for source in sources:
        print(f"→ {source['name']} ({source['repo']}) …", flush=True)
        try:
            result = scan_source(gh, source, config, since, seen, known_subjects, known_refs, attributed,
                                 args.include_seen, limits)
        except RateLimited as exc:
            print(f"::warning::{exc}; stopping the scan early")
            results.append({"key": source["key"], "name": source["name"], "repo": source["repo"], "license": source.get("license", "?"),
                            "family": source.get("family"), "notes": "", "url": f"https://github.com/{source['repo']}",
                            "status": "unresolved", "error": str(exc), "releases": [], "candidates": [], "skipped": [], "counts": {}})
            break
        except RuntimeError as exc:
            print(f"::warning::{source['name']}: {exc}")
            results.append({"key": source["key"], "name": source["name"], "repo": source["repo"], "license": source.get("license", "?"),
                            "family": source.get("family"), "notes": "", "url": f"https://github.com/{source['repo']}",
                            "status": "unresolved", "error": str(exc), "releases": [], "candidates": [], "skipped": [], "counts": {}})
            continue
        results.append(result)
        print(f"   {result['counts'].get('commits_in_window', 0)} commits · {len(result['candidates'])} candidates · "
              f"{len(result['skipped'])} skipped · {len(result['releases'])} release(s)")

    meta = {"generated": now.strftime("%Y-%m-%d %H:%M UTC"), "since_days": since_days, "owner": args.repo.split("/")[0],
            "prepare_label": prepare_label, "api_calls": gh.calls}
    total = sum(len(r["candidates"]) for r in results)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    report = render_report(results, meta, max_candidates=10_000, for_issue=False)
    (out_dir / "report.md").write_text(report, encoding="utf-8")
    (out_dir / "candidates.json").write_text(json.dumps({"meta": meta, "sources": results}, indent=2), encoding="utf-8")
    print(f"\nWrote {out_dir / 'report.md'} and {out_dir / 'candidates.json'} ({total} candidates)")

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(report[:900_000] + "\n")
    set_output("candidates", str(total))
    set_output("report", str(out_dir / "report.md"))

    if not args.create_issue or args.dry_run:
        if args.dry_run and args.create_issue:
            print("dry run: not creating an issue")
        return 0
    if total == 0 and not args.always_issue:
        print("Nothing new upstream - no issue created.")
        set_output("issue_url", "")
        return 0

    ensure_label(gh, args.repo, radar_label, "5319e7", "Upstream feature radar checklist")
    ensure_label(gh, args.repo, prepare_label, "0e8a16", "Ask the merge-kit workflow to prepare the ticked upstream items")
    body = fit_issue_body(results, meta, max_per_source, radar_cfg.get("issue_body_limit", 60000))
    title = f"Upstream feature radar — {now.date().isoformat()} ({total} new candidate{'s' if total != 1 else ''})"
    issue = publish_issue(gh, args.repo, title, body, radar_label, previous)
    print(f"Opened {issue['html_url']}")
    set_output("issue_url", issue["html_url"])
    set_output("issue_number", str(issue["number"]))
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(f"\n**Checklist issue:** {issue['html_url']}\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
