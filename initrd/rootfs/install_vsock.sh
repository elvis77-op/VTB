#!/bin/bash

# Script to install VSOCK modules in initrd
# Automatically detects module locations and compression formats

set -e  # Exit on any error

# Configuration
GUEST_ROOT_MOUNT="/mnt/guest-root"
GUEST_DEVICE="/dev/vda1"
KERNEL_VERSION=$(uname -r)
MODULE_BASE_PATH="/lib/modules/${KERNEL_VERSION}"

# Function to log messages
log() {
    echo "[VSOCK-SETUP] $1"
}

# Function to check if device exists
check_device() {
    if [ ! -b "$GUEST_DEVICE" ]; then
        log "ERROR: Guest device $GUEST_DEVICE not found"
        return 1
    fi
}

# Function to mount guest root
mount_guest_root() {
    log "Creating mount point and mounting guest root..."
    mkdir -p "$GUEST_ROOT_MOUNT"
    
    if ! mount -o ro "$GUEST_DEVICE" "$GUEST_ROOT_MOUNT"; then
        log "ERROR: Failed to mount $GUEST_DEVICE"
        return 1
    fi
    
    log "Successfully mounted guest root"
}

# Function to copy and decompress module
copy_and_decompress_module() {
    local src="$1"
    local dst_dir="$2"
    local module_name=$(basename "$src")
    local pure_name="$module_name"
    
    mkdir -p "$dst_dir"
    
    log "Processing: $module_name"
    
    # Handle different compression formats
    case "$module_name" in
        *.ko.zst)
            pure_name="${module_name%.ko.zst}.ko"
            log "  Decompressing zst: $module_name → $pure_name"
            if command -v zstd >/dev/null 2>&1; then
                if zstd -d "$src" -o "${dst_dir}/${pure_name}"; then
                    log "  ✓ Decompressed: $pure_name"
                else
                    log "  ✗ Failed to decompress: $module_name"
                    return 1
                fi
            else
                log "  ✗ zstd not available, copying compressed: $module_name"
                cp "$src" "${dst_dir}/${module_name}"
                pure_name="$module_name"
            fi
            ;;
        *.ko)
            # Uncompressed module, copy directly
            cp "$src" "${dst_dir}/${module_name}"
            log "  ✓ Copied: $module_name"
            ;;
        *)
            # Unknown format, copy as-is
            cp "$src" "${dst_dir}/${module_name}"
            log "  ✓ Copied (unknown format): $module_name"
            ;;
    esac
    
    echo "$pure_name"
}

# Function to load module with dependency handling
load_module_safe() {
    local module_path="$1"
    local module_name=$(basename "$module_path" .ko)
    
    # Check if already loaded
    if lsmod | grep -q "^${module_name} "; then
        log "Module $module_name already loaded"
        return 0
    fi
    
    log "Loading module: $module_name"
    if insmod "$module_path"; then
        log "  ✓ Loaded: $module_name"
        return 0
    else
        log "  ✗ Failed to load: $module_name"
        return 1
    fi
}

