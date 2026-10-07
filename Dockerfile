# base-notebook, not scipy-notebook: nothing in these notebooks imports scipy,
# sklearn, matplotlib, seaborn or numba, and those account for ~1GB of the
# download. pandas is the only base package the notebooks actually use, and pip
# adds it in seconds. Pin this by digest once a build is known good.
FROM jupyter/base-notebook@sha256:8c903974902b0e9d45d9823c2234411de0614c5c98c4bb782b3d4f55b3e435e6

USER root

# Create directories with proper permissions
RUN mkdir -p /workspace/notebooks /workspace/data /workspace/lancedb_data && \
    chown -R ${NB_UID}:${NB_GID} /workspace

USER ${NB_UID}

# 'ratelimit' is a placekey dependency published only as a legacy sdist with no
# pyproject.toml, so pip falls back to setup.py - and pip's ISOLATED build env
# has no setuptools, which fails the whole install. The ambient env does have
# setuptools, so building it without isolation works. No compiler is involved,
# which is why there is no build-essential in this image.
RUN pip install --no-cache-dir --no-build-isolation ratelimit

# pandas is pinned below 3.0 deliberately. base-notebook ships no pandas, so pip
# takes the newest major - and pandas 3.0 does not recognise SQLAlchemy 2.0 as a
# connectable, so every pd.read_sql(..., engine) falls through to the SQLite path
# and dies with "'Engine' object has no attribute 'cursor'". pandas 3 also turns
# on copy-on-write and the new string dtype, neither of which these notebooks
# have been tested against. sqlalchemy is listed explicitly because the notebooks
# import it directly - it used to arrive only as a transitive dependency.
# Install Python packages for the workshop
RUN pip install --no-cache-dir \
    senzing-grpc \
    psycopg2-binary \
    placekey \
    lancedb \
    "pandas>=2,<3" \
    sqlalchemy \
    networkx \
    pyvis \
    folium \
    python-dotenv \
    fastembed \
    anthropic \
    openai

# The anthropic and openai SDKs ship httpx2, whose BrotliDecoder calls
# Decompressor.process(data, output_buffer_limit=...). That keyword only exists
# in Brotli 1.2.0+; the base image pins an older one, where process() is a C
# function taking no kwargs. Every API call then dies with a TypeError wrapped
# in a misleading APIConnectionError, which looks like a network fault.
RUN pip install --no-cache-dir --upgrade "Brotli>=1.2.0"

# fastembed replaces sentence-transformers, which pulled in torch. The aarch64
# torch wheel links against OpenBLAS expecting 'sbgemm_', which the conda
# OpenBLAS does not export, so `import torch` died with "undefined symbol:
# sbgemm_" on every arm64 (Apple Silicon) machine. fastembed runs the same
# all-MiniLM-L6-v2 on onnxruntime at the same 384 dimensions, with no torch.

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
