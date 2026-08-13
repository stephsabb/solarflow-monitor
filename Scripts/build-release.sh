#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
app="$project_dir/outputs/SolarFlow Monitor.app"
cd "$project_dir"
CLANG_MODULE_CACHE_PATH="$project_dir/work/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/work/clang-cache" swift build --disable-sandbox -c release
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp .build/release/SolarFlowMonitor "$app/Contents/MacOS/SolarFlowMonitor"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/SolarFlowMonitor" 2>/dev/null || true
cp work/Info.plist "$app/Contents/Info.plist"
cp work/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp work/EnergyFlowHouseLight.png "$app/Contents/Resources/EnergyFlowHouseLight.png"
cp work/EnergyFlowHouseDark.png "$app/Contents/Resources/EnergyFlowHouseDark.png"
ditto .build/release/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
identity="${DEVELOPER_ID_APPLICATION:-}"
if [[ -n "$identity" ]]; then
  codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework"
  codesign --force --deep --options runtime --timestamp --sign "$identity" "$app"
else
  codesign --force --deep --sign - "$app"
fi
archive="$project_dir/outputs/SolarFlow-Monitor-App.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
codesign --verify --deep --strict --verbose=2 "$app"
echo "$archive"
