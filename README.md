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
│   └── compress_dataset.sh         # Batch compression script
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

# AMD GPU (ROCm) — install PyTorch first:
pip install torch torchvision --extra-index-url https://download.pytorch.org/whl/rocm5.7

# NVIDIA GPU (CUDA) — install PyTorch first:
# pip install torch torchvision

pip install -r requirements.txt
```

### 2. Set up JPEG AI reference software

**Linux native (recommended):**
```bash
git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git
cd jpeg-ai-reference-software
git lfs fetch && git lfs checkout
make configure          # creates jpeg_ai_vm conda env
make build_test_libs
cd ..
```

For AMD GPU (ROCm), replace the PyTorch wheel inside `jpeg_ai_vm` after `make configure`:
```bash
conda activate jpeg_ai_vm
pip install "torch==2.0.1+rocm5.4.2" "torchvision==0.15.2+rocm5.4.2" \
    --extra-index-url https://download.pytorch.org/whl/rocm5.4.2
```

### 3. Place your dataset

```
data/original/
    real/   ← genuine images
    fake/   ← deepfake images
```

Recommended: [FaceForensics++](https://github.com/ondyari/FaceForensics) subset (e.g. 1000 real + 1000 fake per manipulation type).

### 4. Run JPEG AI compression

```bash
conda activate jpeg_ai_vm
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

## Experimental Results

The project benchmarks detector baseline performance under neural compression and evaluates two mitigation strategies on ResNet50.

### 1. Baseline Degradation Results
| Backbone | BPP Level | AUC Score | Accuracy |
|---|---|---|---|
| **ResNet50** | original | 0.9999 | 99.92% |
| **ResNet50** | 2.0 (High Q.) | 0.9543 | 86.35% |
| **ResNet50** | 0.8 (Med Q.) | 0.9574 | 87.00% |
| **ResNet50** | 0.1 (Low Q.) | 0.8896 | 79.80% |
| **EfficientNet-B4** | original | 0.9999 | 99.77% |
| **EfficientNet-B4** | 2.0 (High Q.) | 0.8437 | 75.30% |
| **EfficientNet-B4** | 0.8 (Med Q.) | 0.8442 | 77.80% |
| **EfficientNet-B4** | 0.1 (Low Q.) | 0.8518 | 74.60% |

### 2. Mitigation Performance on ResNet50
| BPP Level | Baseline Acc | MIT-1 Acc (Neural) | MIT-1 Gain (vs Base) | MIT-2 Acc (JPEG) | MIT-2 Gain (vs Base) |
|---|---|---|---|---|---|
| **original** | 99.92% | 99.92% | 0.00% | 99.97% | +0.05% |
| **2.0 (High Q.)** | 86.35% | 87.35% | +1.00% | 80.32% | -6.03% |
| **1.0** | 87.20% | 86.80% | -0.40% | 81.60% | -5.60% |
| **0.8 (Med Q.)** | 87.00% | 87.20% | +0.20% | 81.20% | -5.80% |
| **0.5** | 85.40% | 85.60% | +0.20% | 82.00% | -3.40% |
| **0.3** | 83.60% | 86.60% | +3.00% | 82.40% | -1.20% |
| **0.1 (Low Q.)** | 79.80% | 82.60% | +2.80% | 74.40% | -5.40% |

*   **MIT-1 (JPEG AI Augmentation)** provides stable improvements under high compression (+2.80% at BPP=0.1).
*   **MIT-2 (Standard JPEG Augmentation)** degrades accuracy across all BPP levels (down to -6.03% at BPP=2.0). Standard JPEG grid-based features are incompatible with JPEG AI's smooth neural convolutions.

## Reference

E. D. Cannas et al., "Is JPEG AI Going to Change Image Forensics?", ICCVW 2025. DOI: 10.1109/ICCVW69036.2025.00167

