#!/usr/bin/env bash
# compress_dataset.sh
# Batch-compress a deepfake dataset with JPEG AI at multiple BPP levels.
#
# Usage (inside jpeg_ai_vm conda env):
#   bash scripts/compress_dataset.sh <DATASET_DIR> <OUTPUT_DIR> [JPEGAI_ROOT]
#
# Args:
#   DATASET_DIR   Root folder of original images (recursively searched for PNG/JPG).
#   OUTPUT_DIR    Where compressed images are written. Created if absent.
#   JPEGAI_ROOT   Path to cloned jpeg-ai-reference-software repo.
#                 Default: ../jpeg-ai-reference-software (sibling of this repo).
#
# Example:
#   conda activate jpeg_ai_vm
#   bash scripts/compress_dataset.sh data/original data/compressed
#
# Output layout:
#   OUTPUT_DIR/
#     bpp_010/    (0.10 BPP)
#     bpp_030/    (0.30 BPP)
#     bpp_050/    (0.50 BPP)
#     bpp_080/    (0.80 BPP)
#     bpp_100/    (1.00 BPP)
#     bpp_200/    (2.00 BPP)

set -euo pipefail

DATASET_DIR="${1:?Usage: $0 <DATASET_DIR> <OUTPUT_DIR> [JPEGAI_ROOT]}"
OUTPUT_DIR="${2:?Usage: $0 <DATASET_DIR> <OUTPUT_DIR> [JPEGAI_ROOT]}"
JPEGAI_ROOT="${3:-../jpeg-ai-reference-software}"
PROFILE="base"

# BPP levels × 100 (JPEG AI CLI expects integer)
BPP_VALUES=(10 30 50 80 100 200)

if [[ ! -d "$JPEGAI_ROOT" ]]; then
    echo "ERROR: JPEG AI repo not found at $JPEGAI_ROOT"
    echo "Clone it: git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git"
    exit 1
fi

# Collect all images
mapfile -d '' IMAGES < <(find "$DATASET_DIR" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -print0)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "ERROR: No images found in $DATASET_DIR"
    exit 1
fi

echo "Found ${#IMAGES[@]} images in $DATASET_DIR"
echo "Output -> $OUTPUT_DIR"
echo "Profile: $PROFILE"
echo "BPP levels: ${BPP_VALUES[*]}"
echo "=========================================="

for BPP_X100 in "${BPP_VALUES[@]}"; do
    BPP_TAG="bpp_$(printf '%03d' "$BPP_X100")"
    BPP_DIR="$OUTPUT_DIR/$BPP_TAG"
    mkdir -p "$BPP_DIR"

    echo ""
    echo "--- Compressing at BPP=$BPP_X100/100 -> $BPP_DIR ---"

    for IMG in "${IMAGES[@]}"; do
        # Preserve relative directory structure
        REL_PATH="${IMG#"$DATASET_DIR"/}"
        REL_DIR="$(dirname "$REL_PATH")"
        STEM="$(basename "$IMG" | sed 's/\.[^.]*$//')"
        OUT_SUBDIR="$BPP_DIR/$REL_DIR"
        mkdir -p "$OUT_SUBDIR"

        BIN_PATH="$OUT_SUBDIR/${STEM}_bpp$(printf '%04d' "$BPP_X100").bin"
        PNG_PATH="$OUT_SUBDIR/${STEM}_bpp$(printf '%04d' "$BPP_X100").png"

        # Skip if already done
        if [[ -f "$PNG_PATH" ]]; then
            echo "  SKIP (exists): $REL_PATH"
            continue
        fi

        # Convert to PNG if input is JPEG (JPEG AI requires PNG input)
        SRC_PNG="$IMG"
        if [[ "$IMG" != *.png && "$IMG" != *.PNG ]]; then
            TMP_PNG="$OUT_SUBDIR/${STEM}_src.png"
            if [[ ! -f "$TMP_PNG" ]]; then
                conda run -n jpeg_ai_vm python3 \
                    -c "from PIL import Image; Image.open('$IMG').convert('RGB').save('$TMP_PNG')"
            fi
            SRC_PNG="$TMP_PNG"
        fi

        # Encode — must run from JPEGAI_ROOT with jpeg_ai_vm env active
        conda run -n jpeg_ai_vm \
            bash -c "cd '$JPEGAI_ROOT' && python -m src.reco.coders.encoder \
                '$SRC_PNG' '$BIN_PATH' \
                --set_target_bpp '$BPP_X100' \
                --cfg cfg/tools_off.json cfg/profiles/${PROFILE}.json"

        # Decode
        conda run -n jpeg_ai_vm \
            bash -c "cd '$JPEGAI_ROOT' && python -m src.reco.coders.decoder \
                '$BIN_PATH' '$PNG_PATH'"

        # Remove bitstream to save space
        rm -f "$BIN_PATH"

        echo "  OK: $REL_PATH"
    done
done

echo ""
echo "=========================================="
echo "Compression complete. Output: $OUTPUT_DIR"
