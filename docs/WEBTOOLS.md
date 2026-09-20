# Web tools

Three browser tools served by the Python backend in [`server/`](../server/),
under `/tools`. They cover the parts of the workflow that are easier in a browser
than on a phone: building a feed, reading a profile, and getting a UDID.

| Page | Purpose | Module |
| --- | --- | --- |
| `GET /tools` | Hub linking the three tools | `server/web_tools.py` |
| `GET /tools/repo-creator` | Build, validate and export an AltStore-compatible feed | `server/repo_creator.py` |
| `GET /tools/cert-check` | Read a provisioning profile's validity, team, entitlements and device scope | `server/cert_inspector.py` |
| `GET /tools/udid` | Read a device UDID through a one-time enrolment profile | `server/udid_grabber.py` |

Shared page chrome (CSS + `page()`) lives in `server/web_chrome.py`. The app
links to all three from **Settings → Ecosystem → Web Tools**.

## 1. Repository creator

A form for repository metadata plus a repeatable app list, with import from a
file or URL, live validation, and export.

| Endpoint | Body | Returns |
| --- | --- | --- |
| `POST /api/tools/repo/validate` | `{"draft": {…}}` | `issues[]` (`error`/`warning`, message, suggestion, app), counts |
| `POST /api/tools/repo/export` | `{"draft": {…}, "format": "altstore"\|"flat"\|"apps"}` | `filename`, pretty `json`, `errorCount` |
| `POST /api/tools/repo/ota` | `{"app": {…}, "manifestURL", "displayImageURL", "fullSizeImageURL"}` | manifest plist, `installLink` |

The validation rules mirror `VexSign/RepositoryBuilder/RepositoryValidator.swift`
(missing identifiers, non-http(s) URLs, unparseable dates, duplicate screenshots,
duplicate bundle ids), so a feed that passes here imports cleanly in the app.
`altstore` emits `versions[]` history, `flat` the Feather/ESign-style schema,
`apps` the bare `apps.json` array.

**The OTA endpoint refuses cleartext**: both the IPA URL and the manifest URL
must be `https`, because `itms-services://` will not install over http. Nothing is
uploaded or hosted — you get a manifest file and a link to paste.

Hosting the feed is your job: this server's own `POST /api/admin/apps` reads each
IPA's `Info.plist` and publishes `/repo/source.json`, or use any static HTTPS
host.

## 2. Certificate status checker

Parses what a provisioning profile actually says, and nothing more.

| Endpoint | Purpose |
| --- | --- |
| `POST /api/tools/cert/inspect` | multipart upload of a `.mobileprovision` (or public `.cer`/`.pem`) → status, team, App ID, entitlements, device count, expiry countdown, fingerprints, revocation lookup |
| `GET /api/tools/cert/revoked-list` | the curated list this deployment consults |

The page parses the profile **in the browser** (the plist is extracted from the
CMS blob and read with `DOMParser`); the upload button is opt-in for people who
want the server's parse and revocation lookup.

Status is computed from the profile's own validity window: `valid`, `expiring`
(≤30 days), `critical` (≤7 days), `expired`.

Hard limits, by design:

- **No `.p12`, no password.** The endpoint has no password field and rejects
  `.p12`/`.pfx` uploads with a 422. There is nothing to leak.
- **Apple is never queried.** "Revoked" means *listed in
  `server/data/revoked_certs.json` on this deployment*; an unlisted certificate
  is reported as **unknown**, never as valid. See
  [`server/data/README.md`](../server/data/README.md) for the format.
- **Parsing is not verification.** The plist is read out of the signed blob; that
  says nothing about who signed it.
- **Public certificates** (`.cer`/`.pem`) get subject, issuer, validity, CA flag
  and fingerprints when the optional `cryptography` package is installed, and
  fingerprints alone when it is not. It is not in `requirements.txt` on purpose —
  the profile path, which is the common case, is pure stdlib.

## 3. UDID grabber

| Endpoint | Purpose |
| --- | --- |
| `GET /tools/udid` | page; creates a one-time session token |
| `GET /api/tools/udid/profile?token=…` | the enrolment `.mobileconfig` |
| `POST /api/udid/callback?token=…` | where iOS posts the signed attribute plist |
| `GET /api/tools/udid/session/{token}` | the page polls this for the UDID |

The profile is a standard *Profile Service* payload (`PayloadType = Profile
Service`, `PayloadVersion = 1`) asking for `DEVICE_UDID`, `DEVICE_NAME`,
`PRODUCT`, `SERIAL`, `VERSION`, `IMEI` and `MEID`. iOS posts the result back as a
raw CMS-signed plist; the callback pulls the plist out of the body and stores the
attributes against the token.

Guards:

- Sessions live in process memory for **15 minutes**, capped at **200** (oldest
  evicted first). Nothing is written to disk and no UDID is logged.
- An expired session's callback gets **410 Gone** and the UDID is discarded.
- A response without a UDID gets **422**, so a malformed post cannot mark a
  session as received.
- The token is a bearer secret: whoever holds the page URL sees the UDID posted
  to it.
- The generated profile is **unsigned**, so iOS says so. Sign it with your own
  certificate to remove the warning.
- Install flow on iOS 16+: Settings → *Profile Downloaded* → Install; remove it
  afterwards.

## Deployment

Nothing extra is required: the tools ship with `server/main.py` and are mounted
by `app.include_router(web_tools_router)`. Set `PUBLIC_BASE_URL` if your proxy
does not forward `X-Forwarded-Host`/`X-Forwarded-Proto` — the UDID callback URL
is built from it (see `server/request_base.py`, the single implementation shared
with the premium API).

```sh
cd server
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000   # then open http://localhost:8000/tools
```

Tests: `server/tests/test_web_tools.py` (25 cases) covers validation, all three
export formats, the OTA manifest, profile parsing (valid / expiring / expired),
`.p12` rejection, the revocation lookup, public-certificate parsing, the profile
payload, the callback happy path, expiry and the session cap.

```sh
cd server && python -m pytest tests/ -q
```
