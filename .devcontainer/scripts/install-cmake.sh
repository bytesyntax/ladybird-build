#!/usr/bin/env bash
# Installs CMake >= 3.30 (Ladybird requirement; noble ships 3.28).
#
# Strategy:
#   1. keep the distro cmake if it is new enough
#   2. Kitware apt repository (Ubuntu-only)
#   3. official Kitware binary tarball from GitHub releases
set -euo pipefail

CMAKE_MIN="3.30"

cmake_is_new_enough() {
    command -v cmake >/dev/null 2>&1 || return 1
    local v
    v="$(cmake --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
    [[ -n "$v" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$v" "$CMAKE_MIN" | sort -V | head -n1)" == "$CMAKE_MIN" ]]
}

if cmake_is_new_enough; then
    echo "install-cmake: using existing $(cmake --version | head -n1)"
    exit 0
fi

DISTRIB_ID=""
DISTRIB_CODENAME=""
if [[ -f /etc/lsb-release ]]; then
    . /etc/lsb-release
fi

# Strategy 2: Kitware apt repository (Ubuntu-only).
if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
    if wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null \
            | gpg --dearmor > /usr/share/keyrings/kitware-archive-keyring.gpg; then
        echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${DISTRIB_CODENAME} main" \
            > /etc/apt/sources.list.d/kitware.list
        apt-get update -y
        apt-get install -y --no-install-recommends cmake
        if cmake_is_new_enough; then
            echo "install-cmake: installed $(cmake --version | head -n1) from apt.kitware.com"
            exit 0
        fi
        apt-get update -y
    else
        echo "install-cmake: WARNING: could not download Kitware GPG key, falling back to tarball" >&2
    fi
fi

# Strategy 3: official binary tarball from GitHub releases.
case "$(uname -m)" in
    x86_64)  TARGET="x86_64" ;;
    aarch64) TARGET="aarch64" ;;
    *)
        echo "install-cmake: unsupported architecture '$(uname -m)' for the tarball fallback" >&2
        exit 1
        ;;
esac
URL="$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(a["browser_download_url"] for a in d["assets"] if a["name"].endswith("-linux-%s.tar.gz" % TARGET)))')"
echo "install-cmake: downloading $URL"
curl -fsSL "$URL" | tar xz -C /opt --strip-components=1
ln -sf /opt/bin/cmake /usr/local/bin/cmake
ln -sf /opt/bin/cpack /usr/local/bin/cpack
ln -sf /opt/bin/ctest /usr/local/bin/ctest
cmake --version
if ! cmake_is_new_enough; then
    echo "install-cmake: FAILED to install CMake >= $CMAKE_MIN" >&2
    exit 1
fi
echo "install-cmake: installed $(cmake --version | head -n1)"
