#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/simvoya-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/simvoya-module-cache"
swift build -c release --disable-sandbox --cache-path "${TMPDIR:-/tmp}/simvoya-swift-cache"
BINARY_DIR="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "${TMPDIR:-/tmp}/simvoya-swift-cache")"
APP="dist/SimVoya.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/AppIcon.iconset
cp "$BINARY_DIR/SimVoya" "$APP/Contents/MacOS/SimVoya"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Assets/AppIcon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.charles.simvoya</string>
<key>CFBundleName</key><string>SimVoya</string>
<key>CFBundleDisplayName</key><string>SimVoya</string>
<key>CFBundleExecutable</key><string>SimVoya</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
print "Built: $PWD/$APP"
