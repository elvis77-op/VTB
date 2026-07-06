#!/bin/bash

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH

PROJECT_ROOT="${1:?Usage: $0 <PROJECT_ROOT>}"
ROOTFS_DIR="${PROJECT_ROOT}/rootfs"
OUTPUT_DIR="${PROJECT_ROOT}/output"

echo "=== Packing Initrd into CPIO ==="
collect_all_libs() {
    local binary="$1"
    local processed_libs="$2"

    local libs=$(LD_LIBRARY_PATH="${ROOTFS_DIR}/lib:${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib/x86_64-linux-gnu:${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu" \
                 ldd "$binary" 2>/dev/null | grep "=> /" | awk '{print $3}')
    
    for lib in $libs; do
        if [ -z "$lib" ] || [ ! -f "$lib" ]; then
            continue
        fi

        if echo "$processed_libs" | grep -q "$lib"; then
            continue
        fi
        processed_libs="$processed_libs $lib"

        if echo "$lib" | grep -q "${ROOTFS_DIR}"; then
            continue
        fi
        
        local target_dir="${ROOTFS_DIR}$(dirname "$lib")"
        mkdir -p "$target_dir"
        
        if [ ! -f "${target_dir}/$(basename "$lib")" ]; then
            cp -v "$lib" "$target_dir/"
            echo " $(basename "$lib")"
        fi
        
        collect_all_libs "$lib" "$processed_libs"
    done
}

collect_binary_deps() {
    echo ""
    echo "========================================"
    echo "  Collecting Binary Dependencies"
    echo "========================================"

    mkdir -p "${ROOTFS_DIR}/lib/x86_64-linux-gnu"
    mkdir -p "${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu"
    mkdir -p "${ROOTFS_DIR}/bin"
    
    local BINARIES=(
        "${ROOTFS_DIR}/bin/attestation_client"
        "${ROOTFS_DIR}/bin/attestation_server"
        "${ROOTFS_DIR}/bin/socat"
        "${ROOTFS_DIR}/bin/test_tdx_attest"
    )
    
    echo "Collecting dynamic linker..."
    local INTERP="/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
    if [ -f "$INTERP" ]; then
        mkdir -p "${ROOTFS_DIR}/lib/x86_64-linux-gnu"
        cp -v "$INTERP" "${ROOTFS_DIR}/lib/x86_64-linux-gnu/"
    fi
   
    for binary in "${BINARIES[@]}"; do
        if [ ! -f "$binary" ]; then
            echo "⚠ Binary not found: $binary (skipping)"
            continue
        fi
        
        echo ""
        echo "=== Processing: $(basename "$binary") ==="
      
        if ! echo "$binary" | grep -q "${ROOTFS_DIR}"; then
            cp -v "$binary" "${ROOTFS_DIR}/bin/"
            binary="${ROOTFS_DIR}/bin/$(basename "$binary")"
        fi
        
        export LD_LIBRARY_PATH="${ROOTFS_DIR}/lib:${ROOTFS_DIR}/usr/lib:${ROOTFS_DIR}/lib/x86_64-linux-gnu:${ROOTFS_DIR}/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu"
        
        echo "Dependencies:"
        ldd "$binary" 2>/dev/null | grep "=> /"

        collect_all_libs "$binary" ""
        
        unset LD_LIBRARY_PATH
    done
    
    echo ""
    echo "=== Processing: busybox ==="
    if command -v busybox &>/dev/null; then
        BUSYBOX_PATH=$(which busybox)
        cp -v "$BUSYBOX_PATH" "${ROOTFS_DIR}/bin/"
        
        ldd "$BUSYBOX_PATH" 2>/dev/null | grep -q "not a dynamic" && echo "  (static binary, no deps needed)" || {
            export LD_LIBRARY_PATH="${ROOTFS_DIR}/lib:${ROOTFS_DIR}/usr/lib"
            collect_all_libs "$BUSYBOX_PATH" ""
            unset LD_LIBRARY_PATH
        }
    else
        echo "BusyBox not found!"
        exit 1
    fi
    
    echo ""
    echo "=== Libraries in rootfs ==="
    find "${ROOTFS_DIR}" -name "*.so*" -type f | sort
}

create_busybox_symlinks() {
    echo ""
    echo "=== Creating BusyBox Symlinks ==="
    
    cd ${ROOTFS_DIR}/bin
    for cmd in sh mount mkdir mknod cat ls cp mv rm ln grep sed ash; do
        ln -sf busybox $cmd 2>/dev/null || true
    done
    cd ${ROOTFS_DIR}
    
    echo "BusyBox symlinks created"
}

pack_cpio() {
    echo ""
    echo "=== Generating CPIO Archive ==="
    
    cd ${ROOTFS_DIR}
    mkdir -p ${OUTPUT_DIR}
    
    find . | cpio -H newc -o | gzip -9 > ${OUTPUT_DIR}/initramfs.cpio.gz
    cp bin/attestation_server ${OUTPUT_DIR}/attestation_server
    
    echo ""
    echo "============================================"
    echo "  SUCCESS!"
    echo "============================================"
    echo "Initrd created at: ${OUTPUT_DIR}/initramfs.cpio.gz"
    echo "Size: $(du -h ${OUTPUT_DIR}/initramfs.cpio.gz | cut -f1)"
}

mkdir -p ${ROOTFS_DIR}/bin
mkdir -p ${ROOTFS_DIR}/lib
mkdir -p ${ROOTFS_DIR}/usr/lib

echo ""
echo "=== Fixing Dynamic Linker ==="

LINKER_SRC="/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
LINKER_DST_DIR="${ROOTFS_DIR}/lib/x86_64-linux-gnu"

if [ -f "$LINKER_SRC" ]; then
    mkdir -p "$LINKER_DST_DIR"
    cp -v "$LINKER_SRC" "$LINKER_DST_DIR/"
    echo " Linker copied to /lib/x86_64-linux-gnu/"
else
    LINKER_SRC="/lib64/ld-linux-x86-64.so.2"
    if [ -f "$LINKER_SRC" ]; then
        mkdir -p "${ROOTFS_DIR}/lib64"
        cp -v "$LINKER_SRC" "${ROOTFS_DIR}/lib64/"
    fi
fi

mkdir -p "${ROOTFS_DIR}/lib64"
ln -sf ../lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 "${ROOTFS_DIR}/lib64/ld-linux-x86-64.so.2" 2>/dev/null
echo " Created /lib64 symlink"

if [ -f "${ROOTFS_DIR}/lib64/ld-linux-x86-64.so.2" ]; then
    echo " Linker accessible at /lib64/ld-linux-x86-64.so.2"
else
    echo " Linker symlink failed!"
fi

collect_binary_deps
create_busybox_symlinks
pack_cpio

