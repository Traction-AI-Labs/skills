#!/usr/bin/env bash
# Builds the upload zip for the Claude app (Customize, Skills, upload) for one plugin, named for sharing.
# The zip is a delivery artefact: regenerate it from plugins/<name>/skills/, never commit it.
# Run, from anywhere: bash scripts/build-zip.sh <plugin-name> [out-dir]   (default out-dir: plugins/<plugin-name>/dist)
set -euo pipefail
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: bash scripts/build-zip.sh <plugin-name> [out-dir]" >&2
  exit 2
fi
NAME="$1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HERE="$REPO/plugins/$NAME"
if [ ! -d "$HERE/skills/$NAME" ]; then
  echo "no skill folder at plugins/$NAME/skills/$NAME; pass a plugin name such as ruling-page" >&2
  exit 2
fi
OUT="${2:-$HERE/dist}"
mkdir -p "$OUT"
# "ruling-page" becomes "Ruling page by Traction Studio.zip"
words="${NAME//-/ }"
first="$(printf '%s' "${words:0:1}" | tr '[:lower:]' '[:upper:]')"
zipfile="$OUT/${first}${words:1} by Traction Studio.zip"
rm -f "${zipfile:?}"
(cd "$HERE/skills" && zip -qrX "$zipfile" "$NAME" -x "*/__pycache__/*" "*.pyc" "*/.pytest_cache/*")
echo "$zipfile"
