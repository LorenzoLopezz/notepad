#!/bin/zsh
set -euo pipefail

APP_NAME="Notepad"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

swiftc \
  -O \
  -sdk "$SDK_PATH" \
  -target "$(uname -m)-apple-macosx13.0" \
  -framework SwiftUI \
  -framework AppKit \
  "$ROOT_DIR/NotepadApp.swift" \
  "$ROOT_DIR/ContentView.swift" \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Listo: $APP_DIR"
