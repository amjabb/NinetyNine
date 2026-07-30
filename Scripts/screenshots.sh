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

rm -rf "$WORK" "$OUT"
mkdir -p "$OUT" "$WORK"

echo "==> Capturing on $DEVICE"
xcodebuild test \
  -project "$ROOT/NinetyNine.xcodeproj" \
  -scheme NinetyNine \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$WORK/dd" \
  -only-testing:NinetyNineUITests/ScreenshotTests \
  -resultBundlePath "$WORK/result.xcresult" \
  > "$WORK/xcodebuild.log" 2>&1 || {
    echo "Capture failed. Tail of log:" >&2
    tail -30 "$WORK/xcodebuild.log" >&2
    exit 1
  }

echo "==> Extracting"
xcrun xcresulttool export attachments \
  --path "$WORK/result.xcresult" \
  --output-path "$WORK/attachments" > /dev/null

python3 - "$WORK/attachments" "$OUT" <<'PY'
import json, os, shutil, sys

source, destination = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(source, "manifest.json")))
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
        # Strip the uuid suffix xcresulttool appends.
        base = name if name.endswith(".png") else name + ".png"
        shutil.copy(path, os.path.join(destination, base))
        count += 1
print(f"wrote {count} screenshots")
PY

rm -rf "$WORK"
echo "==> Done: $OUT"
ls -1 "$OUT"
