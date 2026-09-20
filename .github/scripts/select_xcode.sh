#!/usr/bin/env bash
# Select an installed Xcode on a GitHub macOS runner.
#
#   REQUESTED_XCODE="26.3"  -> newest /Applications/Xcode_26.3*.app
#   REQUESTED_XCODE="16"    -> newest Xcode 16.x
#   REQUESTED_XCODE=""      -> newest Xcode installed on the image (GA builds
#                              are preferred over Release Candidates/betas)
#
# Why the default is "newest" and not Xcode 16: the project uses iOS 26 SDK
# API (`.glassEffect()` in NimbleKit), `SWIFT_APPROACHABLE_CONCURRENCY` and an
# iOS 26 deployment target for the widget extension, none of which exist in
# Xcode 16's SDKs. Pin a version with the BUILD_XCODE repository variable or
# the `xcode` input of the workflow if you ever need a specific toolchain.
#
# Outputs (GITHUB_OUTPUT): xcode_app, xcode_version
set -euo pipefail
shopt -s nullglob

requested="${REQUESTED_XCODE:-}"

if [ -n "${requested}" ]; then
  candidates=(/Applications/Xcode_"${requested}"*.app)
else
  candidates=(/Applications/Xcode_*.app)
fi

if [ "${#candidates[@]}" -eq 0 ]; then
  echo "::error::No Xcode matching '${requested:-*}' is installed on this runner."
  echo "Installed Xcodes:"
  ls -d /Applications/Xcode*.app 2>/dev/null || true
  exit 1
fi

# Build a sortable key per candidate: GA flag first, then the zero-padded
# version, so that a GA build always beats a Release Candidate/beta, "26.3"
# beats "26.2.1" and "16.4" beats "16". Pure bash - no reliance on `sort -V`.
best_key=""
best_app=""
for app in "${candidates[@]}"; do
  base="$(basename "${app}" .app)"      # Xcode_26.3 / Xcode_26.6_Release_Candidate_2 / Xcode_16
  ver="${base#Xcode_}"
  ga=1
  case "${ver}" in
    *[Bb]eta*|*Release_Candidate*|*RC*) ga=0 ;;
  esac
  ver="${ver%%_*}"                       # strip _Release_Candidate_2 and similar suffixes
  IFS='.' read -r major minor patch <<< "${ver}"
  key="$(printf '%d.%03d.%03d.%03d' "${ga}" "${major:-0}" "${minor:-0}" "${patch:-0}")"
  if [ -z "${best_key}" ] || [[ "${key}" > "${best_key}" ]]; then
    best_key="${key}"
    best_app="${app}"
  fi
done

echo "Selecting ${best_app}"
sudo xcode-select -s "${best_app}/Contents/Developer"
xcodebuild -version
echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"

version="$(xcodebuild -version | awk 'NR==1 {print $2}')"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "xcode_app=${best_app}"
    echo "xcode_version=${version}"
  } >> "${GITHUB_OUTPUT}"
fi
