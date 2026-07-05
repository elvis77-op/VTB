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

collect_vsock_modules() {
    echo "========================================"
    echo "  Collecting VSOCK Kernel Modules"
    echo "========================================"

    if ! command -v zstd &> /dev/null; then
        echo "Installing zstd for kernel module decompression..."
        apt-get update -qq && apt-get install -y -qq zstd 2>/dev/null || {
            echo "⚠ Cannot install zstd, will try to copy compressed modules as-is"
        }
    fi

    if [ -d "/host/lib/modules" ]; then
        MODULES_BASE="/host/lib/modules"
        echo "Modules source: $MODULES_BASE (from /host mount)"
    elif [ -d "/lib/modules" ]; then
        MODULES_BASE="/lib/modules"
        echo "Modules source: $MODULES_BASE (from system)"
    else
        echo "ERROR: Cannot find kernel modules directory"
        return 1
    fi

    KERNEL_VER=$(uname -r)
    echo "Running kernel version: $KERNEL_VER"
    
    if [ ! -d "${MODULES_BASE}/${KERNEL_VER}" ]; then
        echo "⚠ Running kernel modules not found, searching for closest match..."
        KERNEL_VER=$(ls "$MODULES_BASE" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
        echo "Using kernel version: $KERNEL_VER"
    fi
    
    HOST_MODULES="${MODULES_BASE}/${KERNEL_VER}"
    TARGET_MODULES="${ROOTFS_DIR}/lib/modules/${KERNEL_VER}"
    
    echo "Source: $HOST_MODULES"
    echo "Target: $TARGET_MODULES"
    echo ""

    mkdir -p "${TARGET_MODULES}"

    copy_and_decompress_module() {
        local src="$1"
        local dst_dir="$2"
        local module_name=$(basename "$src")

        local pure_name="$module_name"
        
        mkdir -p "$dst_dir"

        case "$module_name" in
            *.ko.zst)
                pure_name="${module_name%.ko.zst}.ko"
                echo "  Decompressing: $module_name → $pure_name"
                if command -v zstd &> /dev/null; then
                    zstd -d "$src" -o "${dst_dir}/${pure_name}" 2>&1 | sed 's/^/    /'
                    echo "  ✓ Decompressed: $pure_name"
                else
                    echo "  ✗ zstd not available, copying compressed: $module_name"
                    cp -v "$src" "${dst_dir}/${module_name}"
                fi
                ;;
            *.ko.gz)
                pure_name="${module_name%.ko.gz}.ko"
                echo "  Decompressing: $module_name → $pure_name"
                gunzip -c "$src" > "${dst_dir}/${pure_name}" 2>&1 && \
                    echo "  ✓ Decompressed: $pure_name" || \
                    echo "  ✗ Failed to decompress: $module_name"
                ;;
            *.ko.xz)
                pure_name="${module_name%.ko.xz}.ko"
                echo "  Decompressing: $module_name → $pure_name"
                if command -v xz &> /dev/null; then
                    xz -d -c "$src" > "${dst_dir}/${pure_name}" 2>&1 && \
                        echo "  ✓ Decompressed: $pure_name" || \
                        echo "  ✗ Failed to decompress: $module_name"
                else
                    echo "  ✗ xz not available, copying compressed: $module_name"
                    cp -v "$src" "${dst_dir}/${module_name}"
                fi
                ;;
            *.ko.bz2)
                pure_name="${module_name%.ko.bz2}.ko"
                echo "  Decompressing: $module_name → $pure_name"
                if command -v bzip2 &> /dev/null; then
                    bzip2 -d -c "$src" > "${dst_dir}/${pure_name}" 2>&1 && \
                        echo "  ✓ Decompressed: $pure_name" || \
                        echo "  ✗ Failed to decompress: $module_name"
                else
                    echo "  ✗ bzip2 not available, copying compressed: $module_name"
                    cp -v "$src" "${dst_dir}/${module_name}"
                fi
                ;;
            *.ko)
                cp -v "$src" "${dst_dir}/${module_name}"
                echo "  ✓ Copied: $module_name"
                ;;
            *)
                cp -v "$src" "${dst_dir}/${module_name}"
                echo "  ✓ Copied (unknown format): $module_name"
                ;;
        esac
        echo "$pure_name"
    }
    echo "Searching for VSOCK modules..."

    VSOCK_FILES=$(find "$HOST_MODULES" -type f \( \
        -iname "*vsock*" -o \
        -iname "*virtio*" \
        \) 2>/dev/null)
    
    if [ -z "$VSOCK_FILES" ]; then
        echo "⚠ No VSOCK modules found!"
    else
        echo "$VSOCK_FILES" | while read module_path; do
            rel_dir=$(dirname "${module_path#${HOST_MODULES}/}")
            dst_dir="${TARGET_MODULES}/${rel_dir}"
            
            echo ""
            echo "Found: $module_path"
            copy_and_decompress_module "$module_path" "$dst_dir"
        done
    fi

    echo ""
    echo "Handling module dependencies..."

    for dep_file in modules.dep modules.order modules.builtin modules.builtin.modinfo modules.softdep; do
        if [ -f "${HOST_MODULES}/${dep_file}" ]; then
            cp -v "${HOST_MODULES}/${dep_file}" "${TARGET_MODULES}/${dep_file}"
        fi
    done

    if command -v depmod &> /dev/null; then
        echo "Regenerating module dependencies with depmod..."
        depmod -b "${ROOTFS_DIR}" "$KERNEL_VER" 2>&1 | sed 's/^/  /'
        echo "✓ Module dependencies regenerated"
    else
        echo "⚠ depmod not available, using original dependency files"

        if [ ! -f "${TARGET_MODULES}/modules.dep" ]; then
            echo "Creating basic modules.dep..."
            cat > "${TARGET_MODULES}/modules.dep" << 'MODDEP'
