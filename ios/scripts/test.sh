#!/usr/bin/env bash
# Real Swift Testing run of every pure-logic test, without Xcode.
#
# Mac Catalyst is not needed here: the pure layer (protocol codec, reassembler,
# ToF algorithm, bottle profiles, reminder rules, allowlist, health sync
# planning, battery policy, device name, background policy, URL routes) imports
# nothing but Foundation, so it compiles into a plain macOS test binary that
# links the Swift Testing library that ships with the Command Line Tools.
#
# Usage:  ios/scripts/test.sh          (from the repo root or anywhere)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS="$ROOT/ios"
APP="$IOS/HydroCap"
TESTS="$IOS/HydroCapTests"
SDK="$(xcrun --show-sdk-path)"

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIBS="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
TESTING_MACROS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

for required in "$CLT_FRAMEWORKS/Testing.framework" "$TESTING_MACROS"; do
  if [[ ! -e "$required" ]]; then
    echo "missing Swift Testing component: $required" >&2
    exit 1
  fi
done

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hydrocap-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The pure-logic sources, exactly the files the tests touch.
PURE_FILES=(
  "Protocol/Hex.swift"
  "Protocol/ProtoWire.swift"
  "Protocol/Messages.swift"
  "Protocol/CapCommand.swift"
  "Protocol/CapCodec.swift"
  "Domain/DeviceName.swift"
  "Domain/BottleProfile.swift"
  "Domain/TofAlgorithm.swift"
  "Domain/ReminderConfig.swift"
  "Domain/HydrationTarget.swift"
  "Domain/HistoryAggregation.swift"
  "Notify/DrinkReminderPlanner.swift"
  "Notify/DrinkReminderQueue.swift"
  "Sync/ConnectionHandoff.swift"
  "Sync/ReminderMapping.swift"
  "Sync/SyncErrors.swift"
  "Sync/BackgroundRunPolicy.swift"
  "Data/Records.swift"
  "Data/Settings.swift"
  "Data/Stores.swift"
  "Health/HydrationRecordSync.swift"
  "Notify/BatteryAlertPolicy.swift"
  "Debug/DebugLog.swift"
  "Debug/DebugRoute.swift"
  "BLE/AsyncWaiter.swift"
  "BLE/RequestIdCounter.swift"
  "BLE/NotificationReassembler.swift"
  "BLE/NusChannel.swift"
  "BLE/DiscoveredCap.swift"
)

SOURCES=()
for file in "${PURE_FILES[@]}"; do
  SOURCES+=("$APP/$file")
done

# Every test file, with `@testable import HydroCap` removed: everything is
# compiled into one module *named* HydroCap, so the import would be a self-import.
for file in "$TESTS"/*.swift; do
  name="$(basename "$file")"
  sed -e '/^@testable import HydroCap$/d' "$file" > "$TMP/$name"
  SOURCES+=("$TMP/$name")
done

# Swift Testing entry point (top-level code is rejected with -parse-as-library).
cat > "$TMP/Runner.swift" <<'SWIFT'
import Foundation
import Testing

@main
struct HydroCapTestRunner {
    static func main() async {
        let code = await Testing.__swiftPMEntryPoint() as CInt
        exit(code)
    }
}
SWIFT
SOURCES+=("$TMP/Runner.swift")

echo "hydrocap tests: ${#SOURCES[@]} source files (pure logic + tests + runner)"

xcrun swiftc \
  -sdk "$SDK" \
  -swift-version 5 \
  -module-name HydroCap \
  -parse-as-library \
  -load-plugin-library "$TESTING_MACROS" \
  -F "$CLT_FRAMEWORKS" -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
  -L "$CLT_LIBS" -Xlinker -rpath -Xlinker "$CLT_LIBS" \
  -framework Testing \
  "${SOURCES[@]}" \
  -o "$TMP/hydrocap-tests"

"$TMP/hydrocap-tests"
