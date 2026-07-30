#!/bin/bash
#
# Build a Release archive ready for App Store distribution.
#
# Usage:
#   Scripts/archive.sh                 # archive only (no signing needed)
#   Scripts/archive.sh --export TEAMID # archive and export a signed .ipa
#
# Without a team id this archives unsigned, which is enough to prove the Release
# configuration builds clean. Exporting an uploadable .ipa requires your Apple
# Developer team.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVE="$ROOT/Artifacts/NinetyNine.xcarchive"
EXPORT_DIR="$ROOT/Artifacts/export"

mkdir -p "$ROOT/Artifacts"
rm -rf "$ARCHIVE"

EXPORT=false
TEAM_ID=""
if [[ "${1:-}" == "--export" ]]; then
  EXPORT=true
  TEAM_ID="${2:?--export requires a team id}"
fi

echo "==> Archiving (Release)"
if $EXPORT; then
  xcodebuild archive \
    -project "$ROOT/NinetyNine.xcodeproj" \
    -scheme NinetyNine \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM_ID"
else
  # Unsigned: verifies the Release build without needing a developer account.
  xcodebuild archive \
    -project "$ROOT/NinetyNine.xcodeproj" \
    -scheme NinetyNine \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""
fi

echo "==> Archive at $ARCHIVE"

if $EXPORT; then
  rm -rf "$EXPORT_DIR"
  cat > "$ROOT/Artifacts/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF
  echo "==> Exporting .ipa"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$ROOT/Artifacts/ExportOptions.plist"
  echo "==> Exported to $EXPORT_DIR"
  echo "    Upload with Transporter, or Xcode > Organizer > Distribute App."
else
  echo
  echo "Archived unsigned — the Release configuration builds clean."
  echo "To produce an uploadable build:  Scripts/archive.sh --export <YOUR_TEAM_ID>"
fi
