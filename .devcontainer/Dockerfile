# Ladybird build container - self-contained recipe.
#
# REBUILD TRIGGER: the hash of this recipe directory is baked into the image
# at /opt/ladybird-build/recipe.sha256 (last RUN below). The same hash is
# recomputed on the live workspace by:
#   - scripts/check-fresh.sh  (postCreate/postStart, in-container; --strict in CI)
#   - scripts/rebuild-if-stale.sh (host-side, wired into git hooks)
#   - the GitHub devcontainer workflow (paths: .devcontainer/**)
# If they drift, the container is stale and must be rebuilt.
#
# Base: Ubuntu 24.04 (noble) via the official devcontainers base image.
FROM mcr.microsoft.com/devcontainers/base:noble

# Preferred clang major from apt.llvm.org; the installer falls back to older
# versions (min 19) and finally to a from-source LLVM build.
ARG LLVM_VERSION=22
ENV DEBIAN_FRONTEND=noninteractive

# --- Base build tools ---------------------------------------------------------
# From Ladybird's Documentation/BuildInstructionsLadybird.md (Debian/Ubuntu
# list) plus the extras from the upstream .devcontainer feature.
#
# The X11 dev set (libxcb*-dev & friends) is required by vcpkg's qtbase port:
# on Linux it force-enables the xcb/xlib/xkb Qt features and expects these
# libraries to come from the system package manager (it prints exactly this
# list as a warning). Without them qtbase dies at its own CMake configure.
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf autoconf-archive automake build-essential ccache curl \
        fonts-liberation2 glslang-tools gpg git libdrm-dev libgl1-mesa-dev \
        libncurses-dev libpulse-dev libtool libwayland-dev 'libxcb*-dev' \
        libx11-xcb-dev libegl1-mesa-dev libglu1-mesa-dev libxi-dev \
        libxkbcommon-dev libxkbcommon-x11-dev libxrender-dev \
        lsb-release nasm ninja-build pkg-config python3 python3-venv \
        shellcheck tar unzip zip wget \
    && rm -rf /var/lib/apt/lists/*

# --- CMake >= 3.30 (noble ships 3.28) ------------------------------------------
COPY scripts/install-cmake.sh /tmp/install-cmake.sh
RUN bash /tmp/install-cmake.sh && rm -f /tmp/install-cmake.sh

# --- C++23 compiler (minimum clang 19; Ladybird CI uses clang 22) --------------
COPY scripts/install-compiler.sh /tmp/install-compiler.sh
RUN bash /tmp/install-compiler.sh "${LLVM_VERSION}" && rm -f /tmp/install-compiler.sh

# --- Rust (rustup; ladybird's rust-toolchain.toml pins the exact toolchain) ----
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable

# The container runs as vscode (uid 1000), but rustup installed as root:
# ladybird's rust-toolchain.toml makes rustup download+write its pinned
# toolchain on the first cargo run, so both dirs must be user-writable.
RUN chown -R 1000:1000 /usr/local/rustup /usr/local/cargo

# --- Cache directories ----------------------------------------------------------
# /var/lib/ladybird-cache is mounted as a persistent devcontainer volume (see
# devcontainer.json) and holds the vcpkg binary cache + ccache, so container
# rebuilds do not throw away compiled third-party dependencies.
RUN mkdir -p /var/lib/ladybird-cache /usr/local/share/vcpkg-binary-cache

# --- Bake the recipe self-hash (rebuild-trigger anchor) --------------------------
COPY . /opt/ladybird-build/recipe/
RUN bash /opt/ladybird-build/recipe/scripts/hash-recipe.sh /opt/ladybird-build/recipe \
        > /opt/ladybird-build/recipe.sha256 \
    && echo "baked recipe hash: $(cat /opt/ladybird-build/recipe.sha256)"
