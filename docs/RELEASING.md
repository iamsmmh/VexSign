# Releasing VexSign

Two rules cover almost everything:

1. **Real releases are tag pushes.** Push `vX.Y.Z` and CI builds, verifies and
   publishes it. Reproducible (the tag pins the commit and the version) and
   automatic (no inputs to remember, and `app-repo.json` is synced afterwards).
2. **Testing is `build_only = true`.** Run the Release workflow manually from any
   branch, leave `build_only` ticked (the default), and download the IPA from
   the run page. Nothing is published, no tag is created.

Both run the same [`Release` workflow](../.github/workflows/release.yml); they
just stop at different points.

## Publish a release (tag push)

1. **Bump the version.** Set `MARKETING_VERSION` for all targets - Xcode →
   VexSign target → *General* → *Version*, or from the repo root:

   ```sh
   agvtool new-marketing-version 1.2.0
   ```

   Commit it (`chore(release): bump version to 1.2.0`) and land it on `main`
   through a normal PR. The PR build proves the release commit compiles before
   it is tagged.

2. **Tag that commit and push the tag.**

   ```sh
   git checkout main && git pull
   git tag -a v1.2.0 -m "VexSign v1.2.0"
   git push origin v1.2.0
   ```

3. **Watch the run** under *Actions → Release*. On success it has:
   - a GitHub release `VexSign v1.2.0` for the tag, with `VexSign.ipa` attached
     and release notes generated from the commits since the previous release;
   - the same IPA attached to the run as an artifact.

4. **The source updates itself.** Publishing the release triggers the
   [`Update Repository`](../.github/workflows/update_repo.yml) workflow, which
   rewrites `app-repo.json` (version, download URL, size, notes, news card) and
   commits it to `main`. Pre-releases are synced too - they are "published"
   releases as far as GitHub is concerned.

### Tag rules

- The tag is **`v` + `MARKETING_VERSION`**, exactly: `1.2.0` → `v1.2.0`,
  `1.2` → `v1.2`. The workflow refuses a tag that doesn't match the project
  (before building) and a build whose `CFBundleShortVersionString` doesn't
  match the tag (after building), so a stale version can never ship under a
  new tag.
- **Pre-releases** append a suffix: `v1.2.0-beta.1`, `v1.2-rc1`. The release
  is marked as a pre-release; the app still reports `1.2.0` (Apple version
  strings can't carry the suffix). Release notes for a pre-release cover
  everything since the last tag of any kind; notes for a stable release skip
  pre-release tags, so `v1.2.0` lists everything since `v1.1.0`.
- **Never move a tag that has been published.** If a release must change, cut
  a new patch version. If the tag run *failed* (nothing was published), fixing
  and re-tagging is fine: `git tag -f v1.2.0 && git push -f origin v1.2.0`.
- The **build number** (`CFBundleVersion`) is the full commit SHA, stamped by
  CI, so any installed build can be traced back to its source.

### Reproducibility knobs

- Tag runs use the newest Xcode on the runner image. To pin the toolchain,
  set a repository variable **`RELEASE_XCODE`** (e.g. `26.3`) under
  *Settings → Secrets and variables → Actions → Variables*. A manual run's
  `xcode` input overrides it for that run only.
- Preview the notes CI will generate:

  ```sh
  VERSION=1.2.0 tools/generate-changelog.sh
  ```

## Test a change without publishing (`build_only`)

1. *Actions → Release → Run workflow*.
2. Pick the branch (or tag) to build. Leave **`build_only` ticked**.
   Optionally set `xcode` to try a specific toolchain.
3. When the run finishes, the IPA is under *Artifacts* on the run page
   (`VexSign-<version>-<sha>`, kept for 14 days). The run summary links to it.

Nothing else happens: no release, no tag, no `app-repo.json` change. Pull
requests against `main` get exactly this treatment automatically, so a PR's
run page also has an installable IPA.

## Synthetic compatibility tags (validation-only runs)

The repository history carries **synthetic milestone tags** — `v0.0.1` through
`v0.0.18`, `v1.0.0` — annotated like:

```
VexSign v0.0.18 FlareStore parity milestone (synthetic tag)
```

They mark parity milestones and intentionally do **not** match
`MARKETING_VERSION` (currently `1.0`). Pushing or re-pushing one therefore
must not fail the version checks and must never publish a release. The
workflow detects the phrase *synthetic tag* in the tag annotation and:

- runs the **full build + packaging + validation** for the tagged commit;
- attaches the IPA to the run as an **artifact** (same as `build_only`);
- publishes **nothing** and does not touch `app-repo.json`;
- reports itself as a **compatibility milestone** in the run summary.

Real releases are unaffected: a tag whose annotation does not say *synthetic
tag* still has to match `MARKETING_VERSION` exactly, before *and* after the
build.

## Manual publish (escape hatch)

Unticking `build_only` publishes `v<MARKETING_VERSION>` from the head of the
selected branch. It exists for the cases a tag push can't cover - mainly
creating a **draft** release to review the notes before they go live (tick
`draft`; GitHub creates the tag when you publish the draft). Guard rails:

- the tag is created at the **exact commit that was built**, not wherever the
  branch head is by the time the build finishes;
- it **refuses to run if the tag already exists**, so a published release is
  never silently overwritten by a branch build. Bump `MARKETING_VERSION`, or
  re-run the tag's own workflow run instead;
- `prerelease` / `draft` inputs apply only to this mode.

Dispatching with `build_only` unticked *on a tag* re-publishes that tag from
the same source (the version checks still apply); it is equivalent to
re-running the tag's run.

## When something goes wrong

| Symptom | What it means | Fix |
| --- | --- | --- |
| `v1.2.0 does not match the project's MARKETING_VERSION (1.1.0)` | The tag was pushed before the version bump landed. | Bump the version, commit, move the tag onto that commit (`git tag -f v1.2.0 && git push -f origin v1.2.0`). |
| `The built app reports CFBundleShortVersionString 1.1.0, but v1.2.0 promises 1.2.0` | Same thing, caught after the build (targets disagreed on the version, so the pre-build check was skipped). | Set the same `MARKETING_VERSION` on every target and re-tag. |
| `v1.2.0 already exists on origin; refusing to overwrite` | A manual publish targeted a version that is already released. | Bump `MARKETING_VERSION` for a new release. To re-publish the existing one, re-run its tag's workflow run. |
| Tag push did nothing | The tag doesn't match `v<major>.<minor>[.<patch>][-<suffix>]`. | Delete it and push a correctly named tag. |
| Build failed on a tag push | Same failure a PR would have shown. | Fix on `main`, then re-tag the fixed commit. Nothing was published. |
| Release exists but `app-repo.json` didn't update | `Update Repository` failed or ran before the assets were visible. | *Actions → Update Repository → Run workflow* with `tag` = `v1.2.0`. |
