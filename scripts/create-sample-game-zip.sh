#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="/tmp/sample-game.zip"

rm -f "${OUTPUT}"
cd "${ROOT_DIR}/examples/sample-game"
zip -r "${OUTPUT}" .

echo "Created ${OUTPUT}"

