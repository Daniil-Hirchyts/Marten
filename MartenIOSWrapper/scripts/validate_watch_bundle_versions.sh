#!/usr/bin/env bash

set -euo pipefail

PROJECT_PATH="${1:-MartenIOSWrapper/MartenIOSWrapper.xcodeproj}"
IOS_TARGET="${2:-Marten}"
WATCH_APP_TARGET="${3:-MartenWatchApp}"
WATCH_EXTENSION_TARGET="${4:-MartenWatchExtension}"

extract_build_number() {
  local target="$1"
  xcodebuild -project "$PROJECT_PATH" -target "$target" -showBuildSettings 2>/dev/null \
    | awk '/CURRENT_PROJECT_VERSION = / { print $3; exit }'
}

ios_build="$(extract_build_number "$IOS_TARGET")"
watch_app_build="$(extract_build_number "$WATCH_APP_TARGET")"
watch_extension_build="$(extract_build_number "$WATCH_EXTENSION_TARGET")"

if [[ -z "$ios_build" || -z "$watch_app_build" || -z "$watch_extension_build" ]]; then
  echo "Failed to resolve CURRENT_PROJECT_VERSION for one or more targets." >&2
  exit 1
fi

if [[ "$ios_build" != "$watch_app_build" ]]; then
  echo "CFBundleVersion mismatch: $IOS_TARGET=$ios_build, $WATCH_APP_TARGET=$watch_app_build" >&2
  exit 1
fi

if [[ "$watch_app_build" != "$watch_extension_build" ]]; then
  echo "CFBundleVersion mismatch: $WATCH_APP_TARGET=$watch_app_build, $WATCH_EXTENSION_TARGET=$watch_extension_build" >&2
  exit 1
fi

echo "Bundle versions aligned: iOS/watchApp/watchExtension = $ios_build"