kernel/net/vmw_vsock/vsock.ko:
kernel/net/vmw_vsock/vmw_vsock_virtio_transport_common.ko: kernel/net/vmw_vsock/vsock.ko
kernel/net/vmw_vsock/vmw_vsock_virtio_transport.ko: kernel/net/vmw_vsock/vmw_vsock_virtio_transport_common.ko kernel/net/vmw_vsock/vsock.ko
kernel/net/vmw_vsock/hv_sock.ko: kernel/net/vmw_vsock/vsock.ko
kernel/net/vmw_vsock/vmw_vsock_vmci_transport.ko: kernel/net/vmw_vsock/vsock.ko
kernel/net/vmw_vsock/vsock_loopback.ko: kernel/net/vmw_vsock/vsock.ko
kernel/net/vmw_vsock/vsock_diag.ko: kernel/net/vmw_vsock/vsock.ko
MODDEP
        fi
    fi

    echo ""
    echo "========================================"
    echo "  VSOCK Module Collection Summary"
    echo "========================================"
    echo "All modules in rootfs:"
    find "${TARGET_MODULES}" -name "*.ko" -type f | sort
    
    echo ""
    echo "VSOCK modules:"
    find "${TARGET_MODULES}" -name "*vsock*" -type f | sort
    
    echo ""
    echo "Critical module check:"
    check_critical() {
        local pattern=$1
        local desc=$2
        local count=$(find "${TARGET_MODULES}" -name "$pattern" -type f 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            echo "  ✓ $desc (found $count)"
        else
            echo "  ✗ $desc - NOT FOUND"
        fi
    }
    
    check_critical "vsock.ko" "VSOCK core module"
    check_critical "*virtio_transport_common*" "Virtio transport common"
    check_critical "*virtio_transport.ko" "Virtio transport"
    check_critical "*vsock_loopback*" "VSOCK loopback"
    check_critical "*hv_sock*" "Hyper-V VSOCK"
    
    echo ""
    echo "VSOCK module collection complete."
}

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
                echo "  ✓ Copying TDX lib: $lib_name"
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
        echo "⚠ No TDX libraries found. If TDX is needed, please install TDX SDK first."
    fi
}


mkdir -p "${ROOTFS_DIR}/bin"
mkdir -p "${ROOTFS_DIR}/lib/modules"
mkdir -p "${ROOTFS_DIR}/usr/lib"
mkdir -p "${ROOTFS_DIR}/dev"
mkdir -p "${OUTPUT_DIR}"

rm intel-sgx-deb.key*
echo 'deb [signed-by=/etc/apt/keyrings/intel-sgx-keyring.asc arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu noble main' | tee /etc/apt/sources.list.d/intel-sgx.list
wget --no-check-certificate https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key
mkdir -p /etc/apt/keyrings
cat intel-sgx-deb.key | tee /etc/apt/keyrings/intel-sgx-keyring.asc > /dev/null
apt-get update
apt install -y libtdx-attest libtdx-attest-dev
make /opt/intel/tdx-quote-generation-sample/
cp /opt/intel/tdx-quote-generation-sample/test_tdx_attest "${ROOTFS_DIR}/bin/test_tdx_attest"

collect_vsock_modules
collect_tdx_libs

mkdir -p "${ROOTFS_DIR}/.host_deps"
echo "DONE" > "${ROOTFS_DIR}/.host_deps/ready"

echo ""
echo "============================================"
echo "  Host Dependencies Collected Successfully"
echo "============================================"