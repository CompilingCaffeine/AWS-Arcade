#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <source_dir> <schema_file> <build_dir>" >&2
  exit 1
fi

SOURCE_DIR="$1"
SCHEMA_FILE="$2"
BUILD_DIR="$3"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

if command -v python3.13 >/dev/null 2>&1; then
  PYTHON=python3.13
elif command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
else
  echo "python3 is required to build the Lambda package" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

find "$SOURCE_DIR" -maxdepth 1 -type f -name "*.py" -exec cp {} "$BUILD_DIR/" \;
cp "$SCHEMA_FILE" "$BUILD_DIR/manifest.schema.json"

REQ_FILE="$SOURCE_DIR/requirements.txt"
if [[ -f "$REQ_FILE" ]] && grep -Eqv '^\s*(#|$)' "$REQ_FILE"; then
  "$PYTHON" -m pip install \
    --quiet \
    --disable-pip-version-check \
    --target "$BUILD_DIR" \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.13 \
    --implementation cp \
    -r "$REQ_FILE"
fi

find "$BUILD_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "$BUILD_DIR" -type d -name "tests" -path "*/site-packages/*" -prune -exec rm -rf {} + 2>/dev/null || true

echo "Built Lambda package at $BUILD_DIR"
