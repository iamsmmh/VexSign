# VexSign Premium Backend

This directory contains the private backend that powers VexSign's premium
features — license-key validation and the gated premium source the app unlocks.

It is committed to the public repository **for transparency only**: anyone can
audit exactly what the app communicates with, what data is stored (key, device
binding, status — nothing else), and how keys are enforced. It is **not** a
deployment or self-hosting guide, and no setup instructions are published.

## Keys

- Premium keys are **single-use and device-bound**.
- Keys are issued exclusively through the official distribution channel —
  contact **[@iamSMMH](https://t.me/iamSMMH)** on Telegram.
- Keys found anywhere else are not valid; unknown, reused or disabled keys are
  rejected by design.

## Contact

Questions about premium, key issues, or refunds: **[@iamSMMH](https://t.me/iamSMMH)**.
Security findings about this service: please report them privately to the same
contact before disclosing anything publicly.

## Self-hosted source

Besides premium keys, this backend can host an AltStore-compatible source of your
own: upload IPAs, and `/repo/source.json` lists them in the exact shape
VexSign's `ASRepository` decodes (add it under **Sources → Add**).

| Endpoint | Purpose |
| --- | --- |
| `GET /repo/source.json` | AltStore v1 source (public) |
| `GET /repo/appdata` | Legacy AltServer XML feed (public) |
| `GET /static/apps/<file>.ipa` | The IPAs themselves (public) |
| `POST /api/admin/apps` | Upload an IPA (multipart `file`, admin token) |
| `GET /api/admin/apps` | List the source (admin token) |
| `DELETE /api/admin/apps/{bundle_identifier}` | Drop an app (admin token) |

Bundle id, name and version are read from the IPA's own `Info.plist`, so the feed
can never disagree with the package it points at. Uploading a new version of an
existing bundle id replaces it.

```sh
curl -X POST https://your-host/api/admin/apps \
  -H "X-Admin-Token: $ADMIN_TOKEN" \
  -F "file=@MyApp.ipa" -F "developer=Me" -F "subtitle=My build"
```

Storage is a JSON index plus a folder of IPAs — no database. Point
`REPO_STORE_DIR` at a mounted volume so uploads survive a redeploy:

```sh
make deploy-server                 # builds the linux/amd64 image
docker run -p 8080:8080 -e ADMIN_TOKEN=<secret> -v vexsign-repo:/data vexsign-server
```

Tests for this surface live in `server/tests/`:

```sh
pip install -r requirements.txt pytest httpx
python -m pytest tests/ -q
```
