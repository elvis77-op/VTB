# Build Environment Setup (Without Docker)

This document describes how to manually reproduce initrd image on a native Ubuntu system.

---

# System Requirements

Recommended OS

- Ubuntu 24.04 LTS
- x86_64

Update package lists

```bash
sudo apt update
```

---

# Install Build Tools

Install the basic build environment.

```bash
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    cpio \
    busybox-static \
    kmod \
    musl-tools
```

These packages provide

- GCC / G++
- CMake
- BusyBox
- CPIO
- Kernel module utilities
- musl compiler

---

# Install gRPC and Protobuf

Install Protobuf and gRPC development libraries.

```bash
sudo apt install -y \
    pkg-config \
    libprotobuf-dev \
    protobuf-compiler \
    protobuf-compiler-grpc \
    libgrpc++-dev \
    libgrpc-dev
```

After installation, verify:

```bash
protoc --version
```

Expected output:

```text
libprotoc xx.x
```

You may also verify the gRPC plugin:

```bash
which grpc_cpp_plugin
```

---

# Install OpenSSL

```bash
sudo apt install -y \
    libssl-dev \
    openssl \
    libssl3
```

Verify:

```bash
openssl version
```

---

# Install Compression Library

```bash
sudo apt install -y zlib1g-dev
```

---

# Install Networking Utilities

```bash
sudo apt install -y \
    iproute2 \
    udhcpc
```

Useful commands:

```bash
ip addr
```

```bash
ip route
```

---

# Install Runtime Utilities

```bash
sudo apt install -y \
    bash \
    ca-certificates
```

---

# Verify gRPC Libraries

You can check whether the shared libraries are installed correctly.

```bash
ls -la /usr/lib/x86_64-linux-gnu/libgrpc++*
```

```bash
ls -la /usr/lib/x86_64-linux-gnu/libgpr*
```

---

# Prepare Project Directory

Assume the project root is

```text
project/
```

Create the required RootFS directories.

```bash
mkdir -p rootfs/bin
mkdir -p rootfs/lib
mkdir -p rootfs/lib64
mkdir -p rootfs/dev
mkdir -p rootfs/proc
mkdir -p rootfs/sys
mkdir -p rootfs/run
```

---

# Prepare Runtime Dependencies

Run the dependency preparation script.

```bash
bash prepare_rootfs_deps.sh "$(pwd)"
```

This script copies the required runtime libraries into the generated root filesystem.

---

# Configure the Project

Generate the build files.

```bash
cmake -S . -B build
```

---

# Build the Initrd

Compile the project.

```bash
cmake --build build --target initrd
```

If the build succeeds, the generated initramfs will be placed in the project's `output` directory.

---

# Clean Previous Build (Optional)

Before rebuilding, remove previously generated files.

```bash
rm -rf build src/build rootfs output
```

---

# Complete Build Workflow

The following commands reproduce the entire Docker build process manually.

```bash
sudo apt update

sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    cpio \
    busybox-static \
    kmod \
    musl-tools \
    pkg-config \
    libprotobuf-dev \
    protobuf-compiler \
    protobuf-compiler-grpc \
    libgrpc++-dev \
    libgrpc-dev \
    libssl-dev \
    zlib1g-dev \
    iproute2 \
    udhcpc \
    bash \
    ca-certificates \
    openssl \
    libssl3

rm -rf build src/build rootfs output

mkdir -p rootfs/bin
mkdir -p rootfs/lib
mkdir -p rootfs/lib64
mkdir -p rootfs/dev
mkdir -p rootfs/proc
mkdir -p rootfs/sys
mkdir -p rootfs/run

bash prepare_rootfs_deps.sh "$(pwd)"

cmake -S . -B build

cmake --build build --target initrd
```

---

# Dependency Explanation

| Package | Purpose |
|---------|---------|
| build-essential | Provides GCC, G++, Make, and other essential compilation tools. |
| cmake | Generates project build files and manages the build process. |
| git | Downloads or updates project source code. |
| wget / curl | Downloads external resources when needed. |
| cpio | Packages the generated root filesystem into an initramfs image. |
| busybox-static | Provides a statically linked BusyBox executable used inside the initramfs. |
| kmod | Supplies utilities for loading and managing Linux kernel modules. |
| musl-tools | Provides the musl compiler toolchain for building lightweight static binaries. |
| pkg-config | Helps CMake locate installed libraries. |
| libprotobuf-dev | Installs the Protocol Buffers development library. |
| protobuf-compiler | Provides the `protoc` compiler for generating source files from `.proto` definitions. |
| protobuf-compiler-grpc | Generates gRPC service stubs from `.proto` files. |
| libgrpc-dev | Installs the core gRPC C library. |
| libgrpc++-dev | Installs the C++ gRPC library used by this project. |
| libssl-dev | Provides OpenSSL headers and libraries required during compilation. |
| openssl | Supplies OpenSSL runtime utilities. |
| libssl3 | Installs the OpenSSL runtime shared libraries. |
| zlib1g-dev | Provides compression support required by several dependencies. |
| iproute2 | Supplies networking utilities such as `ip`. |
| udhcpc | Lightweight DHCP client for network configuration inside initramfs. |
| bash | Shell used by build and helper scripts. |
| ca-certificates | Provides trusted SSL certificates for secure network connections. |