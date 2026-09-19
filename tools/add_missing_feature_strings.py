#!/usr/bin/env python3
"""Adds the user-facing strings of the newly implemented features to the String
Catalog so translators can pick them up.

They already work at runtime — `.localized()` is `NSLocalizedString`, which falls
back to the key itself — so this only makes them visible in Xcode's String
Catalog, exactly like `add_cleanup_and_explorer_strings.py`.

Covered features: PPQ/PPQLess + JIT, batch certificate check, App Cloner sheet,
direct (unsigned) install, App Store update tracking, IPSW browser, Minimal Mode,
Home Screen status widget and the Web Manager REST API.

The catalog is hand-maintained in Xcode's own, non-alphabetical order, so entries
are inserted right after `"strings" : {` instead of rewriting the file — its ~75k
lines stay byte-identical.

Run from the repository root:

    python3 tools/add_missing_feature_strings.py            # dry run
    python3 tools/add_missing_feature_strings.py --apply    # write
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "VexSign/Resources/Localizable.xcstrings"

# Files added or edited for these features. The list stays explicit so a later run
# does not silently sweep unrelated strings into the catalog.
SOURCES = [
    # PPQ / PPQLess detection and the JIT entitlement
    "VexSign/Utilities/CertificateReader/Models/Certificate+PPQ.swift",
    "VexSign/Utilities/Handlers/EntitlementBuilder.swift",
    "VexSign/Utilities/Handlers/SigningHandler.swift",
    "VexSign/Backend/Observable/PreflightChecks.swift",
    "VexSign/Views/Signing/Shared/SigningOptionsView.swift",
    "VexSign/Views/Settings/Certificates/CertificatesCellView.swift",
    "VexSign/Views/Settings/Certificates/Info/CertificatesInfoView.swift",
    # Batch certificate checker
    "VexSign/Backend/Observable/BatchCertChecker.swift",
    "VexSign/Views/Settings/Certificates/BatchCertCheckView.swift",
    "VexSign/Views/Settings/Certificates/CertificatesView.swift",
    # App Cloner
    "VexSign/Views/Library/AppCloneSheet.swift",
    "VexSign/Views/Library/LibraryCellView.swift",
    "VexSign/Views/Library/Info/LibraryInfoView.swift",
    # Install without signing
    "VexSign/Utilities/Handlers/DirectInstaller.swift",
    "VexSign/Views/Library/DirectInstallSheet.swift",
    "VexSign/Backend/Observable/AppInstaller.swift",
    # App Store update tracking
    "VexSign/Utilities/AppStoreTracker.swift",
    "VexSign/Views/Settings/Updates/UpdatesSettingsView.swift",
    # IPSW browser
    "VexSign/Utilities/IPSWBrowser.swift",
    "VexSign/Views/FileManager/IPSWBrowserView.swift",
    "VexSign/Views/FileManager/FileManagerView.swift",
    # Minimal UI mode
    "VexSign/Views/Settings/TabBarSettingsView.swift",
    # Home Screen status widget
    "VexSign/Backend/Observable/WidgetStatusPayload.swift",
    "VexSignWidgetExtension/VexSignStatusWidget.swift",
]

# Matches `.localized("Key")` and `.localized("Key", arguments: …)` — the arguments
# form carries its own string, which also belongs in the catalog.
LOCALIZED = re.compile(r'\.localized\(\s*"([^"\\]+)"')


def _entry(key: str) -> str:
    """One catalog entry, indented the way Xcode writes them."""
    return (
        f'    {json.dumps(key, ensure_ascii=False)} : {{\n'
        f'      "extractionState" : "manual",\n'
        f'      "localizations" : {{\n'
        f'        "en" : {{\n'
        f'          "stringUnit" : {{\n'
        f'            "state" : "translated",\n'
        f'            "value" : {json.dumps(key, ensure_ascii=False)}\n'
        f'          }}\n'
        f'        }}\n'
        f'      }}\n'
        f'    }},\n'
    )


def new_keys() -> list[str]:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    known = set(catalog["strings"])

    keys: list[str] = []
    for relative in SOURCES:
        path = ROOT / relative
        if not path.exists():
            print(f"skipped (missing): {relative}", file=sys.stderr)
            continue
        for match in LOCALIZED.finditer(path.read_text(encoding="utf-8")):
            key = match.group(1)
            if key not in known and key not in keys:
                keys.append(key)
    return keys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="write the catalog")
    args = parser.parse_args()

    keys = new_keys()
    if not keys:
        print("Catalog is already up to date.")
        return 0

    text = CATALOG.read_text(encoding="utf-8")
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        print(f"Catalog is not valid JSON: {error}", file=sys.stderr)
        return 1

    marker = '"strings" : {\n'
    index = text.index(marker) + len(marker)
    block = "".join(_entry(key) for key in keys)
    patched = text[:index] + block + text[index:]

    try:
        check = json.loads(patched)
    except json.JSONDecodeError as error:
        print(f"Refusing to write, result would not parse: {error}", file=sys.stderr)
        return 1

    if len(check["strings"]) != len(data["strings"]) + len(keys):
        print("Refusing to write, key count mismatch.", file=sys.stderr)
        return 1

    if not args.apply:
        print(f"Dry run: {len(keys)} new string(s) would be added.")
        for key in keys:
            print(f"  + {key}")
        return 0

    CATALOG.write_text(patched, encoding="utf-8")
    print(f"Added {len(keys)} string(s) to {CATALOG.relative_to(ROOT)}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
