#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_FILE="$PROJECT_ROOT/PhrasePerch.xcodeproj"
BUILD_ROOT="$PROJECT_ROOT/.build"
APP_PATH="$BUILD_ROOT/Build/Products/Release/PhrasePerch.app"
STAGING_PATH="$BUILD_ROOT/dmg-staging"
DMG_PATH="$BUILD_ROOT/PhrasePerch.dmg"

if [[ ! -f "$PROJECT_FILE/project.pbxproj" ]]; then
    printf '未找到 PhrasePerch.xcodeproj：%s\n' "$PROJECT_FILE" >&2
    exit 1
fi

mkdir -p "$BUILD_ROOT"
printf '清理旧的项目构建产物……\n'
rm -rf \
    "$PROJECT_ROOT/build" \
    "$PROJECT_ROOT/DerivedData" \
    "$BUILD_ROOT/Build" \
    "$BUILD_ROOT/CompilationCache.noindex" \
    "$BUILD_ROOT/DerivedData" \
    "$BUILD_ROOT/Index.noindex" \
    "$BUILD_ROOT/Logs" \
    "$BUILD_ROOT/ModuleCache.noindex" \
    "$BUILD_ROOT/SDKExplicitPrecompiledModules" \
    "$BUILD_ROOT/SDKStatCaches.noindex" \
    "$BUILD_ROOT/SourcePackages" \
    "$BUILD_ROOT/TestResults" \
    "$BUILD_ROOT/dmg-staging" \
    "$BUILD_ROOT/packages" \
    "$BUILD_ROOT/previews" \
    "$BUILD_ROOT/release" \
    "$BUILD_ROOT"/ui-* \
    "$DMG_PATH"
rm -f "$BUILD_ROOT"/*.log

printf '构建 Release arm64 应用……\n'
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme PhrasePerch \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$BUILD_ROOT" \
    build

if [[ ! -d "$APP_PATH" ]]; then
    printf '构建完成但未找到应用：%s\n' "$APP_PATH" >&2
    exit 1
fi

mkdir -p "$STAGING_PATH"
ditto "$APP_PATH" "$STAGING_PATH/PhrasePerch.app"
ln -s /Applications "$STAGING_PATH/Applications"

printf '生成并校验 DMG……\n'
hdiutil create \
    -volname PhrasePerch \
    -srcfolder "$STAGING_PATH" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"
rm -rf "$STAGING_PATH"

printf '完成：%s\n' "$DMG_PATH"
