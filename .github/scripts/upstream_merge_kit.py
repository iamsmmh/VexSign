#!/usr/bin/env python3
"""Upstream merge kit: turn the ticked boxes of a radar issue into a branch, a draft PR and patches.

Given a radar issue (created by upstream_radar.py) whose task boxes were ticked,
this script

  1. reads the selection (`- [x] ... <!-- radar:<source>:<sha> -->`),
  2. fetches each selected upstream commit (depth 2, so 3-way merges have a base),
  3. rewrites the patch onto VexSign's layout (Feather/ → VexSign/, RyukSignWidget…
     → VexSignWidget…, …), drops project-file/docs hunks and sets string-catalog
     and asset hunks aside for Xcode,
  4. applies it with `git apply --3way` on a fresh branch off main and commits it -
     credited to the VexSign developer, with the upstream repository, commit,
     author and license recorded in trailers (GPL-3.0 / AGPL-3.0 attribution),
  5. force-pushes `upstream-kit/issue-<n>`, opens or refreshes a **draft** PR with a
     per-commit result table, comments on the issue and leaves the patch files,
     manual-only hunks and conflict snapshots as a workflow artifact.

Commits that conflict are *not* committed (the branch stays buildable); their
rewritten patch and the conflicted files are in the kit for a manual `git am -3`.
Nothing is merged. You review, fix, build, and merge or close.

    python3 upstream_merge_kit.py --issue 123 --out /tmp/kit
    python3 upstream_merge_kit.py --selection-file picks.md --dry-run --out /tmp/kit   # local

Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, GIT_AUTHOR_NAME/EMAIL (from
git_identity.sh), CREDIT_MODE (vexsign | shared | upstream). Pure stdlib.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from upstream_radar import GitHub, GlobList, map_path, md_escape  # noqa: E402

HERE = Path(__file__).resolve().parent
DEFAULT_CONFIG = HERE / "upstream_sources.json"
MARKER_HEAD = "<!-- vexsign-radar v1"
SELECTED_RE = re.compile(r"^\s*[-*]\s+\[(?P<box>[ xX])\]\s+(?P<text>.*?)<!-- radar:(?P<key>[a-z0-9-]+):(?P<sha>[0-9a-f]{40}) -->",
                         re.M)
DIFF_HEADER_RE = re.compile(r'^diff --git (?:a/(?P<a>.+) b/(?P<b>.+)|"a/(?P<qa>.+)" "b/(?P<qb>.+)")$')
CONFLICT_FILE_RE = re.compile(r"Applied patch to '(?P<path>.+?)' with conflicts\.")
FAILED_RE = re.compile(r"^error: (?:patch failed: )?(?P<path>[^:]+?)(?::\d+)?: (?P<why>.*)$", re.M)
STATUS_EMOJI = {"applied": "✅", "already-present": "♻️", "conflict": "⚠️", "nothing-to-apply": "🧹",
                "unavailable": "❌", "reference": "📖", "error": "❌"}


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------

def run(cmd: list[str], cwd: Path, check: bool = True, input_text: str | None = None) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, input=input_text)
    if check and proc.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed ({proc.returncode}):\n{proc.stderr.strip() or proc.stdout.strip()}")
    return proc


def set_output(name: str, value: str) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


def append_summary(text: str) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")


def diff_path(line: str) -> tuple[str, str] | None:
    """(old, new) from a `diff --git` line. With --no-renames both are equal."""
    match = DIFF_HEADER_RE.match(line.rstrip("\n"))
    if not match:
        return None
    if match["a"] is not None:
        a, b = match["a"], match["b"]
        # `a/x b/x` where x may itself contain " b/": use the equal-length property.
        if a != b:
            joined = f"{a} b/{b}"
            if len(joined) % 2 == 1:
                half = (len(joined) - 3) // 2
                cand = joined[:half]
                if joined == f"{cand} b/{cand}":
                    return cand, cand
        return a, b
    return match["qa"], match["qb"]


# --------------------------------------------------------------------------
# selection
# --------------------------------------------------------------------------

def parse_selection(body: str) -> tuple[list[dict], int]:
    selected: list[dict] = []
    unchecked = 0
    seen: set[str] = set()
    for match in SELECTED_RE.finditer(body):
        if match["box"].strip().lower() != "x":
            unchecked += 1
            continue
        if match["sha"] in seen:
            continue
        seen.add(match["sha"])
        text = re.sub(r"<[^>]+>", "", match["text"]).strip()
        selected.append({"key": match["key"], "sha": match["sha"], "line": text})
    return selected, unchecked


# --------------------------------------------------------------------------
# patch rewriting
# --------------------------------------------------------------------------

class Section:
    def __init__(self, lines: list[str]) -> None:
        self.lines = lines
        paths = diff_path(lines[0]) or ("", "")
        self.old_path, self.new_path = paths
        self.path = self.new_path or self.old_path
        self.is_new = any(l.startswith("new file mode") for l in lines[:6])
        self.is_delete = any(l.startswith("deleted file mode") for l in lines[:6])
        self.is_binary = any(l.startswith("GIT binary patch") or l.startswith("Binary files") for l in lines[:12])
        self.role = "code"
        self.mapped: str | None = None
        self.reason = ""

    def rewritten(self, new_path: str) -> list[str]:
        out: list[str] = []
        in_header = True
        old, new = self.old_path, self.new_path
        # git terminates ---/+++ names that contain spaces with a TAB.
        tab = "\t" if " " in new_path else ""
        for line in self.lines:
            if in_header:
                if line.startswith("@@") or line.startswith("GIT binary patch") or line.startswith("Binary files"):
                    in_header = False
                elif line.startswith("diff --git "):
                    line = f"diff --git a/{new_path} b/{new_path}\n"
                elif line.startswith("--- a/") and line[6:].rstrip("\n").rstrip("\t") in (old, new):
                    line = f"--- a/{new_path}{tab}\n"
                elif line.startswith("+++ b/") and line[6:].rstrip("\n").rstrip("\t") in (old, new):
                    line = f"+++ b/{new_path}{tab}\n"
                elif line.startswith('--- "a/'):
                    line = f"--- a/{new_path}{tab}\n"
                elif line.startswith('+++ "b/'):
                    line = f"+++ b/{new_path}{tab}\n"
                elif line.startswith("rename from ") or line.startswith("copy from "):
                    line = line.split(" from ", 1)[0] + f" from {new_path}\n"
                elif line.startswith("rename to ") or line.startswith("copy to "):
                    line = line.split(" to ", 1)[0] + f" to {new_path}\n"
            out.append(line)
        return out

    def added_lines(self) -> list[str]:
        return [l[1:] for l in self.lines if l.startswith("+") and not l.startswith("+++")]


def split_patch(text: str) -> tuple[list[str], list[Section]]:
    lines = text.splitlines(keepends=True)
    preamble: list[str] = []
    sections: list[Section] = []
    current: list[str] | None = None
    for line in lines:
        if line.startswith("diff --git "):
            if current:
                sections.append(Section(current))
            current = [line]
        elif current is None:
            preamble.append(line)
        else:
            current.append(line)
    if current:
        sections.append(Section(current))
    # format-patch appends "-- \n<git version>\n" after the last diff; drop it.
    if sections:
        last = sections[-1].lines
        for index in range(len(last) - 1, max(0, len(last) - 4), -1):
            if last[index].startswith("-- \n") or last[index] == "-- \n":
                del last[index:]
                break
    return preamble, sections


def classify_sections(sections: list[Section], source: dict, config: dict, repo_root: Path) -> None:
    skip = GlobList(config.get("skip_paths", []))
    manual = GlobList(config.get("manual_paths", []))
    path_map = source.get("path_map") or {}
    for section in sections:
        path = section.path
        mapped = map_path(path, path_map) if path_map else None
        section.mapped = mapped
        hit = skip.match(path) or (mapped and skip.match(mapped))
        if hit:
            section.role, section.reason = "skipped", f"matches skip rule `{hit}`"
            continue
        hit = manual.match(path) or (mapped and manual.match(mapped))
        if hit:
            section.role, section.reason = "manual", "string catalog / asset - add through Xcode"
            continue
        if not path_map:
            section.role, section.reason = "reference", "different codebase"
            continue
        if mapped is None:
            section.role, section.reason = "unmapped", "outside the mapped layout"
            continue
        target = repo_root / mapped
        if section.is_delete and not target.exists():
            section.role, section.reason = "skipped", "deletes a file VexSign does not have"
            continue
        if section.is_new and target.exists():
            section.reason = "new upstream file collides with an existing VexSign file"
        section.role = "code"


# --------------------------------------------------------------------------
# git plumbing
# --------------------------------------------------------------------------

def fetch_commit(repo_root: Path, url: str, sha: str, branch: str | None) -> bool:
    if run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], repo_root, check=False).returncode == 0:
        return True
    proc = run(["git", "fetch", "--no-tags", "--depth=2", url, sha], repo_root, check=False)
    if proc.returncode == 0:
        return True
    print(f"   shallow fetch of {sha[:7]} failed ({proc.stderr.strip()[:120]}); fetching {branch or 'HEAD'} fully")
    proc = run(["git", "fetch", "--no-tags", url, branch or "HEAD"], repo_root, check=False)
    return run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], repo_root, check=False).returncode == 0


def commit_meta(repo_root: Path, sha: str) -> dict:
    fmt = "%H%x00%an%x00%ae%x00%aI%x00%s%x00%b"
    out = run(["git", "show", "-s", f"--format={fmt}", sha], repo_root).stdout
    full, name, email, date, subject, body = (out.split("\x00") + [""] * 6)[:6]
    return {"sha": full.strip(), "name": name, "email": email, "date": date, "subject": subject.strip(), "body": body.strip()}


def build_message(meta: dict, source: dict, issue: int | None, credit: str, login: str | None, coauthor_email: str | None) -> str:
    author = meta["name"] + (f" (@{login})" if login else "")
    lines = [meta["subject"], ""]
    if meta["body"]:
        lines += [meta["body"], ""]
    lines.append(f"Ported from {source['name']} ({source['repo']}@{meta['sha'][:7]}) by {author}.")
    lines.append(f"Original commit: https://github.com/{source['repo']}/commit/{meta['sha']}")
    lines.append("")
    lines.append(f"Upstream-Source: {source['repo']}@{meta['sha']}")
    lines.append(f"Upstream-Author: {author}")
    lines.append(f"Upstream-License: {source.get('license', 'unknown')}")
    if issue:
        lines.append(f"Merge-Kit-Issue: #{issue}")
    if credit == "shared" and coauthor_email:
        lines.append(f"Co-authored-by: {meta['name']} <{coauthor_email}>")
    return "\n".join(lines) + "\n"


# --------------------------------------------------------------------------
# main work
# --------------------------------------------------------------------------

def process(args: argparse.Namespace) -> int:
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    sources = {s["key"]: s for s in config["sources"]}
    source_order = [s["key"] for s in config["sources"]]
    labels = config.get("labels", {})
    repo_root = Path(args.workdir).resolve()
    out_dir = Path(args.out).resolve()
    patches_dir = out_dir / "patches"
    conflicts_dir = out_dir / "conflicts"
    patches_dir.mkdir(parents=True, exist_ok=True)

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    gh = GitHub(token, os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    write_github = not args.dry_run

    # ---- selection --------------------------------------------------------
    issue_number = args.issue
    if args.selection_file:
        body = Path(args.selection_file).read_text(encoding="utf-8")
        issue_url = ""
    else:
        if not issue_number:
            print("::error::--issue or --selection-file is required")
            return 1
        issue = gh.get(f"repos/{args.repo}/issues/{issue_number}")
        if not issue:
            print(f"::error::issue #{issue_number} not found in {args.repo}")
            return 1
        body = issue.get("body") or ""
        issue_url = issue.get("html_url", "")
    if MARKER_HEAD not in body:
        print("::error::this issue was not created by the Upstream feature radar (marker missing) - nothing to do")
        return 1
    selected, unchecked = parse_selection(body)
    print(f"{len(selected)} item(s) ticked, {unchecked} unticked")
    if not selected:
        msg = "No boxes are ticked in this radar issue. Tick the items you want, then comment `/prepare` again."
        print(f"::notice::{msg}")
        if write_github and issue_number and args.comment:
            gh.post(f"repos/{args.repo}/issues/{issue_number}/comments", {"body": f"🧰 **Merge kit:** {msg}"})
        set_output("applied", "0")
        return 0

    # ---- git state --------------------------------------------------------
    if run(["git", "status", "--porcelain", "--untracked-files=no"], repo_root).stdout.strip():
        print("::error::the working tree has uncommitted changes; refusing to build a merge kit on top of them")
        return 1
    base = args.base
    branch = args.branch or f"upstream-kit/issue-{issue_number or 'local'}"
    run(["git", "fetch", "--no-tags", "origin", base], repo_root)
    run(["git", "checkout", "-q", "-B", branch, "FETCH_HEAD"], repo_root)
    base_sha = run(["git", "rev-parse", "HEAD"], repo_root).stdout.strip()

    author_name = os.environ.get("GIT_AUTHOR_NAME") or run(["git", "config", "user.name"], repo_root, check=False).stdout.strip()
    author_email = os.environ.get("GIT_AUTHOR_EMAIL") or run(["git", "config", "user.email"], repo_root, check=False).stdout.strip()
    credit = args.credit
    if credit != "upstream" and not (author_name and author_email):
        print("::error::no git identity for the VexSign developer (run git_identity.sh first or pass --credit upstream)")
        return 1

    # ---- group & order ----------------------------------------------------
    by_source: dict[str, list[dict]] = {}
    for item in selected:
        by_source.setdefault(item["key"], []).append(item)
    ordered_keys = [k for k in source_order if k in by_source] + [k for k in by_source if k not in sources]

    results: list[dict] = []
    index = 0
    for key in ordered_keys:
        source = sources.get(key)
        items = by_source[key]
        if not source:
            for item in items:
                results.append({**item, "status": "unavailable", "note": f"unknown source key `{key}` (removed from upstream_sources.json?)",
                                "source": key, "subject": item["line"][:80]})
            continue
        url = f"https://github.com/{source['repo']}.git"
        print(f"→ {source['name']}: {len(items)} commit(s)")
        metas: list[dict] = []
        for item in items:
            ok = fetch_commit(repo_root, url, item["sha"], source.get("branch"))
            if not ok:
                results.append({**item, "status": "unavailable", "note": "commit could not be fetched from upstream",
                                "source": key, "subject": item["line"][:80]})
                continue
            meta = commit_meta(repo_root, item["sha"])
            api = gh.get(f"repos/{source['repo']}/commits/{item['sha']}") or {}
            login = (api.get("author") or {}).get("login")
            uid = (api.get("author") or {}).get("id")
            meta["login"] = login
            meta["coauthor_email"] = f"{uid}+{login}@users.noreply.github.com" if login and uid else meta["email"]
            metas.append(meta)
        metas.sort(key=lambda m: m["date"])

        for meta in metas:
            index += 1
            sha = meta["sha"]
            stem = f"{index:02d}-{key}-{sha[:7]}"
            result = {"index": index, "source": key, "source_name": source["name"], "repo": source["repo"], "license": source.get("license", "?"),
                      "sha": sha, "short": sha[:7], "subject": meta["subject"], "author": meta["name"], "login": meta.get("login"),
                      "date": meta["date"][:10], "url": f"https://github.com/{source['repo']}/commit/{sha}", "status": "", "note": "",
                      "patch": f"patches/{stem}.patch", "files": {"applied": [], "manual": [], "skipped": [], "unmapped": [], "reference": []},
                      "brand_mentions": 0, "followups": []}
            results.append(result)
            print(f"   [{index:02d}] {sha[:7]} {meta['subject'][:70]}")

            raw = run(["git", "format-patch", "-1", "--stdout", "--full-index", "--binary", "--no-renames", "--no-signature", sha], repo_root).stdout
            (patches_dir / f"{stem}.orig.patch").write_text(raw, encoding="utf-8")
            preamble, sections = split_patch(raw)
            classify_sections(sections, source, config, repo_root)

            apply_lines: list[str] = []
            manual_lines: list[str] = []
            brand = (source.get("brand") or "").lower()
            for section in sections:
                target = section.mapped or section.path
                if section.role == "code":
                    apply_lines += section.rewritten(target)
                    result["files"]["applied"].append(target + (f" ({section.reason})" if section.reason else ""))
                    if brand and source.get("family") != "reference":
                        result["brand_mentions"] += sum(1 for l in section.added_lines() if brand in l.lower())
                elif section.role == "manual":
                    manual_lines += section.rewritten(target)
                    result["files"]["manual"].append(target)
                    if target.endswith(".xcstrings"):
                        keys = sum(1 for l in section.added_lines() if re.match(r'\s{4}"[^"]+"\s*:\s*\{', l))
                        if keys:
                            result["followups"].append(f"≈{keys} string catalog entr{'y' if keys == 1 else 'ies'} in `{target}` (add via Xcode's String Catalog editor)")
                elif section.role == "reference":
                    manual_lines += section.lines
                    result["files"]["reference"].append(section.path)
                elif section.role == "unmapped":
                    manual_lines += section.lines
                    result["files"]["unmapped"].append(section.path)
                else:
                    result["files"]["skipped"].append(f"{section.path} — {section.reason}")
                    if section.path.endswith(".pbxproj"):
                        added = "".join(section.added_lines())
                        if "XCRemoteSwiftPackageReference" in added:
                            result["followups"].append("upstream added a Swift package in project.pbxproj - add it in Xcode (File → Add Package Dependencies)")
                        elif re.search(r"(IPHONEOS_DEPLOYMENT_TARGET|SWIFT_VERSION|OTHER_LDFLAGS|OTHER_SWIFT_FLAGS|INFOPLIST_KEY)", added):
                            result["followups"].append("upstream changed build settings in project.pbxproj - compare manually (hunks dropped; synchronized groups pick new files up automatically)")
            if result["brand_mentions"]:
                result["followups"].append(f"{result['brand_mentions']} added line(s) mention '{source.get('brand')}' - rename to VexSign / com.vexsign.app")

            if manual_lines:
                (patches_dir / f"{stem}.manual.patch").write_text("".join(preamble + manual_lines), encoding="utf-8")
                result["manual_patch"] = f"patches/{stem}.manual.patch"
            if not apply_lines:
                result["status"] = "reference" if source.get("family") == "reference" else "nothing-to-apply"
                result["note"] = ("different codebase - read the patch for ideas" if result["status"] == "reference"
                                  else "only project/docs/strings hunks - see follow-ups")
                continue

            patch_path = patches_dir / f"{stem}.patch"
            patch_path.write_text("".join(preamble + apply_lines), encoding="utf-8")

            proc = run(["git", "apply", "--3way", "--index", "--whitespace=nowarn", str(patch_path)], repo_root, check=False)
            output = (proc.stderr or "") + (proc.stdout or "")
            if proc.returncode == 0:
                if run(["git", "diff", "--cached", "--quiet"], repo_root, check=False).returncode == 0:
                    result["status"], result["note"] = "already-present", "VexSign already contains this change"
                    continue
                commit_cmd = ["git", "commit", "-q", "--no-verify"]
                if credit == "upstream":
                    commit_cmd += [f"--author={meta['name']} <{meta['email']}>", f"--date={meta['date']}"]
                else:
                    commit_cmd += [f"--author={author_name} <{author_email}>"]
                message = build_message(meta, source, issue_number, credit, meta.get("login"), meta.get("coauthor_email"))
                run(commit_cmd + ["-F", "-"], repo_root, input_text=message)
                result["status"] = "applied"
                result["commit"] = run(["git", "rev-parse", "--short", "HEAD"], repo_root).stdout.strip()
                if "three-way" in output or "3-way" in output:
                    result["note"] = "applied with a 3-way merge - review the result"
                continue

            # conflict / failure: snapshot conflicted files, then restore the tree
            conflicted = sorted(set(CONFLICT_FILE_RE.findall(output)))
            failed = [f"{m['path']}: {m['why']}" for m in FAILED_RE.finditer(output) if "with conflicts" not in m["why"]]
            snap_dir = conflicts_dir / stem
            for rel in conflicted:
                src = repo_root / rel
                if src.is_file():
                    dst = snap_dir / rel
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(src, dst)
            run(["git", "reset", "-q", "--hard", "HEAD"], repo_root)
            clean = ["git", "clean", "-fdq"]
            try:
                clean += ["-e", out_dir.relative_to(repo_root).as_posix()]
            except ValueError:
                pass
            run(clean, repo_root, check=False)
            result["status"] = "conflict"
            details = []
            if conflicted:
                details.append("conflicts in " + ", ".join(f"`{c}`" for c in conflicted[:6]) + (" …" if len(conflicted) > 6 else ""))
            if failed:
                details.append("; ".join(failed[:4]))
            result["note"] = "; ".join(details) or output.strip().splitlines()[-1][:200] if output.strip() else "git apply failed"
            result["conflicted_files"] = conflicted
            result["snapshot"] = f"conflicts/{stem}/" if conflicted else ""

    # ---- outcome ------------------------------------------------------------
    counts = {status: sum(1 for r in results if r["status"] == status) for status in STATUS_EMOJI}
    applied = counts["applied"]
    head_sha = run(["git", "rev-parse", "HEAD"], repo_root).stdout.strip()
    run_url = ""
    if os.environ.get("GITHUB_SERVER_URL") and os.environ.get("GITHUB_RUN_ID"):
        run_url = f"{os.environ['GITHUB_SERVER_URL']}/{args.repo}/actions/runs/{os.environ['GITHUB_RUN_ID']}"

    pushed = False
    if applied and args.push and write_github:
        run(["git", "push", "--force", "origin", f"HEAD:refs/heads/{branch}"], repo_root)
        pushed = True
        print(f"Pushed {applied} commit(s) to {branch}")

    pr_url = ""
    report_md = render_report(results, counts, selected, unchecked, issue_number, issue_url, branch, base, base_sha, run_url, credit, pushed)
    if pushed and args.pr:
        owner = args.repo.split("/")[0]
        title = f"Upstream merge kit for #{issue_number}: {applied} of {len(selected)} applied"
        existing = gh.get(f"repos/{args.repo}/pulls", {"head": f"{owner}:{branch}", "state": "open", "per_page": 1}) or []
        if existing:
            pr = gh.patch(f"repos/{args.repo}/pulls/{existing[0]['number']}", {"title": title, "body": report_md})
        else:
            pr = gh.post(f"repos/{args.repo}/pulls", {"title": title, "head": branch, "base": base, "body": report_md,
                                                     "draft": True, "maintainer_can_modify": True})
        pr_url = pr.get("html_url", "")
        print(f"Draft PR: {pr_url}")

    if issue_number and args.comment and write_github and not args.selection_file:
        comment = render_comment(results, counts, selected, branch, pr_url, run_url)
        gh.post(f"repos/{args.repo}/issues/{issue_number}/comments", {"body": comment})
        prepare_label = labels.get("prepare", "prepare-merge")
        try:
            gh._request("DELETE", f"repos/{args.repo}/issues/{issue_number}/labels/{urllib.parse.quote(prepare_label)}")
        except RuntimeError:
            pass

    (out_dir / "report.md").write_text(report_md, encoding="utf-8")
    (out_dir / "report.json").write_text(json.dumps({"issue": issue_number, "branch": branch, "base": base, "base_sha": base_sha,
                                                      "head": head_sha, "pr_url": pr_url, "counts": counts, "results": results},
                                                     indent=2), encoding="utf-8")
    append_summary(report_md)
    set_output("applied", str(applied))
    set_output("conflicts", str(counts["conflict"]))
    set_output("branch", branch if pushed else "")
    set_output("pr_url", pr_url)
    print(f"\n{applied} applied · {counts['conflict']} conflict(s) · {counts['nothing-to-apply'] + counts['reference']} manual-only · "
          f"{counts['already-present']} already present · {counts['unavailable']} unavailable")
    return 0


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def result_row(r: dict) -> str:
    emoji = STATUS_EMOJI.get(r["status"], "❔")
    subject = md_escape(r.get("subject", ""))[:80]
    link = f"[`{r['short']}`]({r['url']})" if r.get("url") else f"`{r.get('sha', '')[:7]}`"
    what = {"applied": f"applied as `{r.get('commit', '')}`", "already-present": "already in VexSign", "conflict": "conflict - patch in kit",
            "nothing-to-apply": "manual only", "unavailable": "unavailable", "reference": "reference only", "error": "error"}.get(r["status"], r["status"])
    note = md_escape(r.get("note", ""))[:160]
    return f"| {r.get('index', '')} | {r.get('source_name', r.get('source', ''))} | {link} | {subject} | {emoji} {what} | {note} |"


def render_report(results, counts, selected, unchecked, issue_number, issue_url, branch, base, base_sha, run_url, credit, pushed) -> str:
    out: list[str] = []
    ref = f"#{issue_number}" if issue_number else "the local selection"
    out.append(f"## Upstream merge kit for {ref}")
    out.append("")
    out.append(f"{len(selected)} item(s) selected ({unchecked} left unticked) · **{counts['applied']} applied** · {counts['conflict']} conflict(s) · "
               f"{counts['nothing-to-apply'] + counts['reference']} manual-only · {counts['already-present']} already present · {counts['unavailable']} unavailable")
    out.append("")
    out.append(f"Branch `{branch}` is rebuilt from `{base}` (`{base_sha[:7]}`) on every run - branch off it instead of committing to it directly. "
               "This is a **draft**: nothing is merged until you decide.")
    out.append("")
    out.append("| # | Source | Commit | Subject | Result | Notes |")
    out.append("|---|---|---|---|---|---|")
    for r in results:
        out.append(result_row(r))
    out.append("")

    followups = [(r, f) for r in results for f in r.get("followups", [])]
    conflicts = [r for r in results if r["status"] == "conflict"]
    manual = [r for r in results if r.get("manual_patch")]
    if conflicts or followups or manual:
        out.append("### Follow-ups")
        out.append("")
        for r in conflicts:
            files = ", ".join(f"`{f}`" for f in r.get("conflicted_files", [])[:8]) or "see notes"
            out.append(f"- **[{r['index']:02d}] {md_escape(r['subject'])[:70]}** did not apply cleanly: {files}. "
                       f"Apply `{r['patch']}` from the kit artifact with `git am -3` and resolve, or port by hand"
                       + (f"; the conflicted files are snapshotted under `{r['snapshot']}`." if r.get("snapshot") else "."))
        for r in manual:
            out.append(f"- **[{r['index']:02d}]** strings/assets/unmapped hunks are in `{r['manual_patch']}` "
                       f"({', '.join(f'`{f}`' for f in (r['files']['manual'] + r['files']['unmapped'] + r['files']['reference'])[:6])}).")
        for r, note in followups:
            out.append(f"- **[{r['index']:02d}]** {note}")
        out.append("")

    out.append("### Next steps")
    out.append("")
    out.append("1. The **Quick check** and **Build check** workflows run on this PR - fix what they flag.")
    out.append("2. Apply the conflicting patches locally (`git am -3 patches/NN-*.patch`) if you still want them.")
    out.append("3. Add string-catalog entries through Xcode, rename any upstream branding to VexSign, run the app.")
    out.append("4. Merge when green - or close the PR; the radar will not offer the same items again.")
    out.append("")

    out.append("### Attribution")
    out.append("")
    by_repo: dict[str, dict] = {}
    for r in results:
        if r["status"] in ("applied", "conflict", "already-present", "nothing-to-apply", "reference"):
            entry = by_repo.setdefault(r["repo"], {"name": r.get("source_name", r["source"]), "license": r.get("license", "?"), "count": 0, "authors": set()})
            entry["count"] += 1
            if r.get("author"):
                entry["authors"].add(r["author"] + (f" (@{r['login']})" if r.get("login") else ""))
    out.append("| Project | Repository | License | Commits | Authors |")
    out.append("|---|---|---|---:|---|")
    for repo, entry in by_repo.items():
        out.append(f"| {entry['name']} | [{repo}](https://github.com/{repo}) | {entry['license']} | {entry['count']} | {md_escape(', '.join(sorted(entry['authors'])))} |")
    out.append("")
    credit_line = {"vexsign": "Commits are authored by the VexSign developer; the upstream project, commit, author and license are recorded in the "
                              "`Upstream-Source`, `Upstream-Author` and `Upstream-License` trailers of every ported commit.",
                   "shared": "Commits are authored by the VexSign developer with the upstream author as `Co-authored-by`; provenance trailers are included.",
                   "upstream": "Commits keep their upstream authorship; provenance trailers are included."}[credit]
    out.append(credit_line + " Ported files keep their own copyright/licence headers, as GPL-3.0 §5 / AGPL-3.0 require. VexSign remains GPL-3.0.")
    out.append("")
    if run_url:
        out.append(f"<sub>Kit artifact (patches, manual hunks, conflict snapshots): {run_url}</sub>")
    if issue_url:
        out.append(f"<sub>Source checklist: {issue_url}</sub>")
    return "\n".join(out)


def render_comment(results, counts, selected, branch, pr_url, run_url) -> str:
    out = [f"### 🧰 Merge kit ready — {counts['applied']} of {len(selected)} applied"]
    out.append("")
    if pr_url:
        out.append(f"Draft PR: {pr_url} (branch `{branch}`)")
    elif counts["applied"]:
        out.append(f"Branch `{branch}` (PR creation was disabled).")
    else:
        out.append("Nothing could be applied automatically - see the table and the kit artifact.")
    out.append("")
    out.append("| # | Source | Commit | Subject | Result | Notes |")
    out.append("|---|---|---|---|---|---|")
    for r in results:
        out.append(result_row(r))
    out.append("")
    if run_url:
        out.append(f"Patches, manual-only hunks and conflict snapshots: [workflow artifact]({run_url}).")
    out.append("Tick more boxes and comment `/prepare` again to rebuild the kit (the branch is regenerated from `main`).")
    return "\n".join(out)


# --------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--issue", type=int, default=None, help="radar issue number")
    parser.add_argument("--selection-file", help="markdown file with ticked radar items (local testing)")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "iamsmmh/VexSign"))
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--workdir", default=os.getcwd(), help="VexSign checkout")
    parser.add_argument("--out", default=os.path.join(os.environ.get("RUNNER_TEMP", "/tmp"), "merge-kit"))
    parser.add_argument("--base", default=os.environ.get("KIT_BASE", "main"))
    parser.add_argument("--branch", default=None)
    parser.add_argument("--credit", choices=["vexsign", "shared", "upstream"], default=os.environ.get("CREDIT_MODE", "vexsign"))
    parser.add_argument("--no-push", dest="push", action="store_false")
    parser.add_argument("--no-pr", dest="pr", action="store_false")
    parser.add_argument("--no-comment", dest="comment", action="store_false")
    parser.add_argument("--dry-run", action="store_true", help="do not push, open PRs or comment")
    args = parser.parse_args()
    try:
        return process(args)
    except RuntimeError as exc:
        print(f"::error::{exc}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
