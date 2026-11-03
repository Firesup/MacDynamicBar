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
mkdir -p "$app/Contents/MacOS"
cp .build/debug/MacDynamicBar "$app/Contents/MacOS/MacDynamicBar"
cp Support/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built %s\nLaunch with: open "%s"\n' "$app" "$app"
