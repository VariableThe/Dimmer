#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

# Keep Clang's module cache inside the workspace. This also works in
# sandboxed developer environments where the default user cache is read-only.
export CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-module-cache"
swift build --disable-sandbox -c release
binary_dir="$(swift build --disable-sandbox -c release --show-bin-path)"
app_path="$project_root/build/Dimmer.app"

mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/Dimmer" "$app_path/Contents/MacOS/Dimmer"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"

# An ad-hoc signature lets macOS associate Screen Recording consent with this
# local bundle. Release distribution should replace this with a Developer ID
# signature and notarization.
codesign --force --sign - "$app_path"

echo "Built $app_path"
