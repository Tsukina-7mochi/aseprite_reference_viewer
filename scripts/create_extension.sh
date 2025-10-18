#!/bin/bash
cd "$(dirname "$0")/../"
set -euo pipefail

DEST_DIR="./build"
PACKAGE_JSON="./package.json"

PACKAGE="$(cat "$PACKAGE_JSON")"
EXT_NAME=$(echo "$PACKAGE" | jq -r '.name + "-v" + .version')

mkdir -p "$DEST_DIR"

zip -r -j "$DEST_DIR/$EXT_NAME.zip" "$PACKAGE_JSON" ./src/*.lua
mv "$DEST_DIR/$EXT_NAME.zip" "$DEST_DIR/$EXT_NAME.aseprite-extension"