# Function to install VSOCK modules
install_vsock_modules() {
    log "========================================"
    log "  Installing VSOCK Kernel Modules"
    log "========================================"
    
    local host_modules="$GUEST_ROOT_MOUNT/lib/modules/$KERNEL_VERSION"
    
    if [ ! -d "$host_modules" ]; then
        log "ERROR: Host modules directory not found: $host_modules"
        return 1
    fi
    
    log "Searching for VSOCK modules..."
    
    # Create /tmp directory if it doesn't exist
    mkdir -p /tmp
    
    # Find all VSOCK and virtio related modules
    local vsock_files=$(find "$host_modules" -type f \( \
        -iname "*vsock*" -o \
        -iname "*virtio*" \
        \) 2>/dev/null)
    
    if [ -z "$vsock_files" ]; then
        log "⚠ No VSOCK modules found!"
        return 1
    fi
    
    # Process each found module
    echo "$vsock_files" | while read module_path; do
        if [ -f "$module_path" ]; then
            # Get relative path from guest root modules directory
            local rel_path="${module_path#${host_modules}/}"
            # Create destination directory in local filesystem
            local dst_dir="${MODULE_BASE_PATH}/$(dirname "$rel_path")"
            
            log "Found: $module_path"
            log "  Destination: $dst_dir"
            
            # Create destination directory
            mkdir -p "$dst_dir"
            
            # Copy and decompress module
            local pure_name=$(copy_and_decompress_module "$module_path" "$dst_dir")
            
            # Store full path for loading
            echo "${dst_dir}/${pure_name}" >> /tmp/vsock_modules_list
        fi
    done
    
    # Load modules in dependency order
    log "Loading VSOCK modules..."
    
    # Define loading order (dependencies first)
    local load_order="vsock.ko vmw_vsock_virtio_transport_common.ko vmw_vsock_virtio_transport.ko vsock_loopback.ko hv_sock.ko vmw_vsock_vmci_transport.ko vsock_diag.ko"
    
    # Load modules in order if they exist
    for module_name in $load_order; do
        local module_path=$(find "$MODULE_BASE_PATH" -name "$module_name" -type f 2>/dev/null | head -1)
        if [ -n "$module_path" ]; then
            load_module_safe "$module_path" || true  # Continue even if loading fails
        fi
    done
    
    # Load any remaining VSOCK modules not in the ordered list
    if [ -f /tmp/vsock_modules_list ]; then
        while read module_path; do
            if [ -f "$module_path" ]; then
                local module_name=$(basename "$module_path")
                # Skip if already in load_order
                local skip=false
                for ordered_module in $load_order; do
                    if [ "$module_name" = "$ordered_module" ]; then
                        skip=true
                        break
                    fi
                done
                
                if [ "$skip" = false ]; then
                    load_module_safe "$module_path" || true
                fi
            fi
        done < /tmp/vsock_modules_list
        rm -f /tmp/vsock_modules_list
    fi
}

# Function to verify VSOCK installation
verify_vsock_installation() {
    log "========================================"
    log "  VSOCK Installation Verification"
    log "========================================"
    
    # Check for VSOCK device nodes
    local vsock_devices=$(ls /dev/vsock* 2>/dev/null || true)
    if [ -n "$vsock_devices" ]; then
        log "✓ VSOCK devices found:"
        echo "$vsock_devices" | while read dev; do
            log "  $dev"
            ls -l "$dev"
        done
    else
        log "⚠ No VSOCK devices found in /dev/"
    fi
    
    # Check loaded modules
    log "Loaded VSOCK modules:"
    local loaded_vsock=$(lsmod | grep -i vsock || true)
    if [ -n "$loaded_vsock" ]; then
        echo "$loaded_vsock" | while read line; do
            log "  ✓ $line"
        done
    else
        log "  ⚠ No VSOCK modules loaded"
    fi
    
    # Check for virtio modules
    log "Loaded virtio modules:"
    local loaded_virtio=$(lsmod | grep -i virtio || true)
    if [ -n "$loaded_virtio" ]; then
        echo "$loaded_virtio" | while read line; do
            log "  ✓ $line"
        done
    else
        log "  ⚠ No virtio modules loaded"
    fi
    
    # Check critical modules
    log "Critical module check:"
    check_critical_module() {
        local pattern=$1
        local desc=$2
        if lsmod | grep -q "$pattern"; then
            log "  ✓ $desc - LOADED"
        else
            log "  ✗ $desc - NOT LOADED"
        fi
    }
    
    check_critical_module "vsock" "VSOCK core module"
    check_critical_module "virtio_transport" "Virtio transport"
    check_critical_module "vsock_loopback" "VSOCK loopback"
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."
    rm -f /tmp/vsock_modules_list
    if mountpoint -q "$GUEST_ROOT_MOUNT" 2>/dev/null; then
        umount "$GUEST_ROOT_MOUNT" 2>/dev/null || true
    fi
    rmdir "$GUEST_ROOT_MOUNT" 2>/dev/null || true
}

# Main execution
main() {
    log "Starting VSOCK module installation..."
    log "Kernel version: $KERNEL_VERSION"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Check prerequisites
    local missing_tools=""
    command -v zstd >/dev/null 2>&1 || missing_tools="$missing_tools zstd"
    command -v xz >/dev/null 2>&1 || missing_tools="$missing_tools xz"
    command -v bzip2 >/dev/null 2>&1 || missing_tools="$missing_tools bzip2"
    
    if [ -n "$missing_tools" ]; then
        log "WARNING: Missing decompression tools:$missing_tools"
        log "Compressed modules with these formats will be copied as-is"
    fi
    
    # Execute installation steps
    check_device
    mount_guest_root
    install_vsock_modules
    verify_vsock_installation
    
    log "VSOCK module installation completed"
}

# Run main function
main "$@"
