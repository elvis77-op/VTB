#!/bin/bash
set -e

PROJECT_ROOT="${1:?Usage: $0 <PROJECT_ROOT>}"
ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
OUTPUT_DIR="${PROJECT_ROOT}/output"

echo "============================================"
echo "  Prepare Host-Side Dependencies"
echo "============================================"
echo "Project root: $PROJECT_ROOT"
echo "RootFS dir:   $ROOTFS_DIR"
echo ""

collect_tdx_libs() {
    echo ""
    echo "========================================"
    echo "  Collecting TDX Libraries"
    echo "========================================"

    TDX_SEARCH_PATHS=(
        "/lib/x86_64-linux-gnu"
    )

    TDX_LIB_PATTERNS=(
        "libtdx*"
    )
    
    local found_any=false
    
    for search_path in "${TDX_SEARCH_PATHS[@]}"; do
        [ -d "$search_path" ] || continue
        
        for pattern in "${TDX_LIB_PATTERNS[@]}"; do
            find "$search_path" -name "$pattern" 2>/dev/null | while read lib_path; do
                lib_name=$(basename "$lib_path")
                target_dir="${ROOTFS_DIR}$(dirname "$lib_path")"
                
                mkdir -p "$target_dir"
                echo " Copying TDX lib: $lib_name"
                cp -v "$lib_path" "$target_dir/"

                if [ -L "$lib_path" ]; then
                    real_path=$(readlink -f "$lib_path")
                    if [ -f "$real_path" ]; then
                        cp -v "$real_path" "$target_dir/"
                    fi
                fi
                
                found_any=true
            done
        done
    done
    
    if ! $found_any; then
        echo " No TDX libraries found. If TDX is needed, please install TDX SDK first."
    fi
}

mkdir -p "${ROOTFS_DIR}/bin"
mkdir -p "${ROOTFS_DIR}/lib/modules"
mkdir -p "${ROOTFS_DIR}/usr/lib"
mkdir -p "${ROOTFS_DIR}/dev"
mkdir -p "${OUTPUT_DIR}"

echo 'deb [signed-by=/etc/apt/keyrings/intel-sgx-keyring.asc arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu noble main' | tee /etc/apt/sources.list.d/intel-sgx.list
wget --no-check-certificate https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key
mkdir -p /etc/apt/keyrings
cat intel-sgx-deb.key | tee /etc/apt/keyrings/intel-sgx-keyring.asc > /dev/null
apt-get update
apt install -y libtdx-attest libtdx-attest-dev
make /opt/intel/tdx-quote-generation-sample/
cp /opt/intel/tdx-quote-generation-sample/test_tdx_attest "${ROOTFS_DIR}/bin/test_tdx_attest"
HEADER_PATH=$(find /usr/include -name "tdx_attest.h" -type f | head -1)

cp "$HEADER_PATH" "src/"

collect_tdx_libs

mkdir -p "${ROOTFS_DIR}/.host_deps"
echo "DONE" > "${ROOTFS_DIR}/.host_deps/ready"

echo ""
echo "============================================"
echo " Dependencies Collected Successfully"
echo "============================================"