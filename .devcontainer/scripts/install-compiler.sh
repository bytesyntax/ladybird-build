#!/usr/bin/env bash
# Installs a C++23-capable compiler for Ladybird.
#
# Ladybird requires clang >= 19 or gcc >= 14 (Meta/Utils/find_compiler.py);
# the Ladybird CI pipeline uses clang-22. The chosen compiler is recorded in
# /opt/ladybird-build/toolchain.env, which bootstrap.sh and build-ladybird.sh
# source to set CC/CXX.
#
# Usage: install-compiler.sh [wanted-major-version]     (default: 22)
set -uo pipefail

WANT="${1:-22}"
MIN_CLANG=19
TOOLCHAIN_ENV=/opt/ladybird-build/toolchain.env
mkdir -p /opt/ladybird-build

pick_ok() { # $1 = clang binary; true if it exists and is >= MIN_CLANG
    command -v "$1" >/dev/null 2>&1 || return 1
    local v
    v="$("$1" -dumpversion 2>/dev/null | awk -F. '{print $1}')" || return 1
    [[ "$v" =~ ^[0-9]+$ ]] || return 1
    (( v >= MIN_CLANG ))
}

record() { # $1=cc binary  $2=cxx binary
    echo "export CC=\"$1\" CXX=\"$2\"" > "$TOOLCHAIN_ENV"
    echo "install-compiler: using $1 / $2 (recorded in $TOOLCHAIN_ENV)"
    exit 0
}

# Strategy 1: an acceptable compiler is already installed.
for c in "clang-$WANT" "clang-21" "clang-20" "clang-19" "clang"; do
    if pick_ok "$c"; then
        record "$c" "${c/clang/clang++}"
    fi
done
echo "install-compiler: no usable compiler present, trying package managers"

DISTRIB_ID=""
DISTRIB_CODENAME=""
if [[ -f /etc/lsb-release ]]; then
    . /etc/lsb-release
fi

# Strategy 2: apt.llvm.org, newest wanted version down to the minimum.
if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
    if wget -qO /usr/share/keyrings/llvm-snapshot.gpg.key https://apt.llvm.org/llvm-snapshot.gpg.key; then
        v="$WANT"
        while (( v >= MIN_CLANG )); do
            echo "deb [signed-by=/usr/share/keyrings/llvm-snapshot.gpg.key] http://apt.llvm.org/${DISTRIB_CODENAME}/ llvm-toolchain-${DISTRIB_CODENAME}-${v} main" \
                > /etc/apt/sources.list.d/llvm.list
            apt-get update -y || true
            if apt-get install -y --no-install-recommends \
                    "llvm-$v" "clang-$v" "clangd-$v" "clang-tools-$v" "lld-$v" \
                    "lldb-$v" "clang-tidy-$v" "clang-format-$v" >/dev/null 2>&1; then
                record "clang-$v" "clang++-$v"
            fi
            v=$(( v - 1 ))
        done
    else
        echo "install-compiler: WARNING: could not download apt.llvm.org signing key" >&2
    fi
fi

# Strategy 3: build LLVM from source (last resort; slow, needs disk + RAM).
echo "install-compiler: falling back to building LLVM from source"
LLVM_TAG="$(curl -fsSL https://api.github.com/repos/llvm/llvm-project/releases/latest \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"
MAJ="${LLVM_TAG#v}"; MAJ="${MAJ%%.*}"
echo "install-compiler: building $LLVM_TAG"

apt-get update -y
apt-get install -y --no-install-recommends make ninja-build python3 python3-dev

cd /tmp
curl -fsSL "https://github.com/llvm/llvm-project/releases/download/${LLVM_TAG}/llvm-${LLVM_TAG#v}-src.tar.xz" -o llvm-src.tar.xz
tar xf llvm-src.tar.xz
SRC_DIR="$(ls -d /tmp/llvm-*llvm-project | head -n1)"

cmake -S "$SRC_DIR/llvm" -B /tmp/llvm-build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="host" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$(uname -m)-unknown-linux-gnu" \
    -DCMAKE_INSTALL_PREFIX=/opt/llvm-src \
    -DLLVM_PARALLEL_LINK_JOBS=2
ninja -C /tmp/llvm-build -j"$(nproc)" install

for t in clang clang++ clangd lld clang-format clang-tidy; do
    ln -sf "/opt/llvm-src/bin/$t" "/usr/local/bin/${t}-${MAJ}"
done
rm -rf /tmp/llvm-src.tar.xz /tmp/llvm-*llvm-project /tmp/llvm-build
record "clang-$MAJ" "clang++-$MAJ"
