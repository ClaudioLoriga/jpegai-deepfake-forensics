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

set -uo pipefail

DATASET_DIR="${1:?Usage: $0 <DATASET_DIR> <OUTPUT_DIR> [JPEGAI_ROOT]}"
OUTPUT_DIR="${2:?Usage: $0 <DATASET_DIR> <OUTPUT_DIR> [JPEGAI_ROOT]}"
JPEGAI_ROOT="${3:-../../jpeg-ai-reference-software/jpeg-ai-reference-software}"
PROFILE="base"

# BPP levels × 100 (JPEG AI CLI expects integer)
BPP_VALUES=(10 30 50 80 100 200)

if [[ ! -d "$JPEGAI_ROOT" ]]; then
    echo "ERROR: JPEG AI repo not found at $JPEGAI_ROOT"
    echo "Clone it: git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git"
    exit 1
fi

# Max images per class (subdirectory). 0 = no limit.
MAX_PER_CLASS="${MAX_PER_CLASS:-150}"

# Collect images: sample MAX_PER_CLASS per first-level subdirectory (class)
IMAGES=()
while IFS= read -r -d '' CLASS_DIR; do
    CLASS_IMAGES=()
    mapfile -d '' CLASS_IMAGES < <(find "$CLASS_DIR" -maxdepth 1 -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -print0 | sort -z)
    if [[ $MAX_PER_CLASS -gt 0 && ${#CLASS_IMAGES[@]} -gt $MAX_PER_CLASS ]]; then
        CLASS_IMAGES=("${CLASS_IMAGES[@]:0:$MAX_PER_CLASS}")
    fi
    IMAGES+=("${CLASS_IMAGES[@]}")
    echo "  Class '$(basename "$CLASS_DIR")': ${#CLASS_IMAGES[@]} images selected"
done < <(find "$DATASET_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "ERROR: No images found in $DATASET_DIR"
    exit 1
fi

N_IMAGES="${#IMAGES[@]}"
N_BPP="${#BPP_VALUES[@]}"
TOTAL=$(( N_IMAGES * N_BPP ))
DONE=0
OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
START_TS=$(date +%s)

echo "Found $N_IMAGES images in $DATASET_DIR"
echo "Output -> $OUTPUT_DIR"
echo "Profile: $PROFILE"
echo "BPP levels: ${BPP_VALUES[*]}"
echo "Total operations: $TOTAL  ($N_IMAGES images × $N_BPP BPP levels)"
echo "=========================================="

# ── Progress bar helper ───────────────────────────────────────────────────────
_progress() {
    local current=$1 total=$2 ok=$3 fail=$4 skip=$5 label="$6"
    local pct=$(( current * 100 / total ))
    local filled=$(( pct * 40 / 100 ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=filled; i<40; i++ )); do bar+="░"; done

    local elapsed=$(( $(date +%s) - START_TS ))
    local eta="--"
    if [[ $current -gt 0 ]]; then
        local remaining=$(( elapsed * (total - current) / current ))
        eta="$(printf '%02d:%02d' $(( remaining/60 )) $(( remaining%60 )))"
    fi
    local elapsed_fmt
    elapsed_fmt="$(printf '%02d:%02d' $(( elapsed/60 )) $(( elapsed%60 )))"

    printf "\r[%s] %3d%% (%d/%d) | ✓%d ✗%d ~%d | elapsed %s ETA %s | %s          " \
        "$bar" "$pct" "$current" "$total" "$ok" "$fail" "$skip" \
        "$elapsed_fmt" "$eta" "$label"
}

for BPP_X100 in "${BPP_VALUES[@]}"; do
    BPP_TAG="bpp_$(printf '%03d' "$BPP_X100")"
    BPP_DIR="$OUTPUT_DIR/$BPP_TAG"
    mkdir -p "$BPP_DIR"

    printf "\n\n--- BPP=%s/100 -> %s ---\n" "$BPP_X100" "$BPP_DIR"

    for IMG in "${IMAGES[@]}"; do
        # Preserve relative directory structure
        REL_PATH="${IMG#"$DATASET_DIR"/}"
        REL_DIR="$(dirname "$REL_PATH")"
        STEM="$(basename "$IMG" | sed 's/\.[^.]*$//')"
        OUT_SUBDIR="$BPP_DIR/$REL_DIR"
        mkdir -p "$OUT_SUBDIR"

        BIN_PATH="$OUT_SUBDIR/${STEM}_bpp$(printf '%04d' "$BPP_X100").bin"
        PNG_PATH="$OUT_SUBDIR/${STEM}_bpp$(printf '%04d' "$BPP_X100").png"

        DONE=$(( DONE + 1 ))

        # Skip if already done
        if [[ -f "$PNG_PATH" ]]; then
            SKIP_COUNT=$(( SKIP_COUNT + 1 ))
            _progress "$DONE" "$TOTAL" "$OK_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "SKIP: $REL_PATH"
            continue
        fi

        _progress "$DONE" "$TOTAL" "$OK_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "enc: $REL_PATH"

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

        # Encode — must run from JPEGAI_ROOT; use absolute paths to avoid cwd issues
        ABS_SRC_PNG="$(realpath "$SRC_PNG")"
        ABS_BIN_PATH="$(realpath -m "$BIN_PATH")"
        ABS_PNG_PATH="$(realpath -m "$PNG_PATH")"

        if conda run -n jpeg_ai_vm \
            bash -c "cd '$JPEGAI_ROOT' && python -m src.reco.coders.encoder \
                '$ABS_SRC_PNG' '$ABS_BIN_PATH' \
                --set_target_bpp '$BPP_X100' \
                --cfg cfg/tools_off.json cfg/profiles/${PROFILE}.json" 2>/dev/null; then

            _progress "$DONE" "$TOTAL" "$OK_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "dec: $REL_PATH"

            # Decode
            if conda run -n jpeg_ai_vm \
                bash -c "cd '$JPEGAI_ROOT' && python -m src.reco.coders.decoder \
                    '$ABS_BIN_PATH' '$ABS_PNG_PATH'" 2>/dev/null; then
                OK_COUNT=$(( OK_COUNT + 1 ))
            else
                FAIL_COUNT=$(( FAIL_COUNT + 1 ))
            fi

            # Remove bitstream to save space
            rm -f "$ABS_BIN_PATH"
        else
            FAIL_COUNT=$(( FAIL_COUNT + 1 ))
            rm -f "$ABS_BIN_PATH"
        fi

        _progress "$DONE" "$TOTAL" "$OK_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$REL_PATH"
    done
done

printf "\n\n=========================================="
printf "\nDone. OK=%d  FAIL=%d  SKIP=%d  Total=%d\n" "$OK_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

echo ""
echo "=========================================="
echo "Compression complete. Output: $OUTPUT_DIR"
