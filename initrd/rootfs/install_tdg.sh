#!/bin/bash

# Script to install TSM and TDX-guest modules in initrd
# Automatically detects module locations and compression

GUEST_ROOT_MOUNT="/mnt/guest-root"
GUEST_DEVICE="/dev/vda1"
KERNEL_VERSION=$(uname -r)
MODULE_BASE_PATH="/lib/modules/${KERNEL_VERSION}"

log() {
    echo "[TDX-SETUP] $1"
}

check_device() {
    if [ ! -b "$GUEST_DEVICE" ]; then
        log "ERROR: Guest device $GUEST_DEVICE not found"
        return 1
    fi
}

mount_guest_root() {
    log "Creating mount point and mounting guest root..."
    mkdir -p "$GUEST_ROOT_MOUNT"
    
    if ! mount -o ro "$GUEST_DEVICE" "$GUEST_ROOT_MOUNT"; then
        log "ERROR: Failed to mount $GUEST_DEVICE"
        return 1
    fi
    
    log "Successfully mounted guest root"
}

# Function to find and extract/copy a module
# Usage: install_module <module_name> <search_pattern>
install_module() {
    local module_name="$1"
    local search_pattern="$2"
    
    log "Looking for $module_name module..."
    
    # Find the source module file
    local source_file=$(find "$GUEST_ROOT_MOUNT/lib/modules/$KERNEL_VERSION" -name "$search_pattern" -type f | head -1)
    
    if [ -z "$source_file" ]; then
        log "ERROR: $module_name module not found with pattern: $search_pattern"
        return 1
    fi
    
    log "Found $module_name at: $source_file"
    
    # Determine destination path (preserve directory structure relative to kernel/)
    local rel_path=$(echo "$source_file" | sed "s|$GUEST_ROOT_MOUNT/lib/modules/$KERNEL_VERSION/||")
    local dest_dir="$MODULE_BASE_PATH/$(dirname "$rel_path")"
    local dest_file="$dest_dir/$(basename "$source_file" | sed 's/\.zst$//')"
    
    # Create destination directory
    mkdir -p "$dest_dir"
    
    # Check if source is compressed (.zst)
    if [[ "$source_file" == *.zst ]]; then
        log "Extracting compressed $module_name module..."
        if ! zstd -d "$source_file" -o "$dest_file"; then
            log "ERROR: Failed to extract $module_name module"
            return 1
        fi
    else
        log "Copying uncompressed $module_name module..."
        if ! cp "$source_file" "$dest_file"; then
            log "ERROR: Failed to copy $module_name module"
            return 1
        fi
    fi
    
    log "Loading $module_name module..."
    if ! insmod "$dest_file"; then
        log "ERROR: Failed to load $module_name module"
        return 1
    fi
    
    log "$module_name module loaded successfully"
    return 0
}

# Function to verify installation
verify_installation() {
    log "Verifying installation..."
    
    if [ -c "/dev/tdx_guest" ]; then
        log "SUCCESS: /dev/tdx_guest device created"
        ls -l /dev/tdx_guest
    else
        log "WARNING: /dev/tdx_guest device not found"
        return 1
    fi
    
    # Check if modules are loaded
    if lsmod | grep -q "tsm"; then
        log "TSM module is loaded"
    else
        log "WARNING: TSM module not found in lsmod"
    fi
    
    if lsmod | grep -q "tdx_guest"; then
        log "TDX-guest module is loaded"
    else
        log "WARNING: TDX-guest module not found in lsmod"
    fi
}

# Function to cleanup
cleanup() {
    log "Cleaning up..."
    if mountpoint -q "$GUEST_ROOT_MOUNT" 2>/dev/null; then
        umount "$GUEST_ROOT_MOUNT" 2>/dev/null || true
    fi
    rmdir "$GUEST_ROOT_MOUNT" 2>/dev/null || true
}

# Main execution
main() {
    log "Starting TDX module installation..."
    log "Kernel version: $KERNEL_VERSION"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Check prerequisites
    if ! command -v zstd >/dev/null 2>&1; then
        log "WARNING: zstd command not found - compressed modules will fail"
    fi
    
    # Execute installation steps
    check_device
    mount_guest_root
    
    # Install TSM module first (dependency)
    install_module "TSM" "*tsm*"
    
    # Install TDX-guest module
    install_module "TDX-guest" "*tdx-guest*"
    
    verify_installation
    
    log "TDX module installation completed successfully"
}

# Run main function
main "$@"
}
