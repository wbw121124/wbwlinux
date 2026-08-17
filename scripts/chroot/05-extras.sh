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
# Neovim stable (official prebuilt)
# =====================================================================
if [ ! -e /opt/nvim-linux-x86_64/bin/nvim ]; then
    log "==> Neovim stable"
    tar xf nvim-linux-x86_64.tar.gz -C /opt
    ln -sfv /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    nvim --version | head -1
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
cat > /etc/nanorc << 'EOF'
set utf8
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
font-name=WenQuanYi Micro Hei
font-size=16
font-width=0
font-height=0
color-foreground=191,191,191
color-background=0,0,0
text-format=1
cursor-shape=0
cursor-interval=500
EOF

cat > /usr/local/bin/fbterm-zh << 'EOF'
#!/bin/sh
exec env LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 fbterm --fontname="WenQuanYi Micro Hei" --font-size=16 -n 2
EOF
chmod +x /usr/local/bin/fbterm-zh

# root login shell convenience (auto fbterm on tty1)
cat > /root/.bashrc << 'EOF'
# LFS-CN live environment
if [ "$TERM" = "linux" ] && [ -x /usr/local/bin/fbterm-zh ] && [ -z "$FBTTERM" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export FBTTERM=1
    exec /usr/local/bin/fbterm-zh
fi
EOF

log '==> extras installed'
node --version 2>/dev/null || true
/opt/rust/bin/rustc --version 2>/dev/null || true
pwsh --version 2>/dev/null || true
nvim --version 2>/dev/null | head -1 || true
