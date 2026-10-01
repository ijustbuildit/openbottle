#!/usr/bin/env bash
# Typecheck every app source as Mac Catalyst against the iOS-support
# frameworks — the closest thing to an Xcode build that a Mac with only the
# Command Line Tools can do. Bar: 0 errors, 0 warnings.
#
#   * same target triple as an iOS app on Apple silicon (arm64-apple-ios*-macabi);
#     the iOS 26.0 floor matches `deploymentTarget` in ios/project.yml (Liquid
#     Glass APIs are @available(iOS 26.0, *))
#   * same language mode and concurrency settings as ios/project.yml
#   * `#Preview` blocks are stripped in a temp copy (the PreviewsMacros plugin
#     ships only with Xcode) — never in the repo
#   * `-D HYDROCAP_TYPE_CHECK` skips the SwiftData `@Model` layer, whose macro
#     plugin likewise ships only with Xcode; that file additionally gets a
#     parse-only pass so at least its syntax is covered
#
# Usage:  ios/scripts/typecheck.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS="$ROOT/ios"
APP="$IOS/HydroCap"
SDK="$(xcrun --show-sdk-path)"
IOS_SUPPORT="$SDK/System/iOSSupport"
TARGET="arm64-apple-ios26.0-macabi"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hydrocap-typecheck.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/sources"

python3 - "$APP" "$TMP/sources" "$TMP/count.txt" <<'PY'
"""Copy the app sources into a temp dir, stripping `#Preview { ... }` blocks."""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "#Preview"


def strip_previews(text: str) -> str:
    out = []
    index = 0
    while True:
        found = text.find(MARKER, index)
        if found < 0:
            out.append(text[index:])
            break
        out.append(text[index:found])
        brace = text.find("{", found)
        if brace < 0:
            out.append(text[found:])
            break
        depth = 0
        cursor = brace
        while cursor < len(text):
            character = text[cursor]
            if character == "{":
                depth += 1
            elif character == "}":
                depth -= 1
                if depth == 0:
                    cursor += 1
                    break
            cursor += 1
        index = cursor
    return "".join(out)


app = Path(sys.argv[1])
destination = Path(sys.argv[2])
count = 0
for source in sorted(app.rglob("*.swift")):
    relative = source.relative_to(app)
    name = "__".join(relative.parts)
    text = strip_previews(source.read_text())
    (destination / name).write_text(text)
    count += 1
Path(sys.argv[3]).write_text(str(count))
print(f"copied {count} app sources")
PY

FILES=("$TMP"/sources/*.swift)

set +e
xcrun swiftc -typecheck \
  -target "$TARGET" \
  -sdk "$SDK" \
  -Fsystem "$IOS_SUPPORT/System/Library/Frameworks" \
  -I "$IOS_SUPPORT/usr/lib/swift" \
  -L "$IOS_SUPPORT/usr/lib/swift" \
  -parse-as-library \
  -swift-version 5 \
  -default-isolation MainActor \
  -enable-upcoming-feature StrictConcurrency \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -D HYDROCAP_TYPE_CHECK \
  -module-name HydroCap \
  "${FILES[@]}" \
  > "$TMP/output.txt" 2>&1
STATUS=$?
set -e

# The SwiftData file, parsed without macro expansion (its plugin is Xcode-only).
set +e
xcrun swiftc -frontend -parse \
  -target "$TARGET" \
  -sdk "$SDK" \
  -Fsystem "$IOS_SUPPORT/System/Library/Frameworks" \
  -I "$IOS_SUPPORT/usr/lib/swift" \
  "$APP/Data/SwiftDataModels.swift" \
  > "$TMP/parse.txt" 2>&1
PARSE_STATUS=$?
set -e

python3 - "$TMP/output.txt" "$TMP/parse.txt" "$TMP/count.txt" <<'PY'
import sys
from pathlib import Path

typecheck_output = Path(sys.argv[1]).read_text()
parse_output = Path(sys.argv[2]).read_text()
file_count = Path(sys.argv[3]).read_text().strip()
lines = [
    line
    for line in typecheck_output.splitlines()
    if ": error:" in line or ": warning:" in line or line.startswith("error:")
]
for line in lines:
    print(line)
errors = sum(": error:" in line or line.startswith("error:") for line in lines)
warnings = sum(": warning:" in line for line in lines)
parse_errors = sum(": error:" in line or line.startswith("error:") for line in parse_output.splitlines())
print(
    f"typecheck files={file_count} errors={errors} warnings={warnings} "
    f"swiftdata_parse_errors={parse_errors}"
)
PY

rm -rf "$TMP/sources"
if [[ $STATUS -ne 0 || $PARSE_STATUS -ne 0 ]]; then
  # Show raw compiler output when the summary filter found nothing to print.
  if ! grep -qE ": (error|warning):" "$TMP/output.txt"; then
    cat "$TMP/output.txt" | head -40
  fi
  if [[ $PARSE_STATUS -ne 0 ]]; then
    cat "$TMP/parse.txt" | head -20
  fi
  exit 1
fi
