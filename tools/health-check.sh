#!/usr/bin/env bash
# VexSign repository health check (Phase 0 deliverable).
#
# Reports repository/build/test indicators in one run. Indicators are for
# triage, not quality scores. Steps that need macOS/Xcode are skipped with a
# note on other platforms instead of failing the run.
#
#   tools/health-check.sh            # everything
#   tools/health-check.sh --quick    # skip dependency installation steps
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
QUICK="${1:-}"
PYVENV="server/.venv/bin/python"

section() { printf '\n== %s ==\n' "$1"; }

section "Git status"
git status --short --branch | head -20
echo "submodules:"
git submodule status | sed 's/^/  /'

section "Static gates (platform-independent)"
if command -v python3 >/dev/null; then
  python3 .github/scripts/quick_check.py --root . 2>/dev/null | tail -12
  python3 tools/check-pbxproj.py 2>/dev/null | tail -2
  if [ -x "$PYVENV" ]; then
    "$PYVENV" tools/check-swift-syntax.py >/dev/null 2>&1 \
      && echo "tree-sitter swift syntax: clean" \
      || echo "tree-sitter swift syntax: findings (advisory — CI swiftc -parse is authoritative)"
  else
    echo "tree-sitter swift syntax: skipped (no server/.venv)"
  fi
else
  echo "python3 not found — skipped"
fi

section "Swift build / tests (needs macOS + Xcode 26)"
if command -v xcodebuild >/dev/null; then
  echo "xcodebuild present — run:"
  echo "  xcodebuild -project VexSign.xcodeproj -scheme VexSign -configuration Debug build"
  echo "  xcodebuild test -project VexSign.xcodeproj -scheme VexSignTests -destination 'platform=iOS Simulator,name=iPhone 16'"
else
  echo "xcodebuild not found on this host — CI (build-check.yml / swift test job) is the oracle"
fi

section "Python backend tests"
if [ -x "$PYVENV" ]; then
  ( cd server && "$ROOT/$PYVENV" -m pytest tests/ -q 2>&1 | tail -3 )
elif [ "$QUICK" != "--quick" ] && command -v python3 >/dev/null; then
  echo "creating server/.venv and installing pinned deps…"
  ( cd server && python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt pytest ) \
    && ( cd server && .venv/bin/python -m pytest tests/ -q 2>&1 | tail -3 ) \
    || echo "venv setup failed"
else
  echo "server/.venv missing — run: cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt pytest"
fi

section "Cloud signing tests"
if command -v npm >/dev/null; then
  if [ ! -d cloud-signing/node_modules ] && [ "$QUICK" != "--quick" ]; then
    ( cd cloud-signing && npm ci --no-audit --no-fund >/dev/null ) || echo "npm ci failed"
  fi
  if [ -d cloud-signing/node_modules ]; then
    ( cd cloud-signing && npm run check --silent && echo "tsc --noEmit: clean" )
    ( cd cloud-signing && npm test --silent 2>&1 | grep -E '^# (tests|pass|fail)' )
  else
    echo "cloud-signing/node_modules missing — run: cd cloud-signing && npm ci"
  fi
else
  echo "npm not found — skipped"
fi

section "Code indicators (indicators, not scores)"
app_sources() { find VexSign AltSourceKit NimbleKit VexSignWidgetExtension VexSignWatch VexSignWatchWidgets VexSignTV VexSignVision VexSignTests -name '*.swift' 2>/dev/null; }
echo "swift files:            $(app_sources | wc -l)"
echo "force unwraps (approx): $(app_sources | xargs grep -hoE '\w+![^=]' 2>/dev/null | wc -l)"
echo "try!:                   $(app_sources | xargs grep -l 'try!' 2>/dev/null | wc -l) files"
echo "as!:                    $(app_sources | xargs grep -l ' as! ' 2>/dev/null | wc -l) files"
echo "fatalError:             $(app_sources | xargs grep -h 'fatalError' 2>/dev/null | wc -l)"
echo "Task.detached:          $(app_sources | xargs grep -h 'Task.detached' 2>/dev/null | wc -l)"
echo "DispatchQueue.main:     $(app_sources | xargs grep -h 'DispatchQueue.main' 2>/dev/null | wc -l)"
echo "TODO/FIXME:             $(app_sources | xargs grep -hE 'TODO|FIXME' 2>/dev/null | wc -l)"
echo "swift test methods:     $(find VexSignTests -name '*.swift' | xargs grep -c 'func test' | awk -F: '{s+=$2} END {print s}')"
echo "largest files:"
app_sources | xargs wc -l 2>/dev/null | sort -rn | sed -n '2,8p' | sed 's/^/  /'

section "Dependency status"
echo "SwiftPM pins: $(python3 -c "import json;print(len(json.load(open('VexSign.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'))['pins']))" 2>/dev/null || echo '?')"
echo "python pins:  $(grep -c '==' server/requirements.txt)"
echo "npm outdated: run 'cd cloud-signing && npm outdated' when needed"

section "Done"
echo "Health check finished. Interpret counts as trends, never as pass/fail."
