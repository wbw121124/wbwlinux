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
export NEOVIM_URL=https://github.com/neovim/neovim/archive/refs/tags
export NVIM_VER=0.12.5
# vimcdoc (yianwillis/vimcdoc, pinned): Chinese translations of the Vim help
# (*.cnx + tags-cn). Installed into BOTH nvim and vim runtime doc dirs;
# selected via 'helplang=cn' (root cause #55).
export VIMCDOC_COMMIT=bc2469b2752c9e2d89beca07d0c7faab4e1f1869
# cmake standalone binary (needed to build neovim from source; Arch closure
# does not include cmake since it is a build-time-only dep)
export CMAKE_VER=3.31.6
# Lua 5.1 (neovim cmake needs Lua 5.1 interpreter; built from source before
# neovim because Arch closure is imported later in 06-xorg-xfce.sh)
export LUA_VER=5.1.5
# NetworkManager (prebuilt from Arch repo; pacman 7.1 needs it for Wi-Fi)
export NM_VER=1.58.1
# VS Code (prebuilt from Microsoft; not installed by default)
export VSCODE_VER=1.134.0
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
# man-pages-zh: Debian prebuilt data-only package (upstream 1.6.x builds need
# cmake+opencc which the chroot lacks; the deb ships converted simplified pages)
export MANPAGES_ZH_VER=1.6.4.5-1

# pacman package manager stack (ninja+meson are pacman's build deps;
# curl+libarchive are its runtime deps). Versions verified via GitHub API
# / gitlab release pages on 2026-08-22.
export NINJA_VER=1.13.2
export MESON_VER=1.12.0
export CURL_VER=8.21.0
export LIBARCHIVE_VER=3.8.9
export PACMAN_VER=7.1.0

# CLI tool bundle: fd/ripgrep/bat ship official musl STATIC binaries
# (zero compilation, zero runtime deps); htop is a tiny source build (the
# Debian deb links plain libtinfo which LFS ncurses does not provide);
# wget is absent from LFS ch8 and Debian's build links gnutls which we
# lack, so it is a tiny source build against openssl.
# Versions verified against upstream releases on 2026-08-23.
export FD_VER=10.4.2
export RIPGREP_VER=15.2.0
export BAT_VER=0.26.1
export HTOP_VER=3.5.3
export WGET_VER=1.25.0

# sudo (privilege escalation for non-root users on the live system)
# Version verified against https://www.sudo.ws/releases/stable/ on 2026-08-24
export SUDO_VER=1.9.17p2

# git (version control for live system)
export GIT_VER=2.55.0

# Firefox (prebuilt binary from Mozilla; packaged but not installed by default)
export FIREFOX_VER=154.0

# Rea-Dark XFCE theme (GTK2 + GTK3 + xfwm4)
# Pinned to commit 1a422b0ec86e9fc6d349d17a770d933dbf2c00f8 (2026-02-24)
export REA_COMMIT=1a422b0ec86e9fc6d349d17a770d933dbf2c00f8

# Yaru theme (Ubuntu 26.04 LTS) - full GTK2/GTK3/GTK4/icons/cursor/shell
export YARU_VER=26.04.5
# sassc (libsass compiler): Yaru 26.04 meson requires the sassc program
# unconditionally (root cause #57). Built from source via their plain
# Makefiles + SASS_LIBSASS_PATH (no autotools needed).
export LIBSASS_VER=3.6.6
export SASSC_VER=3.6.3.1ubuntu
export YARU_COMMIT=f01c3e9a257296242806f8e0c5d4a660516f2181
export YARU_TARBALL="yaru-${YARU_VER}.tar.gz"

# kmscon (KMS/DRM userspace console, Phase 1 of the fbterm replacement):
# tty2-6 graphical consoles; tty1 stays fbterm-zh until Phase 3.
export KMSCON_VER=v10.0.2
export LIBTSM_VER=v4.7.1
export KMSCON_TARBALL="kmscon-${KMSCON_VER}.tar.gz"
export LIBTSM_TARBALL="libtsm-${LIBTSM_VER}.tar.gz"

# CA trust store: the ISO ships no certificates, so every TLS client
# silently relied on `curl -k`; pacman cannot skip verification
# (root cause #59). Mozilla-derived bundle from curl.se.
export CACERT_URL="https://curl.se/ca/cacert.pem"

# Arch binary stack (X.Org + XFCE) imported from repo databases at build
# time by chroot/06-xorg-xfce.sh; rolling release, pinned per run only.
export ARCH_MIRRORS="https://geo.mirror.pkgbuild.com https://mirror.rackspace.com/archlinux https://mirrors.kernel.org/archlinux"

# Host side of the chroot filesystems
export KERNFS="proc sys run dev"
