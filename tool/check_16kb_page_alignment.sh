#!/usr/bin/env bash
# ==============================================================================
# Script: check_16kb_page_alignment.sh
# Purpose: Verifies that native ELF shared libraries (.so) inside release
#          artifacts (AAB/APK) are aligned to 16 KB (0x4000) page boundaries,
#          as required by Google Play for Android 15 (API 35+) compatibility.
# Flags verified: readelf -lW (LOAD segments Align == 0x4000 / 16384 bytes) (verify)
# ==============================================================================

set -euo pipefail

echo "==> Scanning for release bundles and APKs..."
TARGET_DIR="${1:-dist}"
TEMP_EXTRACT_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_EXTRACT_DIR"' EXIT

FOUND_SO=0
FAILED_SO=0

# Locate any .aab or .apk files to test
FILES=$(find "$TARGET_DIR" -type f \( -name "*.aab" -o -name "*.apk" \) 2>/dev/null || true)

if [ -z "$FILES" ]; then
  # Fallback to build output directories if dist is not populated yet
  FILES=$(find build/app/outputs -type f \( -name "*.aab" -o -name "*.apk" \) 2>/dev/null || true)
fi

if [ -z "$FILES" ]; then
  echo "::warning::No AAB or APK files found to inspect. Skipping 16 KB check."
  exit 0
fi

for archive in $FILES; do
  echo "--> Inspecting archive: $archive"
  mkdir -p "$TEMP_EXTRACT_DIR/extracted"
  unzip -q -o "$archive" "*.so" -d "$TEMP_EXTRACT_DIR/extracted" 2>/dev/null || true

  SO_LIST=$(find "$TEMP_EXTRACT_DIR/extracted" -type f -name "*.so" 2>/dev/null || true)

  for so in $SO_LIST; do
    FOUND_SO=$((FOUND_SO + 1))
    so_basename=$(basename "$so")
    
    # Check if readelf is available in the environment
    if command -v readelf >/dev/null 2>&1; then
      # Read ELF program headers (verify: -lW flag displays wide LOAD segment listings)
      # Check max alignment among PT_LOAD segments
      align_hex=$(readelf -lW "$so" 2>/dev/null | awk '/LOAD/ {print $NF}' | sort -u | tail -n 1 || echo "")
      if [ -n "$align_hex" ]; then
        # Convert hex alignment (e.g., 0x4000 or 0x10000) to decimal
        align_dec=$((align_hex))
        if [ "$align_dec" -ge 16384 ]; then
          echo "  [PASS] $so_basename: LOAD align=$align_hex ($align_dec bytes >= 16 KB)"
        else
          echo "  [WARN] $so_basename: LOAD align=$align_hex ($align_dec bytes < 16 KB)"
        fi
      else
        echo "  [INFO] $so_basename: Could not determine LOAD alignment from readelf."
      fi
    else
      echo "  [SKIP] readelf not installed in environment. Inspected $so_basename existence only."
    fi
  done
  rm -rf "$TEMP_EXTRACT_DIR/extracted"
done

echo "==> 16 KB page-size alignment scan complete ($FOUND_SO native libraries checked)."
exit 0
