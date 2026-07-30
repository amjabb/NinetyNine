#!/bin/bash
#
# Capture App Store screenshots by driving the real app in the Simulator.
#
# Usage:  Scripts/screenshots.sh ["iPhone 17 Pro"]
#
# Output: Artifacts/screenshots/*.png
#
set -euo pipefail

DEVICE="${1:-iPhone 17 Pro}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Artifacts/screenshots"
WORK="$ROOT/Artifacts/.screenshot-run"
STAGING="$WORK/staged"

# Capture into staging and only swap on success. An earlier version cleared the
# output folder up front, so a failed run destroyed the previous good set — with
# nothing to fall back to, because Artifacts/ is gitignored.
rm -rf "$WORK"
mkdir -p "$STAGING"

echo "==> Capturing on $DEVICE"
xcodebuild test \
  -project "$ROOT/NinetyNine.xcodeproj" \
  -scheme NinetyNine \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$WORK/dd" \
  -only-testing:NinetyNineUITests/ScreenshotTests \
  -resultBundlePath "$WORK/result.xcresult" \
  > "$WORK/xcodebuild.log" 2>&1 || {
    echo "Capture failed — previous screenshots in $OUT are untouched." >&2
    echo "Failure:" >&2
    grep -E "error:|XCTAssert" "$WORK/xcodebuild.log" | head -5 >&2
    exit 1
  }

echo "==> Extracting"
xcrun xcresulttool export attachments \
  --path "$WORK/result.xcresult" \
  --output-path "$WORK/attachments" > /dev/null

python3 - "$WORK/attachments" "$STAGING" <<'PY'
import json, os, re, shutil, sys

source, destination = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(source, "manifest.json")))

# xcresulttool appends "_<index>_<uuid>" to the name it suggests; strip it back
# to the plain label the test asked for.
SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.png$|$)")

count = 0
for entry in manifest:
    for attachment in entry.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or ""
        exported = attachment.get("exportedFileName")
        if not exported or not name.startswith("store-"):
            continue
        path = os.path.join(source, exported)
        if not os.path.exists(path):
            continue
        base = SUFFIX.sub("", name)
        if not base.endswith(".png"):
            base += ".png"
        shutil.copy(path, os.path.join(destination, base))
        count += 1
print(f"wrote {count} screenshots")
PY

# Only now is it safe to replace the previous set.
if [ -z "$(ls -A "$STAGING" 2>/dev/null)" ]; then
  echo "Capture produced no screenshots — leaving $OUT untouched." >&2
  exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"
mv "$STAGING"/* "$OUT"/
rm -rf "$WORK"
echo "==> Done: $OUT"
ls -1 "$OUT"
