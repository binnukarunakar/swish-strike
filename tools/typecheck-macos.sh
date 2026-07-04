#!/usr/bin/env bash
# typecheck-macos.sh — typecheck the iOS app's LOGIC TIER on a Mac WITHOUT
# Xcode. The listed files form one batch (a single swiftc invocation, so
# cross-file references resolve) compiled against the macOS SDK with the
# locally built SwishStrikeCore module. This tier holds the code where a wrong
# signature would corrupt counting: session orchestration, detection, camera
# plumbing, audio synthesis, coaching, persistence flags.
#
# The SwiftUI view files use iOS-only API (toolbars, UIKit bridges) and are
# deliberately NOT checked here — CI's iOS Simulator build covers them.
#
# This is a NET, not a proof: passing here does not guarantee the iOS build;
# failing here means the iOS build definitely fails.
set -uo pipefail
cd "$(dirname "$0")/.."

CORE=ios/SwishStrikeCore
APP=ios/SwishStrikeApp/SwishStrike

echo "── building SwishStrikeCore module (macOS) ──"
(cd "$CORE" && swift build) || { echo "SwishStrikeCore build failed"; exit 1; }
MODULES="$CORE/.build/arm64-apple-macosx/debug/Modules"
[ -d "$MODULES" ] || MODULES="$CORE/.build/debug/Modules"

LOGIC_TIER=(
  "$APP/Support/AppFlags.swift"
  "$APP/Support/GameStyling.swift"
  "$APP/DesignSystem/Color+Hex.swift"
  "$APP/DesignSystem/Theme.swift"
  "$APP/Engine/SetupCoach.swift"
  "$APP/Engine/GameSession.swift"
  "$APP/Camera/CameraManager.swift"
  "$APP/Vision/BallDetecting.swift"
  "$APP/Vision/TrajectoryBallDetector.swift"
  "$APP/Audio/Sfx.swift"
  "$APP/Haptics/Haptics.swift"
)

echo "── typechecking the logic tier (${#LOGIC_TIER[@]} files, one module batch) ──"
if swiftc -typecheck -swift-version 6 \
    -sdk "$(xcrun --show-sdk-path)" \
    -target arm64-apple-macos14.0 \
    -I "$MODULES" \
    "${LOGIC_TIER[@]}"; then
  echo "── typecheck OK: logic tier is signature-clean ──"
else
  echo "── typecheck FAILED (errors above are real iOS build breaks) ──"
  exit 1
fi
