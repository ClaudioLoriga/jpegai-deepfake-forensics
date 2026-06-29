# Dockerfile for JPEG AI reference software
# Wraps the official encoder/decoder for use on macOS or any non-Linux host.
#
# Build:  docker build -t jpegai-codec -f docker/Dockerfile .
# Run:    docker run --rm -v $(pwd)/data:/workspace/project/data jpegai-codec \
#           bash scripts/compress_dataset.sh data/original data/compressed
#
# GPU support (Linux host only):
#   docker run --rm --gpus all -v $(pwd)/data:/workspace/project/data jpegai-codec ...

# Force x86_64 — JPEG AI has no ARM/Apple-Silicon native build.
# Runs via Rosetta 2 on Apple Silicon (slow but correct).
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CONDA_DIR=/opt/conda
ENV PATH=$CONDA_DIR/bin:$PATH

# ── System packages ───────────────────────────────────────────────────────────
# Includes all deps JPEG AI's setup_system.sh would install, plus sudo so
# the script itself doesn't fail when called directly.
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    git \
    git-lfs \
    curl \
    wget \
    make \
    cmake \
    g++ \
    libgomp1 \
    doxygen \
    graphviz \
    ca-certificates \
    python3-pip \
    python3-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && echo "root ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Miniconda with Python 3.9 ─────────────────────────────────────────────────
# JPEG AI pins numpy==1.19.1 which requires Python <=3.9. Latest Miniconda
# ships Python 3.13 which breaks it, so we pin the installer version.
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-py39_23.5.2-0-Linux-x86_64.sh \
        -O /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p $CONDA_DIR \
    && rm /tmp/miniconda.sh \
    && conda clean -afy

WORKDIR /workspace

# ── Clone JPEG AI reference software ─────────────────────────────────────────
RUN git clone https://gitlab.com/wg1/jpeg-ai/jpeg-ai-reference-software.git \
    && cd jpeg-ai-reference-software \
    && git lfs install \
    && git lfs fetch \
    && git lfs checkout

# ── Create jpeg_ai_vm conda env manually ─────────────────────────────────────
# All packages sourced from JPEG AI requirements.txt, with version pins relaxed
# where they conflict with Python 3.9 + modern pip (numpy, torch, scikit-image).
RUN conda create -y -n jpeg_ai_vm python=3.9 \
    && conda run -n jpeg_ai_vm pip install --upgrade pip setuptools wheel \
    # pybind11 must come before building C++ libs
    && conda run -n jpeg_ai_vm pip install pybind11 \
    # Core numerical — relax old pins that break on py3.9
    && conda run -n jpeg_ai_vm pip install \
        "numpy==1.23.5" \
        "scipy==1.9.3" \
        "scikit-image==0.19.3" \
        "scikit-learn==1.0.2" \
        "scikit-learn-extra==0.3.0" \
        "pandas==1.3.5" \
    # PyTorch — use newer compatible version (JPEG AI's 1.10.2 too old for py3.9 wheels)
    && conda run -n jpeg_ai_vm pip install \
        "torch==2.0.1" \
        "torchvision==0.15.2" \
    # OpenCV headless (no GUI needed in container; avoids libGL issues)
    && conda run -n jpeg_ai_vm pip install \
        "opencv-python-headless==4.7.0.72" \
    # All remaining JPEG AI requirements.txt packages
    && conda run -n jpeg_ai_vm pip install \
        "addict==2.2.1" \
        "attrs==21.4.0" \
        "decorator==4.4.2" \
        "einops==0.5.0" \
        "fsspec==2022.11.0" \
        "GPUtil==1.4.0" \
        "ipython==7.34.0" \
        "lightgbm==3.3.2" \
        "openpyxl" \
        "packaging==21.3" \
        "prettytable==0.7.2" \
        "protobuf==3.20.3" \
        "psutil==5.9.1" \
        "ptflops==0.6.5" \
        "pybind11" \
        "pynvml==8.0.4" \
        "pyrtools==1.0.4" \
        "pytorch-msssim==0.2.1" \
        "tensorboard==2.11.0" \
        "commentjson==0.9.0" \
        "python-gitlab==3.15.0" \
        "bjontegaard==1.1.0" \
        "timm" \
        "lpips" \
        "thop"

# ── Build JPEG AI C++ extension libs ─────────────────────────────────────────
RUN conda run -n jpeg_ai_vm \
    bash -c "cd /workspace/jpeg-ai-reference-software && make build_test_libs"

# ── Copy project files ────────────────────────────────────────────────────────
COPY . /workspace/project

# Install project Python dependencies into the same env
RUN conda run -n jpeg_ai_vm pip install -r /workspace/project/requirements.txt

RUN chmod +x /workspace/project/scripts/compress_dataset.sh

ENV JPEGAI_ROOT=/workspace/jpeg-ai-reference-software
ENV CONDA_DEFAULT_ENV=jpeg_ai_vm

WORKDIR /workspace/project

# Activate jpeg_ai_vm on every bash invocation
RUN echo "conda activate jpeg_ai_vm" >> ~/.bashrc

CMD ["/bin/bash", "--login"]
