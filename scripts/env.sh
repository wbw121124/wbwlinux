# LFS-CN build environment
# Shared by all stage scripts and the GitHub Actions workflow.

set -euo pipefail

export LFS_ROOT=/mnt/lfs
export LFS_TGT="$(uname -m)-lfs-linux-gnu"
export LFS_VERSION=13.0-systemd
export LFS_DISTRO_NAME="LFS-CN"
export LFS_KERNEL_VER=6.18.10

export SOURCES="$LFS_ROOT/sources"
export SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export STAGES_DIR="$SCRIPTS_DIR/stages"
export CONFIG_DIR="$(dirname "$SCRIPTS_DIR")/config"

# Parallelism: GitHub hosted runners have 2 vCPUs; oversubscribe by one
export NPROC="$(nproc)"
export MAKEFLAGS="-j$((NPROC >= 2 ? NPROC + 1 : NPROC))"

# Package versions for extras (BLFS 13.0 / upstream binaries)
export NODE_VER=v24.19.0
export RUST_VER=1.93.1
export NANO_VER=8.7.1
export ICU_VER=78.2
export FREETYPE_VER=2.14.1
export FONTCONFIG_VER=2.17.1

# Download roots
export LFS_BOOK_URL=https://www.linuxfromscratch.org/lfs/downloads/13.0-systemd
export NODE_URL=https://nodejs.org/dist/$NODE_VER
export RUST_URL=https://static.rust-lang.org/dist
export POWERSHELL_URL=https://github.com/PowerShell/PowerShell/releases/download
export NEOVIM_URL=https://github.com/neovim/neovim/releases/download
export ICU_URL=https://github.com/unicode-org/icu/releases/download/release-78.2

# Powershell 7.6.4 (linux-x64 tarball)
export PWSH_VER=7.6.4

# fbterm console input method stack (ucimf) + coding font
export UCIMF_VER=2.3.8
export OV_BRIDGE_VER=2.10.11
export FBTERM_UCIMF_VER=0.2.9
# openvanilla-modules (OVIMGeneric + .cin tables) has no release tarballs;
# pinned to a verified commit of the pkg-ime GitHub snapshot
export OV_MODULES_COMMIT=28d0dd62b710f563d04ee926b548da9cb41a409a
export OV_MODULES_TARBALL="openvanilla-modules-git${OV_MODULES_COMMIT:0:7}.tar.gz"
export FIRACODE_VER=6.2

# Host side of the chroot filesystems
export KERNFS="proc sys run dev"
