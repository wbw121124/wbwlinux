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

fd --version
rg --version | head -1
bat --version
htop --version
wget --version | head -1

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
szsz 树状数组
xds 线段树
zxs 主席树
lcxds 李超线段树
jsjxds 吉司机线段树
kcjhxds 可持久化线段树
kcjphs 可持久化平衡树
phs 平衡树
avl AVL树
hhs 红黑树
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
dij Dijkstra
spfa SPFA
flyd 弗洛伊德
bemft 贝尔曼福特
zxscs 最小生成树
cxscs 次小生成树
klskr 克鲁斯卡尔
pm Prim算法
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
%chardef end
CINEOF
grep -q '动态规划' "$OVIM_DIR/cs-oi.cin" || die "extras: cs-oi.cin content broken"

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
grep -q '^font-name=Fira Code,WenQuanYi Micro Hei$' /etc/ucimf.conf \
    && grep -q '^font-size=16$' /etc/ucimf.conf \
    || die "extras: ucimf.conf font alignment failed"

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
EOF

cat > /usr/local/bin/fbterm-zh << 'EOF'
#!/bin/sh
# Chinese-capable framebuffer terminal. Falls back to a plain shell if the
# framebuffer or CJK font is unavailable so the session never dies silently.
# zh_CN applies ONLY inside fbterm: the vconsole has no CJK glyphs, so any
# localized text outside fbterm would render as boxes. Fallback shells stay
# on the inherited C.UTF-8 environment.
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
export PATH="/usr/local/sbin:/usr/local/bin:/opt/rust/bin:/opt/nvim-linux-x86_64/bin:/opt/microsoft/powershell/7:/usr/sbin:/usr/bin:/sbin:/bin"
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
NVIM_V="$(nvim --version 2>/dev/null | sed -n 's/^NVIM //p' | tr -d v)"
if [ -z "$NVIM_V" ]; then NVIM_V="stable"; fi

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
pkg_register neovim "$NVIM_V" "Neovim editor (prebuilt)" \
    /opt/nvim-linux-x86_64 /usr/local/bin/nvim
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
         /usr/local/repo/lfscn/lfscn.db.tar.gz; do
    [ -e "$f" ] || die "extras self-check: missing $f"
done

log '==> extras installed'
node --version 2>/dev/null || true
/opt/rust/bin/rustc --version 2>/dev/null || true
pwsh --version 2>/dev/null || true
nvim --version 2>/dev/null | head -1 || true
pacman --version 2>/dev/null | head -1 || true
