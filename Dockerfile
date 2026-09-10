# Pinned by digest: this is the exact base the working image was built from.
# ':latest' is how a CUDA-heavy base can appear without any change on our side.
FROM jupyter/scipy-notebook@sha256:fca4bcc9cbd49d9a15e0e4df6c666adf17776c950da9fa94a4f0a045d5c4ad33

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create directories with proper permissions
RUN mkdir -p /workspace/notebooks /workspace/data /workspace/lancedb_data && \
    chown -R ${NB_UID}:${NB_GID} /workspace

USER ${NB_UID}

# CPU-only torch FIRST. sentence-transformers otherwise resolves the default
# CUDA build and drags in nvidia (2.7G) + torch (1.2G) + triton (691M) - 4.6GB
# of GPU libraries that nothing in this workshop can use, since everything runs
# CPU-only in a container. Installing the CPU wheel up front means the later
# install sees torch already satisfied.
# --no-deps is essential: --index-url REPLACES PyPI for the whole resolution, so
# without it torch's dependencies also come from the PyTorch mirror, where a
# conflicting 'backports' clobbers the one setuptools needs. setuptools then
# fails to import, and every later sdist build dies with a confusing
# "setuptools is not available in the build environment". Taking torch alone
# from that index and letting its dependencies resolve from PyPI avoids it.
RUN pip install --no-cache-dir --no-deps \
    --index-url https://download.pytorch.org/whl/cpu \
    torch

# 'ratelimit' is a placekey dependency published only as a legacy sdist with no
# pyproject.toml, so pip falls back to setup.py - and pip's ISOLATED build env
# has no setuptools, which fails the whole install. The ambient env does have
# setuptools, so building it without isolation works. Do it first, then the main
# install below sees it already satisfied.
RUN pip install --no-cache-dir --no-build-isolation ratelimit

# Install Python packages for the workshop
RUN pip install --no-cache-dir \
    senzing-grpc \
    psycopg2-binary \
    placekey \
    lancedb \
    pandas \
    networkx \
    pyvis \
    python-dotenv \
    sentence-transformers \
    dspy-ai \
    anthropic \
    openai

# Set working directory
WORKDIR /workspace
