#!/usr/bin/env python3
"""Browser tools that live next to the VexSign backend.

The iOS app covers signing on-device; these pages cover the things people need a
browser for — driving the phone's signer, building and reading repository feeds,
reading a provisioning profile, and reading a device UDID off an iPhone:

    GET /tools                 hub page linking the tools
    GET /tools/signer          signing console (relays to the phone's Web Manager)
    GET /tools/repo-creator    web-based AltStore-compatible repository builder
    GET /tools/repo-decoder    read any source feed, export it in another dialect
    GET /tools/app-installer   OTA install link + reachability probe for a hosted IPA
    GET /tools/cert-check      certificate / provisioning-profile status checker
    GET /tools/udid            UDID grabber (enrolment profile + callback)

Their JSON APIs live in the sibling modules (`web_signer`, `repo_creator`,
`repo_decoder`, `app_installer`, `cert_inspector`, `udid_grabber`); shared page
rendering is in `web_chrome`. Everything here is public by design — none of the
tools touch premium keys, private keys or the admin surface — but see each
module's docstring for the privacy stance: nothing is persisted, and the signer
relay only talks to private network addresses by default.
"""

from __future__ import annotations

import html

from fastapi import APIRouter, Request

import app_installer
import cert_inspector
import repo_creator
import repo_decoder
import udid_grabber
import web_signer
from web_chrome import TOOLS, page

router = APIRouter()
router.include_router(web_signer.router)
router.include_router(repo_creator.router)
router.include_router(repo_decoder.router)
router.include_router(app_installer.router)
router.include_router(cert_inspector.router)
router.include_router(udid_grabber.router)


@router.get("/tools")
def tools_hub(request: Request):
    cards = "\n".join(
        f"""  <a class="card" href="{href}" style="text-decoration:none;color:inherit;display:block">
    <h2>{html.escape(name)}</h2>
    <p class="muted" style="margin:0">{html.escape(blurb)}</p>
  </a>"""
        for href, name, blurb, _ in TOOLS
    )
    body = f"""
  <p class="muted">Browser-side helpers for the VexSign workflow. None of them hold
  a private key: signing always happens on the phone, and the signer console only
  relays to it.</p>
  <div class="grid">
{cards}
  </div>
  <div class="card">
    <h2>Backend endpoints</h2>
    <ul class="muted">
      <li><code>POST /api/tools/sign/proxy</code> — read the phone's status / library / updates</li>
      <li><code>POST /api/tools/sign/sign</code> — relay an IPA to the phone, stream the signed IPA back</li>
      <li><code>POST /api/tools/repo/validate</code> — lint a repository draft</li>
      <li><code>POST /api/tools/repo/decode</code> — normalise any source-feed dialect</li>
      <li><code>POST /api/tools/repo/convert</code> — re-export a feed in another schema</li>
      <li><code>POST /api/tools/install/manifest</code> — OTA manifest + <code>itms-services://</code> link</li>
      <li><code>POST /api/tools/install/probe</code> — check a hosted IPA is actually installable</li>
      <li><code>POST /api/tools/repo/export</code> — AltStore / flat / apps.json output</li>
      <li><code>POST /api/tools/repo/ota</code> — OTA manifest + <code>itms-services://</code> link</li>
      <li><code>POST /api/tools/cert/inspect</code> — parse an uploaded profile or public certificate</li>
      <li><code>GET /api/tools/cert/revoked-list</code> — the curated local revocation list</li>
      <li><code>GET /api/tools/udid/profile</code> — the enrolment <code>.mobileconfig</code></li>
      <li><code>POST /api/udid/callback</code> — where the device posts its UDID</li>
      <li><code>GET /api/tools/udid/session/{{token}}</code> — poll for the result</li>
    </ul>
  </div>
"""
    return page("VexSign Tools", body, request)
