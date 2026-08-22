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
    ./configure --prefix=/usr CXXFLAGS="-O2 -Wno-narrowing"
    make -j"$NPROC"
    make install
    cd "$DL"
    rm -rf "libucimf-$UCIMF_VER"
fi

if [ ! -e /usr/lib/ucimf/openvanilla.so ]; then
    log "==> ucimf-openvanilla $OV_BRIDGE_VER"
    tar xf "ucimf-openvanilla-$OV_BRIDGE_VER.tar.gz"
    cd "ucimf-openvanilla-$OV_BRIDGE_VER"
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

# compose/preedit/candidate window font must cover CJK
if [ -e /etc/ucimf.conf ] && ! grep -q '^font-name=WenQuanYi Micro Hei' /etc/ucimf.conf; then
    sed -i 's|^font-name=.*|font-name=WenQuanYi Micro Hei|' /etc/ucimf.conf
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
font-names=Fira Code,WenQuanYi Micro Hei
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
# Chinese-capable framebuffer terminal. Falls back to a plain shell if the
# framebuffer or CJK font is unavailable so the session never dies silently.
export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
FONT_NAMES="Fira Code,WenQuanYi Micro Hei"
if [ ! -e /dev/fb0 ]; then
    echo "fbterm-zh: /dev/fb0 not available, staying on plain console" >&2
    export FBTTERM=1
    exec bash -i
fi
if command -v fbterm_ucimf >/dev/null 2>&1; then
    # ucimf input method: Ctrl+Space on/off, Ctrl+Shift switch IMs
    if fbterm --font-names="$FONT_NAMES" --font-size=16 -i fbterm_ucimf 2>/dev/null; then
        exit 0
    fi
fi
if fbterm --font-names="$FONT_NAMES" --font-size=16 2>/dev/null; then
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
export PATH="/opt/rust/bin:/opt/nvim-linux-x86_64/bin:/opt/microsoft/powershell/7:$PATH"
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

# hard self-check: input method stack + fonts must all be in place
for f in /usr/bin/fbterm /usr/bin/fbterm_ucimf \
         /usr/lib/libucimf.so /usr/lib/ucimf/openvanilla.so \
         /usr/lib/openvanilla/OVIMGeneric.so \
         /usr/share/openvanilla/OVIMGeneric/pinyin.cin \
         /usr/share/fonts/fira-code/FiraCode-Regular.ttf; do
    [ -e "$f" ] || die "extras self-check: missing $f"
done

log '==> extras installed'
node --version 2>/dev/null || true
/opt/rust/bin/rustc --version 2>/dev/null || true
pwsh --version 2>/dev/null || true
nvim --version 2>/dev/null | head -1 || true
