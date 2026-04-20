#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.0.6"
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/builds/${VERSION}"
APP_DIR="${BUILD_DIR}/Gridded"
OUTPUT_DMG="${BUILD_DIR}/Gridded.dmg"
BACKGROUND_IMAGE="${ROOT_DIR}/background.jpg"
BACKGROUND_IMAGE_PNG="${BUILD_DIR}/.dmg-background.png"
APP_BUNDLE_NAME="Gridded.app"

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Error: create-dmg is not installed."
  echo "Install with: brew install create-dmg"
  exit 1
fi

if [[ ! -d "${BUILD_DIR}" ]]; then
  echo "Error: build directory not found: ${BUILD_DIR}"
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "Error: app directory not found: ${APP_DIR}"
  echo "Expected to contain Gridded.app"
  exit 1
fi

if [[ ! -f "${BACKGROUND_IMAGE}" ]]; then
  echo "Error: background image not found: ${BACKGROUND_IMAGE}"
  exit 1
fi

if [[ ! -d "${APP_DIR}/${APP_BUNDLE_NAME}" ]]; then
  echo "Error: app bundle not found: ${APP_DIR}/${APP_BUNDLE_NAME}"
  exit 1
fi

rm -f "${OUTPUT_DMG}"
rm -f "${BACKGROUND_IMAGE_PNG}"

if ! command -v sips >/dev/null 2>&1; then
  echo "Error: sips command is required to convert background image."
  exit 1
fi

sips -s format png "${BACKGROUND_IMAGE}" --out "${BACKGROUND_IMAGE_PNG}" >/dev/null

create-dmg \
  --volname "Gridded" \
  --background "${BACKGROUND_IMAGE_PNG}" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 110 \
  --icon "${APP_BUNDLE_NAME}" 170 200 \
  --hide-extension "${APP_BUNDLE_NAME}" \
  --app-drop-link 430 200 \
  --no-internet-enable \
  "${OUTPUT_DMG}" \
  "${APP_DIR}"

echo "Created: ${OUTPUT_DMG}"
