#!/bin/zsh
# Build, install, and launch WriteRight on the iPad with hot reload wired up.
#
# Hot reload needs two things the plain SweetPad launch can't provide:
#   INJECTION_HOST         — direct TCP to the InjectionNext Mac app
#                            (multicast discovery is unreliable here)
#   INJECTION_PROJECT_ROOT — makes the server auto-watch this repo for saves
# Run the InjectionNext.app menu-bar app first; then use this script instead
# of SweetPad ▶ whenever you want hot reload for the session.
set -e -o pipefail

DEVICE="${DEVICE:-EAF83A6D-1C63-5AA7-BFEA-18F3240ED0AC}"   # iPad Air 13" (M3)
BUNDLE_ID=com.milesfritzmather.writeright
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC_IP="$(ipconfig getifaddr en0)"

echo "▸ building for device…"
xcodebuild -project "$ROOT/WriteRight.xcodeproj" -scheme WriteRight \
    -destination "platform=iOS,id=$DEVICE" build | xcbeautify --quiet

APP_DIR="$(xcodebuild -project "$ROOT/WriteRight.xcodeproj" -scheme WriteRight \
    -destination "platform=iOS,id=$DEVICE" -showBuildSettings 2>/dev/null |
    awk '/TARGET_BUILD_DIR =/ {dir=$3} /WRAPPER_NAME =/ {name=$3} END {print dir "/" name}')"

echo "▸ installing $APP_DIR…"
xcrun devicectl device install app --device "$DEVICE" "$APP_DIR"

echo "▸ launching with hot reload (Mac: $MAC_IP)…"
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
    --environment-variables "{\"INJECTION_HOST\": \"$MAC_IP\", \"INJECTION_PROJECT_ROOT\": \"$ROOT\"}" \
    "$BUNDLE_ID"
echo "✓ running — save a Swift file and watch it update live"
