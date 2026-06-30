"""
JPEG AI encoder/decoder wrapper.
Calls the official reference software CLI as subprocess.
Must run inside the jpeg_ai_vm conda env.

Repo: https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software
Setup: make configure && make build_test_libs
"""

import subprocess
import shutil
from pathlib import Path


# Path to the cloned jpeg-ai-reference-software repo.
# Override via env var JPEGAI_ROOT or pass explicitly.
import os
JPEGAI_ROOT = Path(os.environ.get(
    "JPEGAI_ROOT",
    str(Path(__file__).resolve().parents[3] / "jpeg-ai-reference-software" / "jpeg-ai-reference-software")
))

# BPP levels used across the project (target_bpp values).
BPP_LEVELS = [0.1, 0.3, 0.5, 0.8, 1.0, 2.0]


def _check_jpegai_available() -> None:
    encoder = JPEGAI_ROOT / "src" / "reco" / "coders" / "encoder.py"
    if not encoder.exists():
        raise RuntimeError(
            f"JPEG AI reference software not found at {JPEGAI_ROOT}.\n"
            "Clone it: git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git\n"
            "Then set JPEGAI_ROOT env var or place it next to this repo."
        )


def encode_image(
    input_png: Path,
    output_bin: Path,
    target_bpp: float,
    profile: str = "base",
) -> None:
    """
    Encode a PNG with JPEG AI at the given target BPP.

    Args:
        input_png:  Path to input PNG (must be RGB, lossless source).
        output_bin: Path where the JPEG AI bitstream will be written.
        target_bpp: Target bits-per-pixel (e.g. 0.5).
        profile:    JPEG AI profile — 'simple', 'base', or 'high'.
    """
    _check_jpegai_available()
    output_bin.parent.mkdir(parents=True, exist_ok=True)

    bpp_x100 = int(target_bpp * 100)
    cmd = [
        "conda", "run", "-n", "jpeg_ai_vm",
        "python", "-m", "src.reco.coders.encoder",
        str(input_png),
        str(output_bin),
        "--set_target_bpp", str(bpp_x100),
        "--cfg",
        str(JPEGAI_ROOT / "cfg" / "tools_off.json"),
        str(JPEGAI_ROOT / "cfg" / "profiles" / f"{profile}.json"),
    ]
    subprocess.run(cmd, check=True, cwd=JPEGAI_ROOT)


def decode_image(input_bin: Path, output_png: Path) -> None:
    """
    Decode a JPEG AI bitstream to PNG.

    Args:
        input_bin:  Path to the JPEG AI bitstream.
        output_png: Path where the reconstructed PNG will be written.
    """
    _check_jpegai_available()
    output_png.parent.mkdir(parents=True, exist_ok=True)

    cmd = [
        "conda", "run", "-n", "jpeg_ai_vm",
        "python", "-m", "src.reco.coders.decoder",
        str(input_bin),
        str(output_png),
    ]
    subprocess.run(cmd, check=True, cwd=JPEGAI_ROOT)


def compress_image(
    input_png: Path,
    output_dir: Path,
    target_bpp: float,
    profile: str = "base",
    keep_bitstream: bool = False,
) -> Path:
    """
    Full encode→decode round-trip for one image.
    Returns path to reconstructed PNG.

    Output layout:
        output_dir/
            <stem>_bpp<bpp_x100>.png      reconstructed image
            <stem>_bpp<bpp_x100>.bin      bitstream (if keep_bitstream=True)
    """
    bpp_x100 = int(target_bpp * 100)
    stem = input_png.stem
    bin_path = output_dir / f"{stem}_bpp{bpp_x100:04d}.bin"
    png_path = output_dir / f"{stem}_bpp{bpp_x100:04d}.png"

    if png_path.exists():
        return png_path  # already compressed, skip

    encode_image(input_png, bin_path, target_bpp, profile)
    decode_image(bin_path, png_path)

    if not keep_bitstream:
        bin_path.unlink(missing_ok=True)

    return png_path


def compress_dataset(
    dataset_dir: Path,
    output_root: Path,
    bpp_levels: list[float] = BPP_LEVELS,
    profile: str = "base",
    extensions: tuple[str, ...] = (".png", ".jpg", ".jpeg"),
) -> dict[float, Path]:
    """
    Compress all images in dataset_dir at each BPP level.

    Output layout:
        output_root/
            bpp_010/   (0.10 BPP)
            bpp_030/   (0.30 BPP)
            ...

    Args:
        dataset_dir: Root folder with original images (searched recursively).
        output_root: Where compressed images are written.
        bpp_levels:  List of target BPP values.
        profile:     JPEG AI profile.
        extensions:  Image file extensions to include.

    Returns:
        Dict mapping BPP value → output directory path.
    """
    images = [
        p for p in dataset_dir.rglob("*")
        if p.suffix.lower() in extensions
    ]
    if not images:
        raise ValueError(f"No images found in {dataset_dir}")

    bpp_dirs: dict[float, Path] = {}
    for bpp in bpp_levels:
        bpp_tag = f"bpp_{int(bpp * 100):03d}"
        bpp_dir = output_root / bpp_tag
        bpp_dir.mkdir(parents=True, exist_ok=True)
        bpp_dirs[bpp] = bpp_dir

        for img_path in images:
            # Preserve relative folder structure inside output dir
            rel = img_path.relative_to(dataset_dir)
            out_subdir = bpp_dir / rel.parent
            out_subdir.mkdir(parents=True, exist_ok=True)

            # Convert to PNG if needed (JPEG AI requires PNG input)
            if img_path.suffix.lower() != ".png":
                from PIL import Image as PILImage
                png_tmp = out_subdir / (img_path.stem + "_src.png")
                if not png_tmp.exists():
                    PILImage.open(img_path).convert("RGB").save(png_tmp)
                src = png_tmp
            else:
                src = img_path

            compress_image(src, out_subdir, bpp, profile)
            print(f"  [{bpp_tag}] {rel} ✓")

    return bpp_dirs
