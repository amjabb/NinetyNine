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
# Each device size gets its own folder — App Store Connect has a separate slot
# per display size, and capturing a second size must not destroy the first.
SLUG="$(echo "$DEVICE" | tr '[:upper:] ' '[:lower:]-')"
OUT="$ROOT/Artifacts/screenshots/$SLUG"
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
#
# The bar is the *full* set, not a non-empty one. An earlier version checked
# only that something had been produced, so a run that captured nine of ten —
# which the test suite then reported as a pass — quietly replaced a complete set
# of App Store screenshots with an incomplete one.
EXPECTED=10
ACTUAL="$(ls -1 "$STAGING"/*.png 2>/dev/null | wc -l | tr -d ' ')"
if [ "$ACTUAL" -lt "$EXPECTED" ]; then
  echo "Capture produced $ACTUAL of $EXPECTED screenshots — leaving $OUT untouched." >&2
  echo "Missing:" >&2
  for n in 1 2 3 4 5 6 7 8 9 10; do
    ls "$STAGING"/store-$n-*.png > /dev/null 2>&1 || echo "  store-$n-*" >&2
  done
  exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"
mv "$STAGING"/* "$OUT"/
rm -rf "$WORK"
echo "==> Done: $OUT"
ls -1 "$OUT"
echo
echo "Dimensions: $(sips -g pixelWidth -g pixelHeight "$OUT"/store-1-home.png 2>/dev/null | awk '/pixel/{printf "%s ", $2}')"
