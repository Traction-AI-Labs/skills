#!/usr/bin/env bash
# Builds the upload zip for the Claude app (Customize, Skills, upload), named for sharing.
# The zip is a delivery artefact: regenerate it from skills/, never commit it.
# Run: bash scripts/build-zip.sh [out-dir]   (default: ./dist)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HERE/dist}"
mkdir -p "$OUT"
zipfile="$OUT/Call prep by Traction Studio.zip"
rm -f "$zipfile"
(cd "$HERE/skills" && zip -qrX "$zipfile" "call-prep")
echo "$zipfile"
