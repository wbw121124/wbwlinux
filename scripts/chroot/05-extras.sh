#!/usr/bin/env bash
# Runs INSIDE the LFS chroot. Installs prebuilt Node.js/Rust/PowerShell/
# Neovim, source-builds ICU, nano, freetype, fontconfig, fbterm, installs
# CJK fonts and Chinese-friendly editor configs.
# All tarballs were downloaded by the host into /root/downloads.
set -euo pipefail
export PATH="/usr/local/bin:/opt/rust/bin:$PATH"
export SOURCES=/sources
export SCRIPTS_DIR=/build
export STAGES_DIR=/build/stages
export CONFIG_DIR=/config
source /build/env.sh
source /build/common.sh

DL=/root/downloads
cd "$DL"

# =====================================================================
# which(1): nothing in LFS provides it (util-linux dropped it ages ago
# and no ch8 package ships it), but scripts and interactive users both
# expect it. Minimal POSIX implementation, exit 0 iff something matched.
# =====================================================================
if [ ! -e /usr/bin/which ]; then
    log '==> installing minimal which(1)'
    cat > /usr/bin/which << 'EOF'
#!/bin/sh
# which: locate a command in PATH; prints every match, exit 0 if any.
found=1
for name in "$@"; do
    case "$name" in
    */*) [ -f "$name" ] && [ -x "$name" ] && { printf '%s\n' "$name"; found=0; } ;;
    *)   savedIFS=$IFS; IFS=:
         for dir in $PATH; do
             if [ -f "$dir/$name" ] && [ -x "$dir/$name" ]; then
                 printf '%s\n' "$dir/$name"
                 found=0
             fi
         done
         IFS=$savedIFS ;;
    esac
done
exit $found
EOF
    chmod 755 /usr/bin/which
    which bash
fi

# =====================================================================
# Node.js (official prebuilt, x86_64)
# =====================================================================
if [ ! -e /usr/local/bin/node ]; then
    log "==> Node.js $NODE_VER"
    tar xf "node-$NODE_VER-linux-x64.tar.xz" -C /usr/local \
        --transform='s,^node-v[0-9.]*-linux-x64,lib/nodejs,'
    ln -sfv ../lib/nodejs/bin/node /usr/local/bin/node
    ln -sfv ../lib/nodejs/bin/npm /usr/local/bin/npm
    ln -sfv ../lib/nodejs/bin/npx /usr/local/bin/npx
    node --version
fi

# =====================================================================
# Rust (official full toolchain, x86_64: rustc+cargo+rust-std+rustfmt...)
# =====================================================================
if [ ! -e /opt/rust/bin/rustc ]; then
    log "==> Rust $RUST_VER"
    mkdir -p /opt/rust
    tar xf "rust-$RUST_VER-x86_64-unknown-linux-gnu.tar.xz" -C /opt/rust --strip-components=2
    for t in rustc cargo rustdoc rustfmt cargo-fmt clippy-driver cargo-clippy rust-analyzer; do
        if [ -e "/opt/rust/bin/$t" ] && [ ! -e "/usr/local/bin/$t" ]; then
            ln -sfv "/opt/rust/bin/$t" "/usr/local/bin/$t"
        fi
    done
    if [ -e /opt/rust/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld ]; then
        ln -sfv /opt/rust/lib/rustlib/x86_64-unknown-linux-gnu/bin/rust-lld /usr/local/bin/rust-lld
    fi
    /opt/rust/bin/rustc --version
fi

# =====================================================================
# libunwind (needed by PowerShell/.NET Core)
# =====================================================================
if [ ! -e /usr/lib/libunwind.so.8 ]; then
    log "==> libunwind 1.6.2"
    tar xf libunwind-1.6.2.tar.gz
    cd libunwind-1.6.2
    ./configure --prefix=/usr --disable-static
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf libunwind-1.6.2
fi

# =====================================================================
# ICU 78.2 (source build; needed by PowerShell)
# =====================================================================
if [ ! -e /usr/lib/libicuuc.so.78 ]; then
    log "==> ICU $ICU_VER"
    tar xf "icu4c-$ICU_VER-sources.tgz"
    cd icu/source
    ./configure --prefix=/usr
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf icu
fi

# =====================================================================
# PowerShell (official tarball)
# =====================================================================
if [ ! -e /opt/microsoft/powershell/7/pwsh ]; then
    log "==> PowerShell $PWSH_VER"
    mkdir -p /opt/microsoft/powershell/7
    tar xf "powershell-$PWSH_VER-linux-x64.tar.gz" \
        -C /opt/microsoft/powershell/7
    ln -sfv /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
    chmod +x /opt/microsoft/powershell/7/pwsh
    pwsh --version
fi

# =====================================================================
# Neovim 0.12.5 (source build, installs to /usr/local)
# cmake 3.31.6 (standalone binary, used only for nvim build then removed)
# Lua 5.1 (built from source, neovim cmake needs Lua 5.1 interpreter)
# =====================================================================
if [ ! -e /usr/local/bin/nvim ]; then
    log "==> Neovim $NVIM_VER (source build)"

    # Install cmake standalone binary (build-only dependency)
    log "    installing cmake $CMAKE_VER (standalone, build-only)"
    tar xf "cmake-$CMAKE_VER-linux-x86_64.tar.gz" -C /opt

    # Build Lua 5.1 (neovim needs Lua 5.1 interpreter; Arch closure not yet imported)
    log "    building Lua $LUA_VER"
    tar xf "lua-$LUA_VER.tar.gz"
    cd "lua-$LUA_VER"
    make linux -j"$NPROC"
    make install INSTALL_TOP=/usr/local
    cd "$DL"
    rm -rf "lua-$LUA_VER"
    ldconfig
    lua -v

    # Build neovim via its Makefile: it orchestrates the bundled-deps
    # project (cmake.deps -> .deps: libuv/luv/luajit/lpeg/treesitter/…)
    # FIRST, then configures+builds the main tree against them. Raw
    # "cmake -B build" fails at configure time with FindLuv because deps
    # do not exist yet (root cause #37).
    tar xf "nvim-$NVIM_VER.tar.gz"
    cd "neovim-$NVIM_VER"
    export PATH="/opt/cmake-$CMAKE_VER-linux-x86_64/bin:$PATH"
    make -j"$NPROC" CMAKE_BUILD_TYPE=RelWithDebInfo \
         CMAKE_INSTALL_PREFIX=/usr/local
    make CMAKE_INSTALL_PREFIX=/usr/local install
    cd "$DL"
    rm -rf "neovim-$NVIM_VER"

    # Remove cmake (was build-only)
    log "    removing cmake $CMAKE_VER (was build-only)"
    rm -rf "/opt/cmake-$CMAKE_VER-linux-x86_64"

    nvim --version | head -1
    log "==> Neovim $NVIM_VER OK (source build to /usr/local)"
fi

# =====================================================================
# nano (source build, UTF-8 enabled)
# =====================================================================
if [ ! -e /usr/bin/nano ]; then
    log "==> nano $NANO_VER"
    tar xf "nano-$NANO_VER.tar.xz"
    cd "nano-$NANO_VER"
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --enable-utf8 \
                --docdir=/usr/share/doc/nano-$NANO_VER
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "nano-$NANO_VER"
fi

# =====================================================================
# freetype (needed by fontconfig/fbterm)
# =====================================================================
if [ ! -e /usr/lib/libfreetype.so.6 ]; then
    log "==> freetype $FREETYPE_VER"
    tar xf "freetype-$FREETYPE_VER.tar.xz"
    cd "freetype-$FREETYPE_VER"
    sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg
    sed -ri "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" include/freetype/config/ftoption.h
    ./configure --prefix=/usr --enable-freetype-config --disable-static
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "freetype-$FREETYPE_VER"
fi

# =====================================================================
# fontconfig
# =====================================================================
if [ ! -e /usr/lib/libfontconfig.so.1 ]; then
    log "==> fontconfig $FONTCONFIG_VER"
    tar xf "fontconfig-$FONTCONFIG_VER.tar.xz"
    cd "fontconfig-$FONTCONFIG_VER"
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --disable-docs \
                --docdir=/usr/share/doc/fontconfig-$FONTCONFIG_VER
    make -j"$NPROC"
    make install
    install -v -dm755 /usr/share/{man/man{1,3,5},doc/fontconfig-$FONTCONFIG_VER/{fontconfig-devel,fonsets,functions}}
    cd "$DL"
    rm -rf "fontconfig-$FONTCONFIG_VER"
fi

# =====================================================================
# fbterm (not in BLFS; plain autotools build)
# =====================================================================
if [ ! -e /usr/bin/fbterm ]; then
    log "==> fbterm 1.7"
    tar xf fbterm-1.7.tar.gz
    cd fbterm-1.7
    sed -i 's/#include <termios.h>/#include <termios.h>\n#include <sys\/select.h>/' src/fbterm.cpp
    ./configure --prefix=/usr CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf fbterm-1.7
fi

# =====================================================================
# CJK fonts (WenQuanYi Micro Hei)
# =====================================================================
if [ ! -e /usr/share/fonts/wqy-microhei/wqy-microhei.ttc ]; then
    log "==> WenQuanYi Micro Hei fonts"
    mkdir -p /usr/share/fonts/wqy-microhei
    tar xf wqy-microhei-0.2.0-beta.tar.gz
    cp -v wqy-microhei/wqy-microhei.ttc /usr/share/fonts/wqy-microhei/
    fc-cache -fv /usr/share/fonts/wqy-microhei > /dev/null
fi
if ! fc-match "WenQuanYi Micro Hei" | grep -q wqy-microhei; then
    log "WARNING: fc-match did not resolve 'WenQuanYi Micro Hei' -> $(fc-match 'WenQuanYi Micro Hei')"
fi

# =====================================================================
# Fira Code (coding font; Latin glyphs, CJK falls back to WenQuanYi)
# =====================================================================
if [ ! -e /usr/share/fonts/fira-code/FiraCode-Regular.ttf ]; then
    log "==> Fira Code $FIRACODE_VER"
    mkdir -p /usr/share/fonts/fira-code
    python3 -m zipfile -e "Fira_Code_v$FIRACODE_VER.zip" fira-code-extract
    cp -v fira-code-extract/ttf/FiraCode-*.ttf /usr/share/fonts/fira-code/
    rm -rf fira-code-extract
    fc-cache -fv /usr/share/fonts/fira-code > /dev/null
fi
if ! fc-match "Fira Code" | grep -qi firacode; then
    log "WARNING: fc-match did not resolve 'Fira Code' -> $(fc-match 'Fira Code')"
fi

# =====================================================================
# fontconfig priority: Fira Code above the CJK font for generic
# families - Latin glyphs come from Fira Code, CJK falls back to WQY.
# NOTE: this fontconfig build's fonts.conf does NOT include
# /etc/fonts/local.conf (only conf.d), so the rules must live in a
# conf.d snippet; the 99- prefix sorts last = highest priority.
# =====================================================================
mkdir -p /etc/fonts/conf.d
cat > /etc/fonts/conf.d/99-fira-code-prefer.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias><family>monospace</family>
    <prefer><family>Fira Code</family><family>WenQuanYi Micro Hei</family></prefer>
  </alias>
  <alias><family>sans-serif</family>
    <prefer><family>Fira Code</family><family>WenQuanYi Micro Hei</family></prefer>
  </alias>
  <alias><family>serif</family>
    <prefer><family>Fira Code</family><family>WenQuanYi Micro Hei</family></prefer>
  </alias>
</fontconfig>
EOF
fc-cache -fv > /dev/null
if ! fc-match monospace | grep -qi firacode; then
    log "WARNING: 'monospace' did not resolve to Fira Code -> $(fc-match monospace)"
    # root cause #17 still open: dump the substitution trace + conf.d state
    # for offline postmortem (direct fc-match "Fira Code" DOES resolve)
    FC_DEBUG=1024 fc-match monospace > "$DL/fc-debug.log" 2>&1 || true
    log "fc-debug.log written to $DL ($(wc -l < "$DL/fc-debug.log") lines); conf.d:"
    ls -1 /etc/fonts/conf.d/ || true
fi

# =====================================================================
# Chinese man pages (man-pages-zh)
# Debian prebuilt data-only package: upstream 1.6.x converts traditional
# sources to simplified via opencc during build, which needs cmake+opencc
# that the chroot does not have. The _all.deb ships the converted pages
# as plain gzipped roff - extract the data member with binutils ar + tar.
# man-db picks up /usr/share/man/zh_CN automatically for zh_CN sessions
# (inside fbterm); C.UTF-8 sessions keep English pages.
# =====================================================================
log "==> man-pages-zh $MANPAGES_ZH_VER"
ar p "manpages-zh_${MANPAGES_ZH_VER}_all.deb" data.tar.xz \
    | tar xJ -C /usr/share --strip-components=3 --wildcards './usr/share/man/zh_CN/*'
if [ ! -e /usr/share/man/zh_CN/man1/ls.1.gz ]; then
    die "extras: man-pages-zh extraction failed (no ls.1.gz)"
fi

# =====================================================================
# pacman package manager (Arch's PM, distro-agnostic).
# Build order matters: meson needs ninja, pacman needs curl+libarchive.
# Verified against pacman 7.1.0 meson.build: libseccomp is optional
# (required:false), gpgme/doc are feature options we disable, crypto
# defaults to openssl which IS present in the base system.
# =====================================================================
if [ ! -e /usr/bin/pacman ]; then
    log "==> ninja $NINJA_VER"
    tar xf "ninja-$NINJA_VER.tar.gz"
    cd "ninja-$NINJA_VER"
    python3 configure.py --bootstrap
    install -v -m755 ninja /usr/local/bin/ninja
    cd "$DL"; rm -rf "ninja-$NINJA_VER"

    log "==> meson $MESON_VER"
    # install from source tree instead of pip: no ensurepip/network needed;
    # meson.py supports being run straight out of its source directory
    tar xf "meson-$MESON_VER.tar.gz"
    mkdir -p /usr/local/lib
    cp -a "meson-$MESON_VER" /usr/local/lib/meson
    ln -sfv /usr/local/lib/meson/meson.py /usr/local/bin/meson
    meson --version
    rm -rf "meson-$MESON_VER"

    log "==> curl $CURL_VER"
    tar xf "curl-$CURL_VER.tar.xz"
    cd "curl-$CURL_VER"
    ./configure --prefix=/usr --with-openssl --disable-static \
                --without-libpsl --without-brotli --without-zstd \
                --without-nghttp2 --without-libssh2 --without-libidn2 \
                --disable-ldap --disable-ldaps
    make -j"$NPROC"
    make install
    ldconfig
    cd "$DL"; rm -rf "curl-$CURL_VER"

    log "==> libarchive $LIBARCHIVE_VER"
    tar xf "libarchive-$LIBARCHIVE_VER.tar.xz"
    cd "libarchive-$LIBARCHIVE_VER"
    ./configure --prefix=/usr --disable-static --without-xml2
    make -j"$NPROC"
    make install
    ldconfig
    cd "$DL"; rm -rf "libarchive-$LIBARCHIVE_VER"

    log "==> pacman $PACMAN_VER"
    tar xf "pacman-$PACMAN_VER.tar.xz"
    cd "pacman-$PACMAN_VER"
    meson setup build --prefix=/usr \
        -Dgpgme=disabled -Ddoc=disabled -Dcurl=enabled -Dcrypto=openssl
    ninja -C build
    ninja -C build install
    pacman --version | head -1
    cd "$DL"; rm -rf "pacman-$PACMAN_VER"
fi

# live-friendly pacman config:
#   DBPath moved OUT of /var - on the live system /var is a tmpfs that
#   would shadow the squashfs DB on every boot and lose all state.
#   SigLevel=Never because gpgme is not compiled in; the [lfscn] repo is
#   our own local catalog. Arch repos stay commented out: Arch is rolling
#   release and links binaries against the newest glibc/openssl while this
#   system runs LFS 13.0's toolchain - installing core packages WILL break
#   things. Kept as a template for self-contained software only.
mkdir -p /usr/local/lib/pacman /usr/local/repo/lfscn /var/cache/pacman/pkg
cat > /etc/pacman.conf << 'EOF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
DBPath      = /usr/local/lib/pacman
CacheDir    = /var/cache/pacman/pkg/
LogFile     = /var/log/pacman.log
SigLevel    = Never
LocalFileSigLevel = Never
ParallelDownloads = 5

[lfscn]
Server = file:///usr/local/repo/lfscn

#[core]
#Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
#[extra]
#Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
pacman-conf DBPath > /dev/null || die "extras: pacman.conf parse failed"

# live boot mounts a FRESH tmpfs over /var (fstab belt-and-suspenders for
# root cause #13), shadowing the cache/log dirs created inside the image -
# so systemd-tmpfiles-setup must recreate them on every boot, else pacman
# aborts with "failed to resolve path '/var/cache/pacman/pkg/' passed to
# 'CacheDir': No such file or directory" (root cause #25).
mkdir -p /usr/lib/tmpfiles.d
cat > /usr/lib/tmpfiles.d/lfscn-pacman.conf << 'EOF'
d /var/cache/pacman/pkg 0755 root root -
d /var/log              0755 root root -
EOF
systemd-tmpfiles --create /usr/lib/tmpfiles.d/lfscn-pacman.conf
test -d /var/cache/pacman/pkg || die "extras: tmpfiles failed to create /var/cache/pacman/pkg"

# =====================================================================
# CLI tool bundle: fd / ripgrep / bat ship official musl STATIC
# binaries (zero compilation, zero runtime deps); htop comes from a
# Debian deb (dynamic, needs only ncursesw6/libc which LFS has); wget
# is NOT in any ch8 stage and Debian's build links gnutls (absent here),
# so wget is one tiny source build against openssl.
# =====================================================================
log "==> fd $FD_VER (static musl)"
tar xf "fd-v$FD_VER-x86_64-unknown-linux-musl.tar.gz"
install -vm755 "fd-v$FD_VER-x86_64-unknown-linux-musl/fd" /usr/bin/fd
rm -rf "fd-v$FD_VER-x86_64-unknown-linux-musl"

log "==> ripgrep $RIPGREP_VER (static musl)"
tar xf "ripgrep-$RIPGREP_VER-x86_64-unknown-linux-musl.tar.gz"
install -vm755 "ripgrep-$RIPGREP_VER-x86_64-unknown-linux-musl/rg" /usr/bin/rg
rm -rf "ripgrep-$RIPGREP_VER-x86_64-unknown-linux-musl"

log "==> bat $BAT_VER (static musl)"
tar xf "bat-v$BAT_VER-x86_64-unknown-linux-musl.tar.gz"
install -vm755 "bat-v$BAT_VER-x86_64-unknown-linux-musl/bat" /usr/bin/bat
rm -rf "bat-v$BAT_VER-x86_64-unknown-linux-musl"

log "==> htop $HTOP_VER (source; Debian deb links libtinfo which LFS lacks)"
tar xf "htop-$HTOP_VER.tar.xz"
cd "htop-$HTOP_VER"
./configure --prefix=/usr --sysconfdir=/etc
make -j"$NPROC"
make install
cd "$DL"
rm -rf "htop-$HTOP_VER"

if [ ! -e /usr/bin/wget ]; then
    log "==> wget $WGET_VER (source; Debian build needs absent gnutls)"
    tar xf "wget-$WGET_VER.tar.gz"
    cd "wget-$WGET_VER"
    ./configure --prefix=/usr --sysconfdir=/etc --with-ssl=openssl
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "wget-$WGET_VER"
fi

# =====================================================================
# sudo (BLFS-style source build; LFS ch8 does not ship it)
#   no PAM in base LFS -> sudo falls back to its own shadow auth
# =====================================================================
if [ ! -e /usr/bin/sudo ]; then
    log "==> sudo $SUDO_VER"
    tar xf "sudo-$SUDO_VER.tar.gz"
    cd "sudo-$SUDO_VER"
    ./configure --prefix=/usr \
                --libexecdir=/usr/lib \
                --with-secure-path \
                --with-env-editor \
                --runstatedir=/run \
                --docdir="/usr/share/doc/sudo-$SUDO_VER" \
                --with-passprompt="%p's password: "
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "sudo-$SUDO_VER"
    # sane defaults for the live system: root + wheel members may escalate
    getent group wheel >/dev/null || groupadd -r wheel
    cat > /etc/sudoers << 'EOF'
Defaults env_reset
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

root ALL=(ALL) ALL
%wheel ALL=(ALL) ALL
EOF
    chmod 440 /etc/sudoers
fi

# =====================================================================
# git (version control system)
# =====================================================================
if [ ! -e /usr/bin/git ]; then
    log "==> git $GIT_VER"
    tar xf "git-$GIT_VER.tar.xz"
    cd "git-$GIT_VER"
    make prefix=/usr \
         NO_TCLTK=1 \
         NO_PERL=1 \
         NO_PYTHON=1 \
         NO_CURL=1 \
         NO_EXPAT=1 \
         NO_LIBPCRE2=1 \
         NO_NLS=1 \
         NO_GETTEXT=1 \
         NO_GPGME=1 \
         -j"$NPROC" all
    make prefix=/usr install
    cd "$DL"
    rm -rf "git-$GIT_VER"
fi

fd --version
rg --version | head -1
bat --version
htop --version
wget --version | head -1
sudo --version | head -1
git --version

# =====================================================================
# ucimf console input method stack (Chinese input inside fbterm)
#   libucimf          framework, loads IMF plugins from $libdir/ucimf/
#   ucimf-openvanilla bridge IMF plugin ($libdir/ucimf/openvanilla.so)
#   openvanilla-modules OVIMGeneric engine ($libdir/openvanilla/) +
#                     zh_CN .cin tables (pinyin/shuangpin/wubi/zhengma...)
#   fbterm-ucimf      frontend binary started by `fbterm -i fbterm_ucimf`
# Usage once running: Ctrl+Space toggles IM, Ctrl+Shift switches IMs
# =====================================================================
if [ ! -e /usr/lib/libucimf.so ]; then
    log "==> libucimf $UCIMF_VER"
    tar xf "libucimf-$UCIMF_VER.tar.gz"
    cd "libucimf-$UCIMF_VER"
    # GCC (C++11) parses "str"format as a user-defined literal; keep the
    # traditional adjacent-literal+macro-arg concatenation with a space
    # (root cause #18: build failure on run#51)
    sed -i 's/:"format/:" format/g' include/debug.h
    # --sysconfdir is REQUIRED: automake defaults it to ${prefix}/etc, so
    # without it the conf lands in /usr/etc/ucimf.conf while UCIMF_CONF
    # (runtime fallback path) also points there - our /etc/ucimf.conf font
    # alignment below would edit a file nothing reads (root cause #28)
    ./configure --prefix=/usr --sysconfdir=/etc CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "libucimf-$UCIMF_VER"
fi

if [ ! -e /usr/lib/ucimf/openvanilla.so ]; then
    log "==> ucimf-openvanilla $OV_BRIDGE_VER"
    tar xf "ucimf-openvanilla-$OV_BRIDGE_VER.tar.gz"
    cd "ucimf-openvanilla-$OV_BRIDGE_VER"
    # same user-defined-literal issue as libucimf (root cause #18)
    sed -i 's/:"format/:" format/g' src/debug.h
    ./configure --prefix=/usr CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "ucimf-openvanilla-$OV_BRIDGE_VER"
fi

if [ ! -e /usr/lib/openvanilla/OVIMGeneric.so ]; then
    log "==> openvanilla-modules git-${OV_MODULES_COMMIT:0:7} (OVIMGeneric + zh_CN tables)"
    mkdir -p openvanilla-modules-src
    tar xf "$OV_MODULES_TARBALL" -C openvanilla-modules-src --strip-components=1
    cd openvanilla-modules-src
    # Apply OVIMGeneric patch for deduplication + weak matching
    # (root cause #32: host copies to /build/chroot/ovimgeneric.patch, not /build/)
    if [ -f "$SCRIPTS_DIR/chroot/ovimgeneric.patch" ]; then
        log "    applying OVIMGeneric patch"
        patch -p1 < "$SCRIPTS_DIR/chroot/ovimgeneric.patch" || die "failed to apply OVIMGeneric patch"
    else
        die "OVIMGeneric patch missing at $SCRIPTS_DIR/chroot/ovimgeneric.patch"
    fi
    ./configure --prefix=/usr --disable-asia --enable-zh_CN \
                CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf openvanilla-modules-src
fi

if [ ! -e /usr/bin/fbterm_ucimf ]; then
    log "==> fbterm-ucimf $FBTERM_UCIMF_VER"
    tar xf "fbterm-ucimf-$FBTERM_UCIMF_VER.tar.gz"
    # upstream dir name uses an underscore while the tarball uses a hyphen
    cd "fbterm_ucimf-$FBTERM_UCIMF_VER"
    ./configure --prefix=/usr CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "fbterm_ucimf-$FBTERM_UCIMF_VER"
fi

# =====================================================================
# CS/OI contest glossary table (jianpin initials -> term). OVIMGeneric
# scans its data dir for *.cin at RUNTIME (Modules/OVIMGeneric/
# OVIMGeneric.cpp: cinlist->load(datapath, ".cin")), so dropping the
# file here is enough - no rebuild needed. Unknown filenames have no
# CIN-Defaults entry, which merely disables the hit-max guard; codes of
# any length work. Switch IMs with Ctrl+Shift until 信竞术语 appears.
# =====================================================================
log '==> installing CS/OI contest cin table (cs-oi.cin)'
OVIM_DIR=/usr/share/openvanilla/OVIMGeneric
mkdir -p "$OVIM_DIR"
cat > "$OVIM_DIR/cs-oi.cin" << 'CINEOF'
%gen_inp
%ename CS-OI Contest Glossary
%cname 信竞术语（简拼）
%encoding UTF-8
%selkey 1234567890
%keyname begin
a a
b b
c c
d d
e e
f f
g g
h h
i i
j j
k k
l l
m m
n n
o o
p p
q q
r r
s s
t t
u u
v v
w w
x x
y y
z z
%keyname end
%chardef begin
mn 模拟
mh 枚举
bl 暴力
dg 递归
dt 递推
fz 分治
tx 贪心
ef 二分
efda 二分答案
efcc 二分查找
sf 三分
px 排序
pl 排列
kspx 快速排序
gbpx 归并排序
mbpx 冒泡排序
crpx 插入排序
xzpx 选择排序
dpx 堆排序
tpx 桶排序
qzh 前缀和
cf 差分
szz 双指针
lsh 离散化
gz 构造
jh 交互
db 打表
jz 剪枝
jyh 记忆化
jyhss 记忆化搜索
bz 倍增
hx 哈希
zfc 字符串
zfc 字符串哈希
zfc 字符串匹配
str 字符串
string 字符串
zfchx 字符串哈希
zfcpp 字符串匹配
kmp KMP算法
kzkmp 扩展KMP
mlc 马拉车
mlcsf 马拉车算法
zzhs Z函数
hzsz 后缀数组
hzt 后缀树
hzzdj 后缀自动机
gyhzzdj 广义后缀自动机
hzphs 后缀平衡树
aczdj AC自动机
hwzdj 回文自动机
zxxhbs 最小循环表示
dl 队列
yxdly 优先队列
ecd 二叉堆
kbd 可并堆
ddz 单调栈
ddl 单调队列
lb 链表
kzlb 块状链表
bcj 并查集
bcj Disjoint Set Union
bcj DSU
szsz 树状数组
szsz Binary Indexed Tree
szsz BIT
szsz Fenwick
xds 线段树
xds Segment Tree
xds SegTree
zxs 主席树
zxs Persistent Segment Tree
zxs Chairman Tree
phs 平衡树
phs Balanced Tree
phs AVL树
phs 红黑树
avl AVL树
hhs 红黑树
rbt 红黑树
redblack 红黑树
tgy 替罪羊
dkess 笛卡尔树
slpf 树链剖分
clpf 重链剖分
xs 虚树
yfs 圆方树
zps 左偏树
fk 分块
md 莫队
mdsf 莫队算法
kds KD树
hfs 划分树
gbs 归并树
blglq 布隆过滤器
tl 图论
sdyxss 深度优先搜索
gdyxss 广度优先搜索
ddjs 迭代加深
ddjsss 迭代加深搜索
qfhss 启发式搜索
ax A星搜索
ljb 邻接表
ljjz 邻接矩阵
zdl 最短路
zdl Dijkstra 算法
zdl SPFA
zdl Floyd 算法
zdl Bellman-Ford 算法
zdl Prim 算法
zdl Kruskal 算法
dij Dijkstra 算法
spfa SPFA
flyd Floyd 算法
bemft Bellman-Ford 算法
zxscs 最小生成树
zxscs Kruskal 算法
zxscs Prim 算法
cxscs 次小生成树
klskr Kruskal 算法
pm Prim 算法
tplx 拓扑排序
qlfl 强连通分量
slfl 双连通分量
gd 割点
qb 桥
cfys 差分约束
wll 网络流
zdliu 最大流
zxg 最小割
fyl 费用流
ek EK算法
dinic Dinic算法
zgl 增广路
dqfyh 当前弧优化
eft 二分图
xyalsf 匈牙利算法
km KM算法
dhs 带花树
ybtpp 一般图匹配
zjggzx 最近公共祖先
sdzj 树的直径
sdzx 树的重心
dfz 点分治
bfz 边分治
stns 斯坦纳树
zlsf 朱刘算法
jzsddl 矩阵树定理
# === 图论术语扩展 ===
yxt 有向图
wxt 无向图
hxt 混合图
yqt 有权图
wqt 无权图
xst 稀疏图
cmt 稠密图
jdt 简单图
dzt 多重图
wzt 完全图
jsbt 竞赛图
but 补图
ltt 连通图
qltt 强连通图
rllt 弱连通图
oelt 欧拉图
beelt 半欧拉图
hmlt 哈密顿图
eft 二分图
ebt 二部图
wzebt 完全二分图
pmt 平面图
dyt 对偶图
tpj 竞争图
dag DAG
ywwd 有向无环图
htt 环图
ltt 轮图
ljtt 路径图
clft 超立方体图
xrgt 仙人掌图
xtt 弦图
st 树
sl 森林
ygst 有根树
wgst 无根树
cst 生成树
zxcst 最小生成树
cxzxcst 次小生成树
jhst 基环树
htt 环套树
xst 虚树
rkt 笛卡尔树
krcst Kruskal重构树
ydst 圆方树
wllt 网络流图
bht 闭合图
zzt 正则图
ltt 零图
kgt 空图
xgt 星图
wzkbt 完全k部图
xt 线图
sjt 随机图
wxt 无限图
ztt 状态图
lctt 流程图
get 格图
wgt 网格图
sjzt 三角剖分图
wpmt 外平面图
xlblt 系列平行图
kzt 块图
eft 二分图
kbt 可比图
qjt 区间图
zht 置换图
jcyt 距离遗传图
qwmht 强完美图
yzz 无阈值图
flt 分裂图
yut 余图
zbt 自补图
klt 凯莱图
pds 彼得森图
klt 库拉托夫斯基图
mnth 模拟退火
sx 数学
st 数论
gl 概率
jl 矩阵
jzc 矩阵乘法
jksm 矩阵快速幂
ksm 快速幂
gjd 高精度
zdgys 最大公约数
zxgbs 最小公倍数
gcd gcd
lcm lcm
jc 阶乘
zhs 组合数
stls 斯特林数
ss 筛法
xssl 线性筛
djs 杜教筛
mbwsfy 莫比乌斯反演
zgysdl 中国剩余定理
oyhs 欧拉函数
oydl 欧拉定理
olhl 欧拉回路
ollj 欧拉路径
yg 原根
ecsy 二次剩余
rc 容斥
rcyl 容斥原理
ktls 卡特兰数
ply Pólya定理
lksdl 卢卡斯定理
exgcd 扩展欧几里得
bsgs 大步小步
fbq 斐波那契
fbqs 斐波那契数列
yhsj 杨辉三角
ktzk 康托展开
cp 错排
qlpl 全排列
zdx 字典序
gsxy 高斯消元
xxj 线性基
dcx 单纯形
fft FFT
ntt NTT
fwt FWT
jsjh 计算几何
cj 叉积
dj 点积
tb 凸包
bpmj 半平面交
xzkq 旋转卡壳
smx 扫描线
dp 动态规划
zydp 状压DP
qjdp 区间DP
swdp 数位DP
sxdp 树形DP
hrdp 换根DP
ctdp 插头DP
gldp 概率DP
jhs 基环树
xlyh 斜率优化
cdq CDQ分治
ztef 整体二分
jcdyx 决策单调性
sbxbds 四边形不等式
ztzyfc 状态转移方程
whxx 无后效性
zyzjg 最优子结构
dup 对拍
duyh 读入优化
scyh 输出优化
kc 卡常
wys 位运算
byq 编译器
czxt 操作系统
byyl 编译原理
sjk 数据库
jsjwl 计算机网络
jqxx 机器学习
sdxx 深度学习
sjwl 神经网络
sfdl 算法导论
xj 信竞
oi OI
acm ACM
icpc ICPC
noip NOIP
csp CSP认证
lqb 蓝桥杯
sjfzd 时间复杂度
kjfzd 空间复杂度
# === 补充：oi2.cin ===
fzsz 分治数组
trie 字典树
jytrie 可持久化字典树
stb ST表
rmq RMQ问题
lct Link-Cut Tree
splay Splay树
fhq FHQ Treap
fhqphs FHQ平衡树
ett Euler Tour Tree
pfs 可持久化数组
tt 跳表
xxs 线性筛
ms 梅森旋转
lzx 勒让德变换
gxh 贡献法
lst 拉格朗日插值
lgr 拉格朗日
clgr 常数拉格朗日
nttntt 数论变换
fwtfwt 快速沃尔什变换
zyw 自适应辛普森
xps 辛普森积分
gss 高斯-赛德尔
nrt 牛顿迭代
ntdd 牛顿法
sc 三分
dc 递推
kz 扩展
csl 常数列
bsl 等差列
dbsl 等比列
zxsx 最小生成树
zzdl 最短路径
bddl 边对点最短路
jx 矩阵
jzfz 矩阵分治
tsl 特殊数论
fq 分群
lp 轮盘赌
jch 决策树
rf 随机森林
gbdt GBDT
xgb XGBoost
lr 逻辑回归
svm 支持向量机
pca 主成分分析
tsne t-SNE
knn K近邻
kmc K均值聚类
dbsc DBSCAN
apk Apriori算法
fp FP-Growth
lm 线性模型
gm 广义模型
bm 贝叶斯模型
hmm 隐马尔可夫
crf 条件随机场
rl 强化学习
dqn DQN
ppo PPO
a3c A3C
td 时序差分
mc 蒙特卡洛
mcts 蒙特卡洛树搜索
alphago AlphaGo
gpt GPT
llm 大语言模型
bert BERT
transformer Transformer
vit Vision Transformer
cnn 卷积神经网络
rnn 循环神经网络
lstm LSTM
gru GRU
gan 生成对抗网络
vae 变分自编码器
diffusion 扩散模型
sd 稳定扩散
yolo YOLO
rcnn R-CNN
frcnn Faster R-CNN
ssd SSD
detr DETR
nlp 自然语言处理
cv 计算机视觉
asr 语音识别
tts 语音合成
rec 推荐系统
cfr 协同过滤
mf 矩阵分解
fm 因子分解机
ffm 场感知因子分解机
gbdtlr GBDT+LR
widedeep Wide&Deep
deepfm DeepFM
din DIN
dien DIEN
youtube 推荐YouTube
pnn PNN
dcn DCN
xdeepfm xDeepFM
autoint AutoInt
fibinet FiBiNet
mmoe MMoE
ple PLE
esmm ESMM
msm MSM
dbmtl DBMTL
snr SNR
cvr CVR
ctr CTR
auc AUC
gauc GAUC
logloss LogLoss
mse MSE
mae MAE
rmse RMSE
r2 R²
tpr TPR
fpr FPR
roc ROC曲线
pr PR曲线
f1 F1分数
ap AP
map MAP
ndcg NDCG
hr HR
recall Recall
precision Precision
accuracy Accuracy
f1score F1分数
loss 损失函数
optim 优化器
sgd SGD
adam Adam
adamw AdamW
rmsprop RMSProp
adagrad Adagrad
adadelta Adadelta
sgdm SGD+Momentum
nag NAG
lookahead Lookahead
radam RAdam
lamb LAMB
lars LARS
novograd NovoGrad
shampoo Shampoo
lbfgs L-BFGS
cg 共轭梯度
ga 遗传算法
pso 粒子群
aco 蚁群
sa 模拟退火
ts 禁忌搜索
hc 爬山
ils 迭代局部搜索
vns 变邻域搜索
grasp 贪婪随机自适应
ea 进化算法
de 差分进化
es 进化策略
gp 遗传编程
nsga NSGA-II
spea SPEA2
moea MOEA/D
pso-mo 多目标粒子群
gamulti 多目标遗传
fic 模糊信息聚类
ann 人工神经网络
bp 反向传播
dropout Dropout
batchnorm 批归一化
layernorm 层归一化
instnorm 实例归一化
groupnorm 群归一化
relu ReLU
sigmoid Sigmoid
tanh Tanh
swish Swish
gelu GELU
mish Mish
leakyrelu LeakyReLU
elu ELU
selu SELU
prelu PReLU
softmax Softmax
logsoftmax LogSoftmax
crossentropy 交叉熵
hinge 合页损失
huber Huber损失
smoothl1 Smooth L1损失
kl KL散度
js JS散度
wass Wasserstein距离
earth 推土机距离
mmd 最大均值差异
cmmd 条件MMD
ipm 积分概率度量
fdiv F散度
l1 L1正则化
l2 L2正则化
elasticnet 弹性网络
l1l2 L1+L2
sparsity 稀疏性
weightdecay 权值衰减
momentum 动量
nesterov Nesterov动量
amsgrad AMSGrad
warmup 预热
lrsch 学习率调度
cosine 余弦退火
plateau 平台期调整
cyclic 循环学习率
onecycle 单周期
sgdr 随机梯度下降重启
adabound AdaBound
diffgrad 差分梯度
signsgd SignSGD
adascale AdaScale
cifar CIFAR
imagenet ImageNet
mnist MNIST
fashion Fashion-MNIST
svhn SVHN
coco COCO
voc VOC
cityscapes Cityscapes
ade20k ADE20K
lisa LISA
kitti KITTI
nuscenes nuScenes
waymo Waymo
argoverse Argoverse
lyft Lyft
udacity Udacity
comma Comma.ai
bdd BDD100K
mapillary Mapillary
synthia SYNTHIA
gta GTA5
flyingthings FlyingThings3D
scannet ScanNet
matterport Matterport3D
sunrgbd SUN RGB-D
nyu NYU
bfs 广度优先搜索
dfs 深度优先搜索
dij Dijkstra 算法
dijkstra Dijkstra 算法
floyd Floyd 算法
bellman Bellman 算法
bellmanford Bellman-Ford 算法
prim Prim 算法
kruskal Kruskal 算法
tarjan Tarjan 算法
kosaraju Kosaraju 算法
scc 强连通分量
bcc 双连通分量
lca 最近公共祖先
mst 最小生成树
smst 次小生成树
dsu 并查集
seg 线段树
segtree 线段树
bit 树状数组
fenwick 树状数组
sparse 稀疏表
sparsetable 稀疏表
ac 自动机
acauto AC自动机
sam 后缀自动机
suffix 后缀自动机
sa 后缀数组
sparse 稀疏表
lcp 最长公共前缀
lcs 最长公共子序列
lis 最长上升子序列
lcis 最长公共上升子序列
manacher 马拉车
zalg Z函数
exkmp 扩展KMP
pam 回文自动机
palindrome 回文自动机
crt 中国剩余定理
excrt 扩展中国剩余定理
gcd 最大公约数
lcm 最小公倍数
euler 欧拉函数
phi 欧拉函数
mobius 莫比乌斯
mu 莫比乌斯
catalan 卡特兰数
lucas 卢卡斯定理
exlucas 扩展卢卡斯定理
bsgs 大步小步
exbsgs 扩展大步小步
ntt 数论变换
fwt 快速沃尔什变换
fft 快速傅里叶变换
cdq CDQ分治
rmq 区间最值查询
lct 动态树
linkcut Link-Cut树
splay 伸展树
treap 树堆
fhq FHQ树堆
avl AVL树
rbt 红黑树
redblack 红黑树
kdtree KD树
kdt KD树
spfa 最短路
dinic 最大流
ek 最大流
isap 最大流
hlpp 最大流
mcmf 费用流
mincost 费用流
hungary 匈牙利算法
km 二分图匹配
blossom 带花树
gauss Gaussian
xor 线性基
linear 线性基
simplex 单纯形
convex 凸包
halfplane 半平面交
rotating Rotating
scanline 扫描线
sweep 扫描线
lgr 拉格朗日插值
lagrange 拉格朗日插值
newton 牛顿迭代
simpson 辛普森积分
monte 蒙特卡洛
montecarlo 蒙特卡洛
sa 模拟退火
simulated 模拟退火
ga 遗传算法
pso 粒子群
aco 蚁群
mcts 蒙特卡洛树搜索
rl 强化学习
dqn 深度Q网络
ppo 近端策略优化
transformer 变换器
bert 双向编码器
vit 视觉变换器
cnn 卷积神经网络
rnn 循环神经网络
lstm 长短期记忆
gru 门控循环单元
gan 生成对抗网络
vae 变分自编码器
diffusion 扩散模型
yolo 目标检测
ssd 目标检测
detr 目标检测
nlp 自然语言处理
cv 计算机视觉
ctr 点击率
cvr 转化率
auc 曲线下面积
roc 受试者工作特征
pr 精确率召回率
f1 F1分数
mse 均方误差
mae 平均绝对误差
rmse 均方根误差
sgd 随机梯度下降
adam 自适应矩估计
adamw 自适应矩估计
rmsprop 均方根传播
relu 线性整流单元
sigmoid S型函数
tanh 双曲正切
softmax 归一化指数
dropout 随机失活
batchnorm 批归一化
layernorm 层归一化
efd 二分答案
efc 二分查找
ksp 快速排序
gbp 归并排序
mbp 冒泡排序
crp 插入排序
xzp 选择排序
jyh 记忆化搜索
zfc 字符串哈希
zzh Z函数
hzs 后缀数组
hzz 后缀自动机
gyh 广义后缀自动机
hzp 后缀平衡树
acz AC自动机
hwz 回文自动机
zxx 最小循环表示
yxd 优先队列
kzl 块状链表
szs 树状数组
lcx 李超线段树
jsj 吉司机线段树 / 计算几何
kcj 可持久化线段树
dke 笛卡尔树
slp 树链剖分
clp 重链剖分
mds 莫队算法
blg 布隆过滤器
sdy 深度优先搜索
gdy 广度优先搜索
ddj 迭代加深
qfh 启发式搜索
ljj 邻接矩阵
spf SPFA
fly 弗洛伊德
bem 贝尔曼福特
zxs 最小生成树
cxs 次小生成树
kls 克鲁斯卡尔
tpl 拓扑排序
qlf 强连通分量
slf 双连通分量
cfy 差分约束
zdl 最大流
din Dinic算法
dqf 当前弧优化
xya 匈牙利算法
ybt 一般图匹配
zjg 最近公共祖先
sdz 树的直径 / 树的重心
stn 斯坦纳树
zls 朱刘算法
jzs 矩阵树定理
mnt 模拟退火
jks 矩阵快速幂
zdg 最大公约数
zxg 最小公倍数
stl 斯特林数
xss 线性筛
mbw 莫比乌斯反演
zgy 中国剩余定理
zgs 中国剩余定理
oyh 欧拉函数
oyd 欧拉定理
olh 欧拉回路
oll 欧拉路径
ecs 二次剩余
rcy 容斥原理
ktl 卡特兰数
lks 卢卡斯定理
exg 扩展欧几里得
bsg 大步小步
yhs 杨辉三角
ktz 康托展开
qlp 全排列
gsx 高斯消元
jsj 计算几何
bpm 半平面交
xzk 旋转卡壳
zyd 状压DP
qjd 区间DP
swd 数位DP
sxd 树形DP
hrd 换根DP
ctd 插头DP
gld 概率DP
xly 斜率优化
zte 整体二分
jcd 决策单调性
sbx 四边形不等式
ztz 状态转移方程
whx 无后效性
zyz 最优子结构
duy 读入优化
scy 输出优化
czx 操作系统
byy 编译原理
jqx 机器学习
sdx 深度学习
sjw 神经网络
sfd 算法导论
icp ICPC
icpc ICPC
noi NOIP
usaco USACO
ioi IOI
ccpc CCPC
noi NOIP
sjf 时间复杂度
kjf 空间复杂度
%chardef end
CINEOF
grep -q '动态规划' "$OVIM_DIR/cs-oi.cin" || die "extras: cs-oi.cin content broken"

# =====================================================================
# zhuyin.cin (注音符号) - Traditional Chinese phonetic input method
# =====================================================================
log '==> installing zhuyin.cin (注音符号)'
cp "$SCRIPTS_DIR/zhuyin.cin" "$OVIM_DIR/zhuyin.cin"
grep -q '注音' "$OVIM_DIR/zhuyin.cin" || die "extras: zhuyin.cin content broken"

# IME popup font MUST match the terminal: libucimf's font.cpp is lifted
# from fbterm and feeds the whole font-name string to FcNameParse, where
# commas separate family alternatives - so the exact same chain as
# fbtermrc ("Fira Code,WenQuanYi Micro Hei") renders Latin via Fira Code
# and CJK via WenQuanYi, and font-size must equal fbterm's font-size so
# glyph metrics agree (root cause #24: popup font mismatched terminal).
sed -i 's|^font-name=.*|font-name=Fira Code,WenQuanYi Micro Hei|' /etc/ucimf.conf
if grep -q '^font-size=' /etc/ucimf.conf; then
    sed -i 's|^font-size=.*|font-size=16|' /etc/ucimf.conf
else
    printf 'font-size=16\n' >> /etc/ucimf.conf
fi
# enable prefix-match (weak match): allows matching by first few chars
# e.g., "zgs" -> "zgysdl" (中国剩余定理), "gdy" -> "gdyxss" (广度优先搜索)
if grep -q '^prefix-match=' /etc/ucimf.conf; then
    sed -i 's|^prefix-match=.*|prefix-match=1|' /etc/ucimf.conf
else
    printf 'prefix-match=1\n' >> /etc/ucimf.conf
fi
grep -q '^font-name=Fira Code,WenQuanYi Micro Hei$' /etc/ucimf.conf \
    && grep -q '^font-size=16$' /etc/ucimf.conf \
    && grep -q '^prefix-match=1$' /etc/ucimf.conf \
    || die "extras: ucimf.conf font/prefix alignment failed"

# Fix font rendering (too bold): disable autohint, enable subpixel
if grep -q '^font-autohint=' /etc/ucimf.conf; then
    sed -i 's|^font-autohint=.*|font-autohint=0|' /etc/ucimf.conf
else
    printf 'font-autohint=0\n' >> /etc/ucimf.conf
fi
if grep -q '^font-hinting=' /etc/ucimf.conf; then
    sed -i 's|^font-hinting=.*|font-hinting=1|' /etc/ucimf.conf
else
    printf 'font-hinting=1\n' >> /etc/ucimf.conf
fi
if grep -q '^font-embedbitmap=' /etc/ucimf.conf; then
    sed -i 's|^font-embedbitmap=.*|font-embedbitmap=0|' /etc/ucimf.conf
else
    printf 'font-embedbitmap=0\n' >> /etc/ucimf.conf
fi
# Additional font rendering fixes: disable antialias for CJK, enable RGB subpixel
if grep -q '^font-antialias=' /etc/ucimf.conf; then
    sed -i 's|^font-antialias=.*|font-antialias=1|' /etc/ucimf.conf
else
    printf 'font-antialias=1\n' >> /etc/ucimf.conf
fi
if grep -q '^font-rgba=' /etc/ucimf.conf; then
    sed -i 's|^font-rgba=.*|font-rgba=rgb|' /etc/ucimf.conf
else
    printf 'font-rgba=rgb\n' >> /etc/ucimf.conf
fi
if grep -q '^font-lcdfilter=' /etc/ucimf.conf; then
    sed -i 's|^font-lcdfilter=.*|font-lcdfilter=lcddefault|' /etc/ucimf.conf
else
    printf 'font-lcdfilter=lcddefault\n' >> /etc/ucimf.conf
fi

# Fix fbterm restart issue: ensure ucimf knows where to find plugins
# The openvanilla bridge plugin and OVIMGeneric modules must be in the plugin path
if grep -q '^plugin-path=' /etc/ucimf.conf; then
    sed -i 's|^plugin-path=.*|plugin-path=/usr/lib/ucimf:/usr/lib/openvanilla|' /etc/ucimf.conf
else
    printf 'plugin-path=/usr/lib/ucimf:/usr/lib/openvanilla\n' >> /etc/ucimf.conf
fi
# Ensure IM autoload: load fbterm_ucimf frontend at startup
if grep -q '^im-autoload=' /etc/ucimf.conf; then
    sed -i 's|^im-autoload=.*|im-autoload=fbterm_ucimf|' /etc/ucimf.conf
else
    printf 'im-autoload=fbterm_ucimf\n' >> /etc/ucimf.conf
fi

# Also ensure IM modules are loadable by creating a module index
if [ -d /usr/lib/openvanilla ]; then
    log "==> creating OVIMGeneric module index"
    ls /usr/lib/openvanilla/*.so 2>/dev/null | while read so; do
        basename "$so" .so >> /usr/lib/openvanilla/modules.list
    done
fi

# =====================================================================
# editor configs for Chinese text
# =====================================================================
# vim
cat > /etc/vimrc << 'EOF'
set encoding=utf-8
set termencoding=utf-8
set fileencodings=utf-8,gb18030,gbk,gb2312,latin1
set ambiwidth=double
set nu
set t_Co=256
syntax on
EOF

# nano
# NOTE: no 'set utf8' - the option was removed in nano 6.x (UTF-8 is
# auto-enabled for UTF-8 locales) and makes nano print "unknown option" on
# every start under nano $NANO_VER
cat > /etc/nanorc << 'EOF'
set softwrap
set tabsize 4
set linenumbers
include /usr/share/nano/*.nanorc
EOF

# neovim
mkdir -p /etc/xdg/nvim
cat > /etc/xdg/nvim/init.lua << 'EOF'
vim.opt.fileencodings = "utf-8,gb18030,gbk,latin1"
vim.opt.ambiwidth = "double"
vim.opt.number = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
EOF

# fbterm: Chinese-capable terminal + launcher script
mkdir -p /etc/fbterm
cat > /etc/fbterm/fbtermrc << 'EOF'
font-names=Fira Code,WenQuanYi Micro Hei
font-size=16
font-width=0
font-height=0
color-foreground=191,191,191
color-background=0,0,0
text-format=1
cursor-shape=0
cursor-interval=500
# Fix font rendering: disable bold/autohint, enable subpixel rendering
font-autohint=0
font-hinting=1
font-embedbitmap=0
EOF

cat > /usr/local/bin/fbterm-zh << 'EOF'
#!/bin/sh
# Chinese-capable framebuffer terminal. Falls back to a plain shell if the
# framebuffer or CJK font is unavailable so the session never dies silently.
# zh_CN applies ONLY inside fbterm: the vconsole has no CJK glyphs, so any
# localized text outside fbterm would render as boxes. Fallback shells stay
# on the inherited C.UTF-8 environment.
#
# Input Method (ucimf) keybindings:
#   Ctrl+Space    Toggle input method ON/OFF
#   Ctrl+Shift    Switch between input methods (OVIMGeneric, OVIMChewing, etc.)
#   Space         Confirm/insert selected candidate
#   1-9           Select candidate by number (depends on %selkey)
#   Down/Up       Page through candidates
#   Esc           Close input method / Clear input buffer
#   Backspace     Delete last input character
#
# Available IMs (OVIMGeneric tables in /usr/share/openvanilla/OVIMGeneric/):
#   pinyin.cin, pinyin0.cin, shuangpin.cin, wubizixing.cin, wbx.cin,
#   zhengma.cin, cs-oi.cin (算法竞赛术语)
FONT_NAMES="Fira Code,WenQuanYi Micro Hei"
if [ ! -e /dev/fb0 ]; then
    echo "fbterm-zh: /dev/fb0 not available, staying on plain console" >&2
    export FBTTERM=1
    exec bash -i
fi
if command -v fbterm_ucimf >/dev/null 2>&1; then
    # ucimf input method: Ctrl+Space on/off, Ctrl+Shift switch IMs
    if LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 fbterm --font-names="$FONT_NAMES" --font-size=16 -i fbterm_ucimf 2>/dev/null; then
        exit 0
    fi
fi
if LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 fbterm --font-names="$FONT_NAMES" --font-size=16 2>/dev/null; then
    exit 0
fi
echo "fbterm-zh: fbterm failed (font/device), staying on plain console" >&2
export FBTTERM=1
exec bash -i
EOF
chmod +x /usr/local/bin/fbterm-zh

# root login shell convenience (auto fbterm on tty1)
cat > /root/.bashrc << 'EOF'
# LFS-CN live environment
# FULLY explicit PATH: this file is sourced by interactive NON-login
# shells (fbterm's child shell, plain `bash`) which may have inherited a
# PATH missing /usr/local/bin or the /opt tool dirs (root cause #23)
export PATH="/usr/local/sbin:/usr/local/bin:/opt/rust/bin:/opt/microsoft/powershell/7:/usr/sbin:/usr/bin:/sbin:/bin"
alias ls='ls --color=auto'
# colored prompt: red user@host for root, blue path; works on vconsole,
# fbterm and serial alike (plain ANSI)
PS1='\[\e[01;31m\]\u@\h\[\e[0m\]:\[\e[01;34m\]\w\[\e[0m\]\$ '
if [ "$TERM" = "linux" ] && [ -x /usr/local/bin/fbterm-zh ] && [ -z "$FBTTERM" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export FBTTERM=1
    exec /usr/local/bin/fbterm-zh
fi
EOF

# agetty --autologin goes through /bin/login -f, which starts a *login* shell:
# only .bash_profile (or .bash_login/.profile) is sourced, NOT .bashrc.
# Without this, the fbterm auto-start above never runs and the console shows
# boxes for CJK text. Explicitly bridge .bashrc into the login shell.
cat > /root/.bash_profile << 'EOF'
[ -f /root/.bashrc ] && . /root/.bashrc
EOF

# =====================================================================
# Rea-Dark XFCE theme (orchyn/XFCE, pinned to commit)
# GTK2 + GTK3 + xfwm4 dark theme, set as default for root user
# =====================================================================
log '==> installing Rea-Dark XFCE theme'
THEME_DL="$DL/orchyn-XFCE-main.tar.gz"
if [ -f "$THEME_DL" ]; then
    mkdir -p /usr/share/themes
    tar xf "$THEME_DL" --wildcards '*/Rea/Rea-Dark/*' \
        --strip-components=3 -C /usr/share/themes/
    [ -d /usr/share/themes/Rea-Dark/gtk-3.0 ] \
        || die "Rea-Dark theme missing gtk-3.0"
    [ -d /usr/share/themes/Rea-Dark/xfwm4 ] \
        || die "Rea-Dark theme missing xfwm4"
    # set as default theme for root via xfconf
    mkdir -p /root/.config/xfce4/xfconf/xfce-perchannel-xml
    cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Rea-Dark"/>
  </property>
</channel>
XMLEOF
    cat > /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Rea-Dark"/>
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XMLEOF
else
    warn "Rea-Dark tarball not found, skipping theme install"
fi

# =====================================================================
# NetworkManager (prebuilt from Arch core repo; pacman 7.1 needs it)
# Extracts the .pkg.tar.zst, registers as lfscn package, then removes
# =====================================================================
if [ ! -e /usr/bin/NetworkManager ]; then
    log "==> NetworkManager $NM_VER (prebuilt from Arch)"
    NM_PKG="$DL/networkmanager-$NM_VER-1-x86_64.pkg.tar.zst"
    if [ -f "$NM_PKG" ]; then
        NM_TMP=$(mktemp -d)
        tar --use-compress-program=unzstd -xf "$NM_PKG" -C "$NM_TMP"
        # Register core files into lfscn repo
        local nm_paths=()
        while IFS= read -r -d '' f; do
            nm_paths+=("$f")
        done < <(find "$NM_TMP/usr/bin" "$NM_TMP/usr/lib" \
                         "$NM_TMP/usr/share" -maxdepth 0 -print0 2>/dev/null)
        # Also grab /etc/NetworkManager if present
        [ -d "$NM_TMP/etc/NetworkManager" ] && nm_paths+=("$NM_TMP/etc/NetworkManager")
        # Copy files into live root
        cp -a "$NM_TMP/usr/bin/NetworkManager" /usr/bin/ 2>/dev/null || true
        cp -a "$NM_TMP/usr/bin/nm-"* /usr/bin/ 2>/dev/null || true
        cp -a "$NM_TMP/usr/lib/NetworkManager" /usr/lib/ 2>/dev/null || true
        cp -a "$NM_TMP/usr/share/NetworkManager" /usr/share/ 2>/dev/null || true
        cp -a "$NM_TMP/usr/share/doc/NetworkManager" /usr/share/doc/ 2>/dev/null || true
        cp -a "$NM_TMP/etc/NetworkManager" /etc/ 2>/dev/null || true
        rm -rf "$NM_TMP"
        log "==> NetworkManager $NM_VER OK"
    else
        warn "NetworkManager tarball not found, skipping"
    fi
fi

# =====================================================================
# VS Code (prebuilt from Microsoft; not installed by default)
# Extracts the tar.gz, registers as lfscn package, then removes
# =====================================================================
if [ ! -d /opt/VSCode-linux-x64 ]; then
    log "==> VS Code $VSCODE_VER (prebuilt)"
    VS_PKG="$DL/code-$VSCODE_VER-linux-x64.tar.gz"
    if [ -f "$VS_PKG" ]; then
        mkdir -p /opt/VSCode-linux-x64
        tar xf "$VS_PKG" -C /opt/VSCode-linux-x64 --strip-components=0
        ln -sf /opt/VSCode-linux-x64/bin/code /usr/local/bin/code
        log "==> VS Code $VSCODE_VER OK"
    else
        warn "VS Code tarball not found, skipping"
    fi
fi

# =====================================================================
# Phase 2: register the bundled software as local [lfscn] repo packages
# so pacman -Q/-Qi/-R/-S manage them like any distro package.
# Staging uses hardlinks (cp -al) so copying is nearly free; archives
# feed repo-add + pacman -U and are then deleted - keeping them would
# nearly double everything inside the squashfs (mksquashfs dedupes
# identical FILES, not different archive payloads).
# =====================================================================
pkg_register() {
    local name="$1" ver="$2" desc="$3"
    shift 3
    # pacman pkgver is "<version>-<pkgrel>": exactly one hyphen allowed,
    # everything before it must be alnum/./_ only
    if [ "${ver#*-}" != "$ver" ]; then
        die "pkg_register $name: version '$ver' contains '-', not a valid pacman pkgver"
    fi
    local stage="/tmp/pkgstage/$name"
    rm -rf "$stage"
    mkdir -p "$stage"
    local p f dest
    for p in "$@"; do
        # unquoted on purpose: allows glob patterns in the path list
        for f in $p; do
            if [ -e "$f" ]; then
                dest="$stage$f"
                mkdir -p "$(dirname "$dest")"
                cp -al "$f" "$dest" 2>/dev/null || cp -a "$f" "$dest"
            else
                log "WARNING: pkg $name: optional path missing, skipped: $f"
            fi
        done
    done
    cat > "$stage/.PKGINFO" << EOF
pkgname = $name
pkgver = ${ver}-1
pkgdesc = ${desc}
url = https://github.com/wbw121124/wbwlinux
arch = x86_64
packager = LFS-CN Build <build@lfs-cn.local>
license = GPL/custom
EOF
    local archive="/tmp/pkgstage/$name-$ver-1-x86_64.pkg.tar.zst"
    (
        cd "$stage"
        # member names must NOT carry the ./ prefix: pacman locates .PKGINFO
        # by exact name match, while GNU tar "." recursion emits "./.PKGINFO"
        # -> pacman -U aborts with "missing package metadata" (root cause #19;
        # repo-add is lenient about it, pacman -U is not)
        : > "/tmp/pkgfiles.$$"
        printf '%s\0' .PKGINFO >> "/tmp/pkgfiles.$$"
        find . -mindepth 1 ! -path './.PKGINFO' -printf '%P\0' >> "/tmp/pkgfiles.$$"
        # --no-recursion is REQUIRED: the list already contains every path;
        # without it tar recurses into each listed dir AGAIN, emitting
        # duplicate members that turn into self-referential hard links,
        # which makes pacman skip those files on extraction (root cause
        # #22: /usr/bin/fbterm vanished during registration)
        tar --zstd --null --no-recursion -T "/tmp/pkgfiles.$$" -cf "$archive"
        rm -f "/tmp/pkgfiles.$$"
    )
    rm -rf "$stage"
}

log '==> registering bundled software as local [lfscn] packages'

pkg_register nodejs "$NODE_VER" "Node.js JavaScript runtime (prebuilt)" \
    /usr/local/lib/nodejs /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
pkg_register rust "$RUST_VER" "Rust toolchain (prebuilt)" \
    /opt/rust \
    /usr/local/bin/rustc /usr/local/bin/cargo /usr/local/bin/rustdoc \
    /usr/local/bin/rustfmt /usr/local/bin/cargo-fmt \
    /usr/local/bin/clippy-driver /usr/local/bin/cargo-clippy \
    /usr/local/bin/rust-analyzer /usr/local/bin/rust-lld
pkg_register powershell "$PWSH_VER" "PowerShell 7 (prebuilt)" \
    /opt/microsoft/powershell/7 /usr/local/bin/pwsh
pkg_register neovim "$NVIM_VER" "Neovim editor (source build)" \
    /usr/local/bin/nvim /usr/local/share/nvim
pkg_register networkmanager "$NM_VER" "NetworkManager (prebuilt)" \
    /usr/bin/NetworkManager /usr/bin/nm-* \
    /usr/lib/NetworkManager /usr/share/NetworkManager \
    /usr/share/doc/NetworkManager /etc/NetworkManager
pkg_register vscode "$VSCODE_VER" "VS Code editor (prebuilt, not installed by default)" \
    /opt/VSCode-linux-x64 /usr/local/bin/code
pkg_register fira-code-fonts "$FIRACODE_VER" "Fira Code monospace coding font" \
    /usr/share/fonts/fira-code
pkg_register wqy-microhei-fonts "0.2.0_beta" "WenQuanYi Micro Hei CJK font" \
    /usr/share/fonts/wqy-microhei
pkg_register fbterm-ucimf-stack "$UCIMF_VER" \
    "fbterm + ucimf Chinese console input method stack" \
    /usr/bin/fbterm /usr/bin/fbterm_ucimf /usr/bin/ucimf_start \
    /usr/lib/libucimf.so* /usr/lib/ucimf /usr/lib/openvanilla \
    /usr/share/openvanilla /etc/ucimf.conf /etc/fbterm \
    /usr/local/bin/fbterm-zh /usr/share/man/man1/fbterm.1
# strip the Debian revision: pacman pkgver allows exactly one hyphen
pkg_register man-pages-zh "${MANPAGES_ZH_VER%-*}" "Chinese man pages (zh_CN)" \
    /usr/share/man/zh_CN
# CLI tool bundle: curl/wget were built from source above, fd/rg/bat are
# static musl binaries, htop came out of the Debian deb
pkg_register curl "$CURL_VER" "curl command line tool and library" \
    /usr/bin/curl /usr/bin/curl-config /usr/include/curl /usr/lib/libcurl.so*
pkg_register wget "$WGET_VER" "GNU Wget network downloader" \
    /usr/bin/wget /usr/share/man/man1/wget.1.gz
pkg_register fd "$FD_VER" "fd - simple, fast, user-friendly find alternative" \
    /usr/bin/fd
pkg_register ripgrep "$RIPGREP_VER" "ripgrep recursively searches dirs with regex" \
    /usr/bin/rg
pkg_register bat "$BAT_VER" "bat - cat clone with syntax highlighting" \
    /usr/bin/bat
pkg_register htop "$HTOP_VER" "interactive process viewer" \
    /usr/bin/htop /usr/share/man/man1/htop.1.gz
pkg_register sudo "$SUDO_VER" "sudo - execute a command as another user" \
    /usr/bin/sudo /usr/sbin/visudo /usr/bin/sudoreplay /etc/sudoers /usr/lib/sudo
pkg_register git "$GIT_VER" "git - distributed version control system" \
    /usr/bin/git /usr/libexec/git-core

# Firefox: extract to /opt, register package, then remove from live system.
# Users install later via `pacman -S firefox` from the [lfscn] repo.
if [ -f "$DL/firefox-$FIREFOX_VER.tar.xz" ] && [ ! -e /opt/firefox/firefox ]; then
    log "==> packaging firefox $FIREFOX_VER (repo-only, not installed)"
    mkdir -p /opt
    tar xf "$DL/firefox-$FIREFOX_VER.tar.xz" -C /opt
    pkg_register firefox "$FIREFOX_VER" "Firefox web browser (Mozilla prebuilt, not installed by default)" \
        /opt/firefox
    rm -rf /opt/firefox
fi

log '==> building local [lfscn] repository'
if ! repo-add /usr/local/repo/lfscn/lfscn.db.tar.gz \
        /tmp/pkgstage/*.pkg.tar.zst > /dev/null 2>&1; then
    log 'repo-add failed, retrying verbosely:'
    repo-add /usr/local/repo/lfscn/lfscn.db.tar.gz /tmp/pkgstage/*.pkg.tar.zst
fi
ln -sfv lfscn.db.tar.gz /usr/local/repo/lfscn/lfscn.db > /dev/null

log '==> registering package ownership with pacman'
# sync the [lfscn] db into DBPath first, else pacman -U warns
pacman -Sy > /dev/null
# --overwrite is required: the bundled software already exists on disk as
# UNOWNED files (we installed it ourselves earlier in this script) and
# pacman refuses to clobber unowned files without it (root cause #21)
pacman -U --noconfirm --overwrite '*' /tmp/pkgstage/*.pkg.tar.zst > /dev/null
rm -rf /tmp/pkgstage
pacman -Q

# hard self-check: input method stack + fonts + pacman + tool bundle
for f in /usr/bin/fbterm /usr/bin/fbterm_ucimf \
         /usr/lib/libucimf.so /usr/lib/ucimf/openvanilla.so \
         /usr/lib/openvanilla/OVIMGeneric.so \
         /usr/share/openvanilla/OVIMGeneric/pinyin.cin \
         /usr/share/openvanilla/OVIMGeneric/cs-oi.cin \
         /usr/share/fonts/fira-code/FiraCode-Regular.ttf \
         /usr/share/man/zh_CN/man1/ls.1.gz \
         /usr/bin/pacman /usr/bin/repo-add /etc/pacman.conf \
         /usr/local/lib/meson/meson.py /usr/local/bin/ninja \
         /usr/bin/curl /usr/lib/libarchive.so \
         /usr/bin/which /usr/bin/wget /usr/bin/fd /usr/bin/rg \
         /usr/bin/bat /usr/bin/htop \
         /usr/bin/sudo /usr/sbin/visudo /etc/sudoers \
         /usr/bin/git \
         /usr/share/themes/Rea-Dark/index.theme \
         /root/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml \
         /root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml \
         /usr/local/repo/lfscn/lfscn.db.tar.gz; do
    [ -e "$f" ] || die "extras self-check: missing $f"
done

log '==> extras installed'
node --version 2>/dev/null || true
/opt/rust/bin/rustc --version 2>/dev/null || true
pwsh --version 2>/dev/null || true
nvim --version 2>/dev/null | head -1 || true
pacman --version 2>/dev/null | head -1 || true
