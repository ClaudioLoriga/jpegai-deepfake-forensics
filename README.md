# JPEG AI as a Threat to Deepfake Detection
**Computer Vision — Prof. Irene Amerini — Spring 2026**

Investigates how JPEG AI (ISO/IEC 6048-1) neural compression degrades state-of-the-art deepfake detectors, characterizes the degradation via frequency-domain analysis, and compares mitigation strategies.

## Project Structure

```
.
├── notebook.ipynb                  # Main project notebook (all phases)
├── src/
│   ├── compression/
│   │   └── jpegai_codec.py         # Python wrapper for JPEG AI encoder/decoder CLI
│   ├── detectors/                  # Pre-trained detector loaders
│   ├── analysis/                   # Frequency analysis utilities
│   └── mitigation/                 # Fine-tuning and domain-adaptation code
├── scripts/
│   └── compress_dataset.sh         # Batch compression script (Linux/Docker)
├── docker/
│   └── Dockerfile                  # JPEG AI environment for macOS / CI
├── data/
│   ├── original/                   # Raw dataset (real/ + fake/ subdirs)
│   └── compressed/                 # JPEG AI outputs (bpp_010/ … bpp_200/)
├── results/                        # Plots and metric CSVs
├── checkpoints/                    # Fine-tuned model weights
└── requirements.txt
```

## Setup

### 1. Clone and install Python dependencies

```bash
git clone <this-repo>
cd jpegai-deepfake-forensics
pip install -r requirements.txt
```

### 2. Set up JPEG AI reference software

**Linux (native):**
```bash
git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git
cd jpeg-ai-reference-software
git lfs fetch && git lfs checkout
make configure          # creates jpeg_ai_vm conda env
make build_test_libs
cd ..
```

**macOS (Docker):**
```bash
docker build -t jpegai-codec -f docker/Dockerfile .
```

### 3. Place your dataset

```
data/original/
    real/   ← genuine images
    fake/   ← deepfake images
```

Recommended: [FaceForensics++](https://github.com/ondyari/FaceForensics) subset (e.g. 1000 real + 1000 fake per manipulation type).

### 4. Run JPEG AI compression

**Linux:**
```bash
conda activate jpeg_ai_vm
bash scripts/compress_dataset.sh data/original data/compressed
```

**macOS (Docker):**
```bash
docker run --rm -v $(pwd)/data:/workspace/project/data jpegai-codec \
    bash scripts/compress_dataset.sh data/original data/compressed
```

### 5. Run the notebook

```bash
jupyter notebook notebook.ipynb
```

## Phases

| Phase | Description |
|---|---|
| **1 — Compression pipeline** | Compress dataset at BPP ∈ {0.1, 0.3, 0.5, 0.8, 1.0, 2.0} |
| **2 — Baseline evaluation** | Benchmark detectors; plot AUC / accuracy vs BPP |
| **3 — Frequency analysis** | DCT histograms + azimuthal power spectra |
| **4 — Mitigation** | Fine-tuning on augmented data; JPEG-augmentation baseline |

## Reference

E. D. Cannas et al., "Is JPEG AI Going to Change Image Forensics?", ICCVW 2025. DOI: 10.1109/ICCVW69036.2025.00167
