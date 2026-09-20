# Automation

Everything under `.github/workflows/` and `.github/scripts/`. All of it runs on
GitHub Actions; commits it creates are credited to the VexSign developer
(the repository owner), never to a bot.

| Workflow | When | What it does | Runner |
| --- | --- | --- | --- |
| **Quick check (no build)** — `quick-check.yml` | every push, and PRs to `main` (the merge result) | Finds build-breaking mistakes in ~1 minute: conflict markers, Swift syntax errors (`swiftc -parse`), duplicate types / file names inside a target, broken `Info.plist` / entitlements / `*.xcstrings` / JSON / schemes, corrupted `project.pbxproj`. Annotates file + line and shows the offending source lines in the job summary. | Linux (Swift container) |
| **Build check** — `build-check.yml` | push + PR to `main` | `xcodebuild -workspace VexSign.xcworkspace -scheme VexSign -configuration Debug build` (unsigned). Fails on any compiler error and on any *new* warning in first-party code (see [Warnings as errors](#warnings-as-errors)). Uploads the `.xcresult` and raw log when it fails. | macOS 15 |
| **SwiftLint auto-fix** — `lint-fix.yml` | PRs to `main` touching Swift | `swiftlint --fix` on the files the PR changed (`.swiftlint.yml`), commits `style: auto-fix SwiftLint violations` back to the PR branch, annotates what could not be fixed. | macOS 15 |
| **Upstream feature radar** — `upstream-features.yml` | Mondays 06:00 UTC, manual | Scans Feather, FeatherPlus, Ksign, KorSign, RyukSign, MySignReincarnated, SideStore and LiveContainer; opens **one issue with a checklist** of candidate commits (author, date, files mapped onto VexSign, feasibility). | Linux |
| **Upstream merge kit** — `upstream-merge-kit.yml` | `/prepare` comment or `prepare-merge` label on a radar issue, manual | Applies the ticked commits on a fresh `upstream-kit/issue-<n>` branch, opens a **draft PR** with a per-commit result table, attaches patches + conflict snapshots. Nothing is merged automatically. | Linux |

The existing `Release` and `Update Repository` workflows are unchanged.

## Fixing errors without a full build

A cold `xcodebuild` of VexSign compiles Vapor, NIO, Nuke and friends and takes a
long time on a macOS runner. The quick check runs first and covers what most
merges break:

1. **Conflict markers** left behind by a merge.
2. **Syntax errors** — real compiler diagnostics from `swiftc -parse`
   (parsing only, so no SDK, no package resolution, no signing).
3. **Duplicate top-level types** in one module (`invalid redeclaration`) and
   **duplicate file names** in one target (Xcode: *filename used twice*). Both
   are the classic result of porting a feature that already exists.
4. **Resources that no longer parse** — `Info.plist`, entitlements, string
   catalogs, JSON, schemes — and an unbalanced `project.pbxproj`.

Each finding is an inline annotation plus a snippet in the job summary, so it
can be fixed from the PR page. Style problems are fixed automatically by
SwiftLint on pull requests; real semantic errors (type mismatches, missing
symbols) still need the compiler and surface in **Build check**, which
annotates them inline as well.

Run the quick check locally on macOS (Xcode installed) or Linux (Swift
toolchain):

```sh
python3 .github/scripts/quick_check.py
```

## Warnings as errors

The build check treats first-party warnings (`VexSign/`, `VexSignWidgetExtension/`,
`VexSignTests/`, `AltSourceKit/`, `NimbleKit/`) as errors, with a **baseline**
so it could be switched on without first fixing the 51 warnings the code had
(mostly Swift 6 concurrency diagnostics and deprecated API):

* `.github/build-warnings-baseline.json` lists the known warnings as
  `file + message + count` (line numbers are ignored, so edits above a warning
  do not break the match).
* A warning that is **not** in the baseline fails the check and is annotated
  as *New warning (treated as error)*. Known ones are annotated as
  *Known warning (baseline)* and listed, collapsed, in the summary.
* When warnings disappear, the summary says so and the run attaches a
  regenerated `build-warnings-baseline.json` — commit it to lock the
  improvement in. The baseline only ever shrinks unless you decide otherwise.
* Warnings in SwiftPM dependencies (Vapor, Zsign, …) are counted but never fail
  the check.

`BUILD_WARNINGS_AS_ERRORS` (repository variable or the manual-run input):
`true` (default, baseline mode), `strict` (every first-party warning fails),
`false` (report only).

To accept new warnings deliberately: download `build-warnings-baseline.json`
from the run's artifacts and replace the file in `.github/`.

## Collecting features from other signers

```
 Monday 06:00 UTC / manual                  you                          /prepare
┌────────────────────────┐   issue with   ┌──────────────┐   comment    ┌───────────────────────────┐
│ Upstream feature radar │ ─────────────▶ │ tick boxes   │ ───────────▶ │ Upstream merge kit        │
│ scan 8 repos, classify │   checklist    │ (choose)     │   or label   │ branch + draft PR + patch │
└────────────────────────┘                └──────────────┘              └───────────────────────────┘
```

**Radar issue.** One line per candidate commit:

```
- [ ] ✅ feat Add batch re-sign — a1b2c3d · @author · 2026-09-12 · 4 files · likely applies (3 existing, 1 new)
```

* ✅ likely applies · 🆕 new files only · 🟡 partial (files outside the mapped
  layout) · 🧹 non-code · 🌐 string catalog / assets need Xcode · 🧩 project-file
  hunks dropped · 📖 reference only (SideStore, LiveContainer: different
  codebase, AGPL-3.0 — ideas, not code) · ⚠️ needs attention (adds a package,
  changes entitlements, mentions the upstream brand).
* Merge commits, chores, translations, bot commits and commits VexSign already
  has (same subject, or an `Upstream-Source` trailer) are listed collapsed, not
  as options. Items shown in an earlier radar issue are not repeated
  (`include_seen` re-lists them). A new radar issue closes the previous one.
* Releases in the window are shown with their notes for context.

**Merge kit.** For every ticked commit:

1. fetch it from upstream (`--depth=2`, so a 3-way merge has its base);
2. rewrite paths — `Feather/` → `VexSign/`, `RyukSignWidgetExtension/` →
   `VexSignWidgetExtension/`, `KsignApp.swift` → `VexSignApp.swift`, … (see
   `path_map` in `upstream_sources.json`);
3. drop `*.xcodeproj`, workspace, CI, docs, image and submodule hunks
   (synchronized groups pick new files up automatically; a note is added when
   upstream added a Swift package or changed build settings);
4. set `*.xcstrings` and asset-catalog hunks aside as `NN-….manual.patch`
   (CONTRIBUTING.md: the string catalog is edited through Xcode only);
5. `git apply --3way --index` on `upstream-kit/issue-<n>`; a clean result is
   committed, a conflict is **not** — the rewritten patch and the conflicted
   files (with markers) go into the run artifact instead, so the branch stays
   buildable.

Then the branch is force-pushed, a **draft PR** is opened (or refreshed) with the
result table, follow-ups and attribution, and the same table is posted on the
issue. Tick more boxes and `/prepare` again to rebuild the kit; it always starts
from `main`, so branch off it rather than committing to it.

Apply a conflicting patch yourself:

```sh
git switch upstream-kit/issue-42
git am -3 ~/Downloads/merge-kit-issue-42/patches/03-ryuksign-415940b.patch
# resolve, then: git add -A && git am --continue
```

### Credit and licences

* Commits created by the kit are **authored by the VexSign developer**. The
  upstream project, commit, author and licence are recorded in trailers on
  every ported commit, and the PR carries an attribution table:

  ```
  Upstream-Source: claration/Feather@3910f21b05998dd8f2e6f50c49bb3a7507c612cc
  Upstream-Author: Mehdi Kharraz (@imkh)
  Upstream-License: GPL-3.0
  Merge-Kit-Issue: #42
  ```

  `MERGE_KIT_CREDIT=shared` adds `Co-authored-by`, `upstream` keeps the original
  author. Ported files keep their own copyright headers — GPL-3.0 §5 requires
  that, and VexSign stays GPL-3.0.
* SideStore and LiveContainer are **AGPL-3.0** and a different codebase. The
  radar lists their changes as reference material; the kit never applies them.
  Re-implement ideas; do not paste their code into a GPL-3.0 project.

### Editing the source list

`.github/scripts/upstream_sources.json` — add or remove a source, fix a
repository that moved, extend a `path_map`, or tune the noise filters
(`ignore_commit_patterns`, `skip_paths`, `manual_paths`). Parents must come
before their forks so a commit that exists in both is attributed to the
original. "KoSign" was mapped to `korboybeats/KorSign` (a RyukSign fork);
change `repo` if a different project was meant.

## Configuration

Repository **variables** (Settings → Secrets and variables → Actions → Variables); all optional:

| Variable | Default | Purpose |
| --- | --- | --- |
| `BUILD_XCODE` | newest installed | Xcode version prefix for Build check (`26.3`, `26`, `16.4`). The code needs the iOS 26 SDK (`.glassEffect`, `SWIFT_APPROACHABLE_CONCURRENCY`, iOS 26 widget target), so Xcode 16 cannot build it. |
| `BUILD_WARNINGS_AS_ERRORS` | `true` | `true` = fail on first-party warnings not in `.github/build-warnings-baseline.json`; `strict` = fail on all; `false` = report only. Dependency warnings never fail it. |
| `QUICK_CHECK_SWIFT_IMAGE` | `swift:6.4-noble` | Swift container used by the quick check. |
| `AUTOMATION_GIT_NAME` / `AUTOMATION_GIT_EMAIL` | owner's GitHub profile | Identity for commits made by the workflows. |
| `MERGE_KIT_CREDIT` | `vexsign` | `vexsign`, `shared` or `upstream` (see above). |

Repository **secret** (optional): `CI_PUSH_TOKEN` — a fine-grained PAT with
*Contents: write* and *Pull requests: write*. Pushes made with the default
`GITHUB_TOKEN` do not start other workflows, so the auto-fix commit and the
merge-kit branch would not get their own Build/Quick check runs; with the PAT
they do.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Build check fails with `value of type ... has no member 'glassEffect'` | `BUILD_XCODE` pins an Xcode without the iOS 26 SDK | Unset it or set `26`. |
| Build check is red with *New warning (treated as error)* | the change introduces a warning that is not in the baseline | Fix it (preferred), or commit the regenerated `build-warnings-baseline.json` from the run's artifact. `BUILD_WARNINGS_AS_ERRORS=false` turns the gate off. |
| Summary says baseline warnings no longer occur | warnings were fixed | Commit the regenerated baseline from the run's artifact so they cannot come back. |
| SwiftLint fixes were not pushed | fork PR (read-only token) | Run `swiftlint --fix` locally. |
| Radar issue not created | nothing new upstream, or `create_issue` unticked | Check the run summary / artifact; use `include_seen` to re-list. |
| `/prepare` did nothing | commenter is not owner/member/collaborator, or the issue is not a radar issue | Add the `prepare-merge` label or run the workflow manually with the issue number. |
| Most kit items conflict | VexSign diverged from that upstream in those files | Expected for big commits; apply the patch with `git am -3` and resolve, or port by hand from the snapshot. |
