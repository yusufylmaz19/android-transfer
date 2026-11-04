#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache"
swift build -c release --disable-sandbox
mkdir -p dist/AndroidTransfer.app/Contents/MacOS
cp .build/release/AndroidTransfer dist/AndroidTransfer.app/Contents/MacOS/AndroidTransfer
mkdir -p dist/AndroidTransfer.app/Contents/Resources
swift scripts/create-icon.swift .build/AndroidTransfer-icon-1024.png
python3 -c 'from PIL import Image; Image.open(".build/AndroidTransfer-icon-1024.png").save("dist/AndroidTransfer.app/Contents/Resources/AppIcon.icns")'
cat > dist/AndroidTransfer.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AndroidTransfer</string>
<key>CFBundleIdentifier</key><string>local.androidtransfer.mac</string>
<key>CFBundleName</key><string>Android Transfer</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSCameraUsageDescription</key><string>Telefonun bağlantı QR kodunu taramak için kamera kullanılır.</string>
<key>NSLocalNetworkUsageDescription</key><string>Telefonla yerel ağ üzerinden dosya aktarımı için bağlantı kurulur.</string>
</dict></plist>
PLIST
echo "Hazır: dist/AndroidTransfer.app"
