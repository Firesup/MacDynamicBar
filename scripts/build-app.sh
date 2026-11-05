#!/bin/zsh
set -eu
cd "${0:A:h:h}"

# Keep compiler caches alongside the build so restricted workspaces work too.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" \
    --config-path "$PWD/.build/package-config" \
    --security-path "$PWD/.build/package-security" \
    -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"

app="$PWD/.build/Minnow.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -framework AppKit \
    scripts/generate-icon.swift -o "$PWD/.build/generate-icon"
"$PWD/.build/generate-icon" "$PWD/.build/Minnow.iconset"
iconutil -c icns "$PWD/.build/Minnow.iconset" -o "$app/Contents/Resources/Minnow.icns"
cp .build/debug/MacDynamicBar "$app/Contents/MacOS/MacDynamicBar"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
# A persistent signing certificate keeps TCC permission identity across rebuilds.
# The default ad-hoc identity changes with the executable and may need reauthorization.
signing_identity="${MINNOW_SIGN_IDENTITY:--}"
codesign --force --sign "$signing_identity" "$app"
printf 'Built %s\nLaunch with: open "%s"\n' "$app" "$app"
