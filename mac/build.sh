#!/bin/bash
# build/Hanyoung.app 을 만든다. 처음이면 데이터부터 받는다.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f data/raw/ko_50k.txt ]] || scripts/download_data.sh
python3 src/export_model.py build/model.json

APP=build/Hanyoung.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/Hanyoung" mac/*.swift -framework Cocoa -framework Carbon
cp build/model.json "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.hanyoung.app</string>
  <key>CFBundleName</key><string>Hanyoung</string>
  <key>CFBundleExecutable</key><string>Hanyoung</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "✓ $APP"
