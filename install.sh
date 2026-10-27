#!/bin/zsh
# Rebuilds xd-loop in Release and installs it to /Applications, replacing the old copy.
# Run it from anywhere after making changes:  ~/Documents/xd-loop/install.sh
set -euo pipefail
cd "$(dirname "$0")"

# Use the full Xcode (the command line tools alone can't build the app or its shaders)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/Build/Products/Release/xd-loop.app"

echo "Building xd-loop…"
xcodebuild -project xd-loop.xcodeproj -scheme xd-loop -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$BUILD_DIR" build -quiet

# Quit the old copy if it's running, so it can be replaced
if pkill -x xd-loop 2>/dev/null; then sleep 1; fi

rm -rf /Applications/xd-loop.app
cp -R "$APP" /Applications/
echo "Installed /Applications/xd-loop.app. Open it from Spotlight, Launchpad or the Applications folder."
