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
    folium \
    python-dotenv \
    fastembed \
    dspy-ai \
    anthropic \
    openai

# The anthropic and openai SDKs ship httpx2, whose BrotliDecoder calls
# Decompressor.process(data, output_buffer_limit=...). That keyword only exists
# in Brotli 1.2.0+; the base image pins 1.1.0, where process() is a C function
# taking no kwargs. Every API call then dies with a TypeError wrapped in a
# misleading APIConnectionError, which looks like a network fault but is not.
RUN pip install --no-cache-dir --upgrade "Brotli>=1.2.0"

# fastembed replaces sentence-transformers, which pulled in torch. The aarch64
# torch wheel links against OpenBLAS expecting 'sbgemm_', which the conda
# OpenBLAS in this base image does not export, so `import torch` died with
# "undefined symbol: sbgemm_" on every arm64 (Apple Silicon) machine. fastembed
# runs the same all-MiniLM-L6-v2 on onnxruntime at the same 384 dimensions, with
# no torch at all - which also drops ~800MB from the pull.

# A fixed, world-readable cache so the baked model is found at runtime. The
# container runs as the attendee's own uid, which is not necessarily jovyan's,
# so a cache under $HOME would silently miss and re-download.
ENV FASTEMBED_CACHE_PATH=/opt/fastembed_cache

USER root
RUN mkdir -p /opt/fastembed_cache && chown ${NB_UID}:${NB_GID} /opt/fastembed_cache
USER ${NB_UID}

# Bake the model (~90MB). Without this the first embed call in a fresh container
# downloads it with no progress output, which is indistinguishable from a hang -
# and would have forty attendees downloading it at once over conference wifi.
RUN python -c "from fastembed import TextEmbedding; \
    TextEmbedding('sentence-transformers/all-MiniLM-L6-v2')"

# Make the cache readable by any uid. This runs as root because chmod on a
# directory requires owning it, and the container runs as the attendee's own
# uid, which is neither root nor jovyan.
USER root
RUN chmod -R a+rX /opt/fastembed_cache
USER ${NB_UID}

# Set working directory
WORKDIR /workspace
