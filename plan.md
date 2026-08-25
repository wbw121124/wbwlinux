# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：**OVIMGeneric 补丁 hunk header 行数全错导致 malformed patch + 多余 } 已修复，neovim 改为源码编译（/usr/local），新增 NetworkManager/VS Code/Firefox pacman 包（仓库可安装，默认未安装），git 2.55.0 源码编译**。

## 根因三十二（run#88 QEMU 实证，已修）：OVIMGeneric locality bonus 补丁路径静默跳过
**host 侧 05-extras.sh 将 `chroot/ovimgeneric.patch` 拷贝到 `$LFS_ROOT/build/chroot/ovimgeneric.patch`（chroot 内 `/build/chroot/ovimgeneric.patch`）；但 chroot 侧 05-extras.sh 第 502 行检查 `$SCRIPTS_DIR/ovimgeneric.patch`（`/build/ovimgeneric.patch`）——少了 `chroot/` 子目录 → `[ -f ]` 永远 false → patch 静默跳过，locality bonus / dedup / fuzzy matching / weak match fallback 全部未编译进 OVIMGeneric.so。**
- 对比：zhuyin.cin 在 host 第 96 行额外拷贝了一份到 `$LFS_ROOT/build/zhuyin.cin`（`/build/zhuyin.cin`），故 chroot 第 1391 行 `cp $SCRIPTS_DIR/zhuyin.cin` 能找到——ovimgeneric.patch 缺少同款额外拷贝。
- 修复：chroot/05-extras.sh 第 502 行改为 `$SCRIPTS_DIR/chroot/ovimgeneric.patch`（与 host 实际拷贝路径一致）；同时将 silent skip 改为 die（防止补丁文件再次消失时静默回归）。

## 根因三十三（run#88 QEMU 实证，已修）：polkit-gnome agent 25s 超时
**startx 进入 XFCE 后，polkit-gnome-authentication-agent-1 通过 `/etc/xdg/autostart/polkit-gnome-authentication-agent-1.desktop` 自动启动，但 Arch 二进制闭包未包含 polkitd 守护进程（`org.freedesktop.PolicyKit1` 服务不存在）→ agent 向 DBus activation 发起 StartServiceByName → 25s 超时后报错退出。整个会话启动额外卡顿 25s。**
- 修复：06-xorg-xfce.sh 包导入后，删除 polkit-gnome autostart desktop 文件（无 polkitd → agent 无用）。并加注释说明原因。

## 根因三十四（run#88 QEMU 实证，已修）：systemctl --user import-environment 失败噪声
**xfce4-session 的 xinitrc（`/etc/xdg/xfce4/xinitrc`）在 startxfce4 调用链中尝试 `systemctl --user import-environment`，但 LFS live 环境无 PAM / systemd --user 会话 → 进程退出 status 1 → 控制台输出 `Failed to import environment: Process org.freedesktop.systemd1 exited with status 1`。非致命但噪声大。**
- 修复：06-xorg-xfce.sh 包导入后，用 sed 注释掉 `/etc/xdg/xfce4/xinitrc` 中含 `systemctl --user` 的行，保留其余逻辑。加自检断言。

## 根因三十五（Rea-Dark 主题，新增）：XFCE 默认主题
**XFCE 4.20 使用默认 gtk-theme（通常是 Adwaita），无定制暗色主题。新增 Rea-Dark（orchyn/XFCE，含 gtk-2.0 + gtk-3.0 + xfwm4）作为默认主题，通过 xfconf 写入 root 用户配置。**
- 版本锁定：GitHub commit `1a422b0ec86e9fc6d349d17a770d933dbf2c00f8`（2026-02-24）
- 路径：`/usr/share/themes/Rea-Dark`；xfconf 默认写入 `Net/ThemeName=Rea-Dark` + `Xfwm4/Theme=Rea-Dark`
- 注意：xfwm4 compositing 在 QEMU 软件渲染 (llvmpipe) 下有 `Unsupported GL renderer` 警告 → 默认关闭 compositing（`use_compositing=false`）

## 根因三十一（run#87 实证，已修）：sudo 自检断言 visudo 安装路径错误
**run#87（from-base）config+extras 其余全部通过（15 包 pacman 注册成功、cs-oi.cin/zhuyin.cin 安装、OVIMGeneric 模块索引、`pacman -Q` 列表正常），唯一失败点为 sudo 尾部自检 die：`ERROR: extras self-check: missing /usr/bin/visudo`。**
- 证据：run#87 日志 `libtool: install: /bin/sh ../../scripts/install-sh -c -o 0 -g 0 -m 0755 .libs/visudo /usr/sbin/visudo` —— sudo 上游默认 `sbindir=${prefix}/sbin`，`--prefix=/usr` 下 visudo 实装 **/usr/sbin/visudo**；而 chroot/05-extras.sh 的 pkg_register 文件清单与尾部硬性自检均写 /usr/bin/visudo → pkg 注册阶段先报 `WARNING: pkg sudo: optional path missing, skipped: /usr/bin/visudo`（optional 跳过不阻断），随后自检 `[ -e ] || die` 中止。
- 与根因八（node 双 v）/二十六（下载 map 键名）同型教训：**两侧路径必须逐字一致，断言以实际安装布局为准**。
- 修复：chroot/05-extras.sh 两处 `/usr/bin/visudo` → `/usr/sbin/visudo`（pkg_register 清单 + 自检列表）。不采用 `configure --sbindir=/usr/bin` 强改上游布局（secure_path 已含 /usr/sbin，功能无差）。
- 附带：readme.md 包表格补 sudo 行（上轮 a423ff2 新增包时遗漏更新 README）。

## 2026-08-23 扩展：CLI 工具包 + X.Org/XFCE + 竞赛码表 + 三处根因修复
**用户需求五项：①node 不在 PATH 且无 which；②新增 fd/rg/bat/curl/wget/htop/xorg/xfce（pacman 包、不编译）；③pacman CacheDir 报错；④ucimf 候选窗字体与终端不一致；⑤计算机/信息学竞赛中文码表。**
- **根因二十三（node PATH）**：`/etc/profile` 用 `PATH="/opt/...:$PATH"` 前置继承值——agetty 自动登录的 shell 由 systemd 拉起时 PATH 可能缺 `/usr/local/bin` → node 找不到。修复：04-sysconfig.sh 与 chroot/05-extras.sh 的 .bashrc 都改为**完整显式 PATH** `/usr/local/sbin:/usr/local/bin:/opt/rust/bin:/opt/nvim-linux-x86_64/bin:/opt/microsoft/powershell/7:/usr/sbin:/usr/bin:/sbin:/bin`。
- **根因二十四（ucimf 字体不一致）**：libucimf font.cpp 抄自 fbterm，`setInfo` 把 font-name 整串交给 FcNameParse（逗号=family 列表分隔符），但 /etc/ucimf.conf 此前只配了文泉驿单字体 → 候选窗西文与 fbterm 主区（Fira Code 优先）字形不一致。修复：sed 改为 `font-name=Fira Code,WenQuanYi Micro Hei`（29 字符 < mFontNames 64 字节缓冲 ✓）+ `font-size=16` 与终端一致，grep 断言。
- **根因二十五（pacman CacheDir）**：fstab `tmpfs /var` 每次开机遮蔽 squashfs 内目录 → pacman 报 `failed to resolve path '/var/cache/pacman/pkg/' passed to 'CacheDir'`。修复：`/usr/lib/tmpfiles.d/lfscn-pacman.conf` 两行 d 规则（/var/cache/pacman/pkg 与 /var/log）让 systemd-tmpfiles 开机重建 + extras 内立即 --create 并 test 断言。
- **CLI 工具包**（版本 2026-08-23 实证）：fd v10.4.2 / ripgrep 15.2.0 / bat v0.26.1 官方 musl 静态二进制直接 install；htop 3.5.3-1 Debian pool deb 解包（仅依赖 ncurses/libc）；wget 1.25.0 源码编译（Debian 构建链 gnutls 缺失 → `--with-ssl=openssl`，LFS stages 无 wget 已 grep 实证）；curl 已由 pacman 五连编译（8.21.0）只补注册；which 为最小 POSIX sh 实现。六包全部 pkg_register 入 [lfscn] 仓库（8→14 包）。env.sh 加 FD_VER/RIPGREP_VER/BAT_VER/HTOP_DEB/WGET_VER；宿主 05-extras.sh 加 5 个下载 URL。
- **cs-oi.cin 竞赛码表**（220 词条，本地校验：码唯一 ✓ 全 [a-z]+ ✓ keyname 26 字母全覆盖 ✓）：简拼缩写→算法竞赛中文术语（dp→动态规划、bcj→并查集、xds→线段树、zdl→最短路等），OVIMGeneric 运行时扫描 *.cin 自动加载（无 CIN-Defaults 仅禁用达长保护，实证 pinyin.cin 多字词条可行），参与 Ctrl+Shift 轮换。
- **X.Org+XFCE 二进制闭包导入**（新 scripts/chroot/06-xorg-xfce.sh + arch-resolve.py）：
  - 设计：下载 {core,extra}.db → python3 解析 desc 做 BFS 闭包（种子 xorg-server/xorg-xinit + xfce4-session/panel/wm/desktop/settings/appfinder/xfconf/garcon/thunar/thunar-volman/tumbler/xfce4-terminal/mousepad）→ SKIP 集=LFS 已有名（glibc/gcc-libs/coreutils/dbus/python 等，**不含** krb5/libtirpc/libxml2——LFS 没有）→ tar `--skip-old-files` 解包到 /（已有文件 LFS 胜出，仅新增文件落盘）→ ldconfig+glib schemas+pixbuf loaders+desktop/mime/icon cache+fccache 刷新 → /root/.xinitrc `exec dbus-launch --exit-with-session startxfce4`。
  - 防线：闭包解析绝不引入 Arch glibc（README「Arch 源保持禁用」守则的受控例外）；解压前 df 检查 >3GB；闭包 <50 包 die；种子从仓库消失 die；自检断言 Xorg/startx/startxfce4/libX11.so.6/libgtk-3.so.0。
  - kernel-live.fragment 加 DRM 块：DRM=y、FBDEV_EMULATION=y、VIRTIO_GPU=y（QEMU）、BOCHS=y、I915/AMDGPU/RADEON=m（真机）——Xorg modesetting 需要 KMS。
- 本地验证：bash -n 全部脚本通过；arch-resolve.py 合成 fixture 端到端测试（SKIP 生效/glibc>=版本剥离/libx11|libx12 alternates/BFS 传递闭包/repo 归属正确/坏依赖仅 WARN/空闭包与种子丢失 FATAL）全部符合预期。
- **根因二十六（run#65 实证）**：宿主下载 map 键用了缩短名（fd-10.4.2.tar.gz），chroot 脚本按上游资产原名开文件（fd-v10.4.2-x86_64-unknown-linux-musl.tar.gz）→ tar ENOENT。与根因八（node 双 v）同类：**两侧文件名必须逐字一致**。修复：map 键改为上游 release 资产原名（ripgrep/bat 同改；htop/wget 原本一致未动），并在 urls 注释中立规。
- **根因二十七（run#66/67 实证）**：Debian 构建的 htop 链接平名 `libtinfo.so.6`，而 LFS ncurses 6.6 不装任何独立 tinfo 库（libtinfow.so.6 也不存在，die 守卫触发）→ 弃 deb 改源码编译（htop 3.5.3 tarball 自带 configure，pkg-config 解析 LFS ncursesw.pc，约 30 秒）。教训：Debian 预编译二进制只适合纯数据或零 C 库依赖的包。
- **根因二十八（run#68 实证，CI 日志直接抓到 install 行）**：`--prefix=/usr` 下 automake 默认 `sysconfdir=${prefix}/etc` → libucimf 的 `make install` 一直把 ucimf.conf 装到 **/usr/etc**（日志：`install -c -m 644 ucimf.conf '/usr/etc'`），运行期 UCIMF_CONF 宏同样指向 /usr/etc。历史代码 `[ -e /etc/ucimf.conf ] && sed` 因守卫而**静默空转**（候选窗字体其实一直是默认值），后加的 /etc/ucimf.conf 自检断言从未被绿跑覆盖 → 本轮改为硬性 sed 后立刻爆「无法读取」。修复：libucimf configure 加 `--sysconfdir=/etc`（conf 安装点与 UCIMF_CONF 运行期路径同时归位），#24 字体对齐自此才真正生效。教训：autotools 包配 --prefix 时必须显式核对 sysconfdir/localstatedir。
- 风险：Arch 滚动仓库快照漂移（新库 soname 或依赖图变化）→ 解析器 WARN 不致命，仅种子消失才 die；xfwm4 合成标题栏需 GTK3 主题（Adwaita 随 gtk3 包自带）；QEMU 测试用 `-device virtio-gpu` 或默认 std VGA（bochs 驱动覆盖）。

## 根因二十九（run#69 实证，已修）：Arch 仓库下载 SSL 证书验证失败
**config-extras 阶段 06-xorg-xfce.sh 的 fetch() 用 curl 下载 core.db/extra.db 时，chroot 内缺 ca-certificates → curl 报 "unable to get local issuer certificate" → 三镜像全部失败 → arch-import 中止。**
- 证据：run#69 日志 `curl: (60) SSL certificate OpenSSL verify result: unable to get local issuer certificate (20)` 三次重试后 `ERROR: arch-import: cannot download core.db from any mirror`。
- 修复（2026-08-24）：`scripts/chroot/06-xorg-xfce.sh:41` fetch() 的 curl 加 `-k`（`--insecure`）跳过证书验证。chroot 不装 ca-certificates 也能下载，风险可控（仅从已知 Arch 官方镜像拉取只读索引/包）。

## 根因十四（用户 QEMU 实测报告，已修）：登录界面中文乱码、fbterm 内正常
**vconsole（eurlatgr）无 CJK 字形，但 /etc/locale.conf 全套 zh_CN.UTF-8 被 systemd PID1 与所有服务继承 → 开机状态消息 / agetty/login 横幅被本地化为中文 → 纯控制台渲染成方块；fbterm 内经 freetype+WQY 渲染故正常。**
- 修复（三层，2026-08-22）：
  1. GRUB 两菜单项内核参数加 `locale.LANG=C.UTF-8 locale.LC_MESSAGES=C.UTF-8`（systemd.locale(7) 的 locale.* cmdline 覆盖 locale.conf）→ PID1/服务/getty/login 输出全英文，登录界面不再出现任何中文；
  2. `/etc/profile` TERM=linux 分支补 `export LC_ALL=C.UTF-8`（LC_ALL 压制继承的全部 LC_*，纯控制台会话彻底英文化——否则 LC_TIME=zh_CN 仍会让 ls/date 吐中文日期变方块）；
  3. fbterm-zh 把顶层 `export LANG/LC_ALL=zh_CN` 改为仅以 env 前缀作用于 fbterm 调用本身；回退到纯控制台的 bash 分支继承 C.UTF-8。
- 字体优先级（同请求「Fira Code 高于中文字体」）：fbterm 源码证实多字体按字形回退安全（src/font.cpp `fontIndex()` 遍历 FcFontSort 字体列表取首个含该字形的字体 → "Fira Code,WenQuanYi Micro Hei" 西文走 Fira、CJK 回落 WQY）；新增 `/etc/fonts/local.conf` 将 Fira Code 置于 monospace/sans-serif/serif prefer 首位并断言 `fc-match monospace` 解析到 Fira Code。

## 输入法栈 + Fira Code 扩展（2026-08-22，已实施，待 run#49+ 验证）
**目标：live 环境在 fbterm 内可输入中文。无 X11 → ibus/fcitx（X11 IM 平台）不适用且依赖链巨大；选型 ucimf 生态：libucimf（框架）→ ucimf-openvanilla（桥接 IMF 插件 /usr/lib/ucimf/openvanilla.so）→ openvanilla-modules（OVIMGeneric 引擎 /usr/lib/openvanilla/ + zh_CN .cin 码表）→ fbterm-ucimf（`fbterm -i fbterm_ucimf` 前端）。**
- 改动：
  - `scripts/env.sh`：UCIMF_VER=2.3.8、OV_BRIDGE_VER=2.10.11、FBTERM_UCIMF_VER=0.2.9、OV_MODULES_COMMIT=28d0dd6（pkg-ime/openvanilla-modules GitHub 快照固定 commit，无官方 release tarball）、FIRACODE_VER=6.2。
  - `scripts/05-extras.sh`：宿主侧新增下载 libucimf/ucimf-openvanilla/fbterm-ucimf（均 deb.debian.org orig tarball）+ openvanilla-modules（codeload 固定 commit）+ Fira_Code_v6.2.zip（github release）。5 个 URL 已 HEAD 200 实测。
  - `scripts/chroot/05-extras.sh`：四连源码构建（全部 `-Wno-narrowing` 防 GCC15 narrowing）；openvanilla-modules 用 `--disable-asia --enable-zh_CN` 只装 12 张 zh_CN 码表（pinyin/pinyin0/shuangpin/wubizixing/wbx/zhengma 等 → /usr/share/openvanilla/OVIMGeneric/）；/etc/ucimf.conf 字体改 WQY（候选窗 CJK 可渲染）；Fira Code 六个 TTF → /usr/share/fonts/fira-code/（chroot 无 unzip → `python3 -m zipfile -e` 解压，Python 为 ch8 自建）；fbtermrc 键名修正 `font-name`→`font-names`（fbterm 1.7 实际键名），主字体 "Fira Code,WenQuanYi Micro Hei"；fbterm-zh 启动器优先 `-i fbterm_ucimf`（Ctrl+Space 开关输入法、Ctrl+Shift 切换），失败逐级回退纯 fbterm → bash；脚本尾部硬性自检（fbterm_ucimf/libucimf.so/openvanilla.so/OVIMGeneric.so/pinyin.cin/FiraCode-Regular.ttf 缺一即 die）。
- 依赖核实（本地解包审计源码）：libucimf 需 ltdl（AC_CHECK_LIB 强制）+ freetype2/fontconfig（PKG_CHECK_MODULES）——LFS ch8 已含 libtool-2.5.4（ltdl）与 pkgconf-2.5.1（30-ch8-stage.sh:583/:304），libucimf.pc 装 $(libdir)/pkgconfig（Makefile.am:21）→ fbterm-ucimf 的 PKG_CHECK_MODULES(libucimf) 可解析；openvanilla-modules 的 sqlite3 检查非致命且源码未用；LIBDIR/DATADIR 由 AC_DEFINE_DIR 注入 ✓；码表安装路径与 ovimf.cpp 搜索路径（DATADIR/openvanilla/OVIMGeneric/）吻合 ✓。
- 用法：tty1 自动登录进 fbterm 后 Ctrl+Space 开关中文输入；Ctrl+Shift 在拼音/双拼/五笔86/郑码等间切换。
- **bash PATH 集成（同日）**：`/etc/profile`（04-sysconfig.sh）与 `/root/.bashrc`（05-extras.sh，覆盖 fbterm 内层 shell 与纯控制台回退的非登录交互 shell——它们不读 profile）均前置 `export PATH="/opt/rust/bin:/opt/nvim-linux-x86_64/bin:/opt/microsoft/powershell/7:$PATH"`。
- 风险（Windows 宿主无法本地编译验证）：2010 年代 C++ 在 GCC15 下除 narrowing 外或现缺头文件类问题 → 若 extras job 失败看首个报错包补 sed/-include；老代码假定 GNU ld `-Wl,-E -Bsymbolic`（x86_64 Linux OK）。改 scripts/** 触发 ccache 全 miss → toolchain 重编 ~17min（预期内）。

## 根因十三（QEMU 实测实证，已彻底修复：Option A 双保险 + Option B 根治）
**Live overlay 的可写 upper 层随 switch_root + fstab 的 /run tmpfs 重挂而脱离 → /var 与 /etc 落到只读 squashfs 下层 → 必须写 /var 的 systemd 单元（timesyncd/logind/journal-catalog-update）在 STATE_DIRECTORY 步失败（ENOENT），hwdb-update/update-done 写 /etc 也失败。**
- 证据（客观）：`Failed at step STATE_DIRECTORY spawning .../systemd-timesyncd: No such file or directory` + `[FAILED] Failed to start Network Time Synchronization / Rebuild Journal Catalog / User Login Management`；三单元共性 = 启动必须向 /var 写（timesync、linger、catalog/database）；二进制/链接器/var 树均齐全 → 排除静态缺失。
- 设计缺陷（init 脚本，`chroot/06-kernel-initramfs.sh`）：`mount -t tmpfs tmpfs /run/overlay` 后，overlay 却用 `upperdir=/run/upper,workdir=/run/work`（位于 initramfs 根 tmpfs 上，**不在** /run/overlay 那个 tmpfs 内）→ 该 tmpfs 白挂、upper/work 落在 initramfs 根 fs。switch_root 拆除 initramfs 根、且 fstab 的 `tmpfs /run` 让 systemd 用全新 tmpfs 覆盖 /run → overlay upper（在旧 initramfs /run 上）与运行期 / 脱离 → /var、/etc 只读。
- 内核配置无缺失（kernel-live.fragment：OVERLAY_FS=y / BLK_DEV_LOOP=y / TMPFS=y），排除 CONFIG 类原因。
- 修复分两步：
  - **Option A（b052c27 + a6d7a55，已实测）**：fstab 增 `tmpfs /var` + `tmpfs /home`，/var 直接以 tmpfs 覆盖，与 overlay 解耦 → 原三个单元修复；但 /etc 仍只读 → 残留 2 个 FAILED（Rebuild Hardware Database / Update is Completed，写 /etc 失败）。
  - **Option B 根治（4c6cb3e，已实测）**：把 upper/work 移入专用 tmpfs 内：`upperdir=/run/overlay/upper,workdir=/run/overlay/work`。该 tmpfs 挂载点在 systemd 堆叠 /run 后仍存活（被覆盖但未卸载），overlay 钉住 upperdir dentry → **整个根（含 /etc）经 copy-up 保持可写**。/var、/home 的 tmpfs 保留作双保险。
- **CI run#48 产物实测（QEMU，权威构建）**：`mount | grep overlay` → `upperdir=/run/overlay/upper`；`echo test > /etc/test` → ETC_WRITABLE_OK；`mkdir -p /mnt/lfs` → MNT_OK；`df -h /` → overlay 987M（13M 已用，可写）；引导干净进入 `lfs-cn login: root` 自动登录，无 FAILED。sha256 校验通过（zip 21c1c433...；ISO 780,879,872 B）。
- CI 自动验证建议：iso job 加 qemu 冒烟步骤（01-host-prep 装 qemu-system-x86_64），`qemu-system-x86_64 -cdrom ...iso -m 2G -smp 2 -boot d -nographic -serial stdio` 以 `console=ttyS0` 引导并 `grep` 串口日志，断言三个 FAILED 串不再出现、`/etc` 可写；超时兜底（TCG 无 KVM，需放宽容限）。


## 根因一（已修复，run#21 实证、run#22 验证）
**gettext configure 报 "cannot run C compiled programs" 的真正根因：toolchain 快照的裸 `--exclude=sys`（basename 匹配）把 `/usr/include/sys/` 整个排除出快照 → chroot 内所有带 `stdio.h` 的 conftest 编译失败（`sys/cdefs.h: No such file or directory`）。**
1. `snapshot()` 原命令 `tar --zstd -C / --exclude=proc --exclude=sys --exclude=dev ... -cf - "${LFS_ROOT#/}"`：GNU tar 的 `--exclude` 按 **basename** 匹配任意层级，`sys` 命中了 `mnt/lfs/usr/include/sys/` → `/usr/include/sys/cdefs.h` 从未进入快照。
2. 冒烟测试程序不含任何 `#include`，故一直 SMOKE-OK 掩盖问题；autoconf 的 conftest 带 `<stdio.h>` 才暴露。
3. run#21（278b3bd，探针版本）实证：`/usr/include/features.h:540:12: fatal error: sys/cdefs.h: No such file or directory`、`manual_compile_rc=1`；glibc-2.43.tar.xz 内确认 `include/sys/cdefs.h` 与 `misc/sys/cdefs.h` 存在。
4. 修复 + 验证：cb86455 将 exclude 全部锚定为 `${LFS_ROOT#/}/proc`、`/sys`、`/dev`、`/run`、`/ccache`、`/ccache-wrap`；run#22 证明 ch7 全通过。

## 根因二（run#22 实证，待修）
**8.17 Tcl 失败：`tcl8.6.17-src.tar.gz` 解压出的顶层目录是 `tcl8.6.17/`（不带 `-src`），而 pkg_run 的 `$dir` 用了 tarball 名 `tcl8.6.17-src` → `cd "$dir"`（common.sh:31）失败。**
- 证据：run#22 base job 日志尾部 `[17:23:47] ==> build tcl8.6.17-src` → `/build/common.sh: line 31: cd: tcl8.6.17-src: No such file or directory` → `bash: line 2: cd: unix: No such file or directory` → `##[error]Process completed with exit code 1.`；本地 `tar -tzf tcl8.6.17-src.tar.gz` 实测顶层为 `tcl8.6.17/`。
- 修复方案（已实施）：pkg_run 解压后若 `$dir` 目录不存在 → `tar -tf "$tarball" | awk -F/ 'NF>1{print $1; exit}'` 取真实顶层目录名并 `mv` 重命名成 `$dir`（保持 body 相对路径与清理逻辑不变）；用 tar 列表而非 find，避免 /sources 残留目录干扰。已用 Git Bash 本地模拟验证（含旧残留 tcl8.6.17/ 干扰场景）。

## 根因三（run#24 实证，run#28 深化，已修）
**8.82 util-linux-2.41.3 失败：`tests/run.sh` 前置检查 `$top_builddir/test_ttyutils` 不存在（测试程序未编译）→ 输出 "Tests not compiled! Run 'make check-programs' to fix the problem." 并 `exit 1`；脚本只跑了 `make` 未跑 `make check-programs`。**
- 证据：run#24 base job 日志尾部 `[19:06:05] ERROR: build of 'util-linux-2.41.3' failed (rc=1)`；util-linux 编译全部 CCLD 成功，仅 run.sh 检查失败。run.sh 源码（v2.41.3）确认该检查逻辑（`-z "$SYSCOMMANDS" -a ! -f "$top_builddir/test_ttyutils"`）。
- 修复方案（已实施）：`make` 后加 `make check-programs`；`bash tests/run.sh ... || true`（测试为书中可选步骤，CI 宿主内核缺 CONFIG_SCSI_DEBUG/CONFIG_CRYPTO_USER_API_HASH 等，部分测试必然失败，不应阻断构建）。
- **run#28 深化实证：`check-programs` 生效后测试进入实际运行，但 `tests/run.sh` 挂死**：运行约 1 分钟（大量 OK/SKIPPED 输出正常），到 `lsns: NETNSID compare to ip-link` 后 2h 无任何输出（该测试需 `unshare -n` 新建网络命名空间，GitHub runner 容器 seccomp 屏蔽 → 挂起不报错）→ 整包触发 pkg_run 7200s 看门狗（run#28 `TIMEOUT ... exceeded 7200s (rc=124)`）。ps 快照显示无活跃用户进程，free 显示内存充裕（14Gi 可用、swap 3Gi 未用）→ 排除内存假说，实锤为测试挂死。
- 修复（run#28 后，待验）：`timeout 600 bash tests/run.sh ... || true` —— 测试 10 分钟兜底，超时/失败均不阻断构建。

## 待办任务
- [x] 1-6（历史，见下）ccache-wrap 根治 → run#17 toolchain 通过。
- [x] 7. gettext 根因定位（sys/cdefs.h）与修复（cb86455）→ run#22 ch7 全过。
- [x] 8. **修 pkg_run 顶层目录名不匹配**（tcl8.6.17-src 解压出 tcl8.6.17/）→ 已修（common.sh：`tar -tf` 取真实顶层名 + mv 重命名）→ run#24 验证通过（越过 Tcl 至 8.82 util-linux）。
- [x] 9a. **修 util-linux 测试前置**（make check-programs + run.sh 失败不阻断）→ run#28 实证已越过 "Tests not compiled!" 进入实际测试，但发现 lsns 挂死 → 补 `timeout 600`（见根因三深化）→ 待 run#29 验证。
- [x] 9b. **pkg_run 超时看门狗（防静默卡死）**（common.sh）→ 包构建外包 `timeout -k 60 ${PKG_TIMEOUT:-7200} bash -e -c`；超时(124)时保留残留树 + df/mount/ps 快照后 die 显式报错，避免再静默挂满 6h。改 scripts/ → ccache 全 miss，run#26 toolchain 重编（实证仅 ~17min，可接受）。
- [x] 9c. **systemd 全量编译卡死修复（swap 兜底）**（workflow base job + common.sh）→ 宿主加 swap 防 GCC -O3 内存尖峰 cgroup 冻结；超时快照加 free -h/meminfo。run#27 因镜像自带 /swapfile 冲突失败 → run#28 实证 swap 生效（Swap: 3.0Gi 就位），systemd-259.1 编译通过（此轮 j2 无卡死）；systemd 卡死根因仍存疑，但本轮未复现。
- [ ] 9. ch8 剩余（8.79 D-Bus 起）逐个处理后续失败直至 ISO → **run#30 ch8 全部完成（8.85/8.86 通过）**；后续链条：config+extras（fbterm URL 已修，run#31 验证）→ iso job（内核/initramfs/squashfs/GRUB，尚未跑过，新领域）。
- [x] 11. **Live 引导后 /var 只读 → systemd 三个写 /var 单元 STATE_DIRECTORY 失败（根因十三）** → 双保险：(a) fstab 增 `tmpfs /var` + `tmpfs /home`；(b) initramfs init 脚本在 switch_root 前对 `/newroot/var`、`/newroot/home` 挂 tmpfs。本地 ISO 已用 (b) 手工重打包修复（见下），CI 双法均生效。待 QEMU 验证三 FAILED 消失。
- [ ] 12. **输入法栈（libucimf→openvanilla→OVIMGeneric→fbterm_ucimf）+ Fira Code** → 已实施（2026-08-22，见顶部专节），待 run#49+ 验证 extras 四连构建通过 + QEMU 内 Ctrl+Space 中文实测。
- [ ] 13. **根因十四（登录界面中文乱码）+ Fira Code 字体优先级** → 已实施（2026-08-22，见「根因十四」），待 run#49+ QEMU 复测：登录界面无乱码、fbterm 西文为 Fira Code、Ctrl+Space 中文输入可用。
- [x] 14. **体验补全包（2026-08-22，[iso:from-base] 验证）**：
  - **根因十五：nano 启动报 `/etc/nanorc: unknown option "utf8"`** —— `set utf8` 在 nano 6.x 起移除（UTF-8 随 locale 自动启用），chroot 的 nano 8.7.1 每次启动报错。修复：删除该行并注释原因。
  - **run#50 失败复盘（两个新根因，已修，待 run#51 验证）**：
    - **根因十六：man-pages-zh deb 路径错配** —— extras 全部下载到 `/root/downloads` 且 chroot 脚本 `cd` 该目录用相对路径构建；man-pages-zh 块误用 `$SOURCES`（=/mnt/lfs/sources，LFS 书源码目录，extras 不往那放东西）→ `ar: No such file or directory`。修复：改相对路径（deb 已确认正常下载，17 文件齐）。
    - **根因十七：fontconfig 根本不加载 local.conf** —— LFS 构建的 fontconfig 2.17.1 `/etc/fonts/fonts.conf` 只有 `<include>conf.d</include>`（注释声称 customizations belong in local.conf 但无对应 include 行；.ci/sfs 快照实证）→ 写的 `/etc/fonts/local.conf` 完全被忽略 → run#50 日志 `WARNING: 'monospace' did not resolve to Fira Code -> wqy-microhei.ttc`。修复：prefer 规则改写入 `/etc/fonts/conf.d/99-fira-code-prefer.conf`（99 前缀排序最后=优先级最高）。
  - **man 中文手册（man-pages-zh 1.6.4.5）**：上游 1.6.x 构建需 cmake+OpenCC（源码为繁体、构建期 t2s 转简体——1.6.4.0/1.6.4.5 本地解包实证），chroot 无此二者 → 改用 Debian 预编译 `_all.deb`（纯数据，含已转简体 gz 页面）：`ar p ... data.tar.xz | tar xJ --strip-components=3 --wildcards` 仅取 zh_CN 到 /usr/share/man/。Git Bash 宿主 ar 会 CRLF 损坏二进制成员（魔数完好后续损坏），本地校验用 Python 按 ar 头精确切成员完成；chroot Linux ar 无此问题。zh_CN 会话（fbterm 内）`man ls` 出中文，C.UTF-8 会话保持英文；自检加 ls.1.gz。
  - **shell 体验**：/root/.bashrc 加 `alias ls='ls --color=auto'` 与彩色 PS1（root 红 user@host + 蓝 cwd，纯 ANSI，vconsole/fbterm/serial 通吃）。
- [x] 15. **run#51 复盘 + pacman 包管理器 + Phase 2 打包 + persistence（2026-08-22 实施，run#56 全绿验证通过）**：
  - **根因十八：libucimf/ucimf-openvanilla debug.h 编译失败（run#51 实证）** —— `"[Err]:"format` 字面量紧贴宏参数名，GCC 按 C++11 用户自定义字面量解析报 `unable to find string literal operator 'operator""format'`；libucimf-2.3.8/include/debug.h 与 ucimf-openvanilla-2.10.11/src/debug.h 各含 UCIMF_ERR/WARNING/INFO/DEBUG 四个同款宏。修复：解包后 `sed -i 's/:"format/:" format/g'` 两处。man-pages-zh 解包在 run#51 已实证通过。
  - **fontconfig monospace 警告仍未解**：conf.d/99-fira-code-prefer.conf 也未赢过文泉驿（run#51 警告依旧）。不阻塞构建；后续用 FC_DEBUG=1024 或 sed 向 fonts.conf 注入 local.conf include 排查。
  - **pacman 五连构建**（ninja→meson→curl→libarchive→pacman，版本经 GitHub API/gitlab release 实证）：ninja 用 tag 自动归档（release 无源码资产）；meson 免 pip 直接 cp 源树到 /usr/local/lib/meson + symlink meson.py；curl 显式禁 libpsl/brotli/zstd/nghttp2/libssh2/libidn2/ldap；pacman meson 选项 `-Dgpgme=disabled -Ddoc=disabled -Dcurl=enabled -Dcrypto=openssl`（7.1.0 meson.build 实证：libseccomp required:false 可缺省）。
  - **pacman.conf 关键决策**：DBPath=/usr/local/lib/pacman（live 系统 /var 是 tmpfs 会遮蔽 squashfs 且重启即失）；SigLevel=Never（无 gpgme）；[lfscn] file:// 本地仓库；Arch core/extra 注释模板附 glibc 错配警告。
  - **Phase 2 打包**：pkg_register() 硬链接暂存（cp -al）+ 手写 .PKGINFO + tar --zstd → repo-add 入库 → pacman -U 注册所有权 → 删归档防 squashfs 体积翻倍。八包：nodejs/rust/powershell/neovim/fira-code-fonts/wqy-microhei-fonts/fbterm-ucimf-stack/man-pages-zh。效果：pacman -Q/-Qi/-R 可管理。
  - **persistence（W4）**：initramfs 补 losetup；init 在 overlay 装配前探测分区（ext4/vfat 根含 upper/ 目录 → 直用；或含 lfs-cn-persistence.img → loop0 挂载），找不到回退原 tmpfs 行为；persist=off 内核参数显式关闭；GRUB 加「volatile session」第二菜单项。kernel-live.fragment 无需改（LOOP/EXT4/VFAT 均 =y 已确认）。
  - **run#52–#56 迭代实录（全部已修，run#56 全绿：ISO 761MB 产出）**：
    - 根因十九：GNU tar 用 `.` 打包时成员带 `./` 前缀，pacman 按精确名找 `.PKGINFO` 失败报「缺少软件包元数据」→ 改为 null 分隔显式清单（printf .PKGINFO + find %P）。
    - 根因二十：pkgver 含连字符非法（1.6.4.5-1-1、0.2.0-beta）→ 去掉 Debian 修订号、beta 改下划线，pkg_register 加防御校验。
    - 根因二十一：pacman 拒绝覆盖无主文件（我们打包的恰是本脚本先前装好的软件），58.6 万行冲突清单后中止 → `pacman -U --overwrite '*'`。
    - 根因二十二：tar `-T` 清单遇目录会再递归一遍，重复成员变成自引用硬链接，解包时被跳过导致 `/usr/bin/fbterm` 凭空消失 → `--no-recursion`（本地 Git Bash GNU tar 复现实证：修复前后成员数 19→8）。
    - 遗留（外观级）：fontconfig monospace 别名仍落到文泉驿（根因十七）；实证 99-fira-code-prefer.conf 已加载（wqy 正是列表第二项），疑 Fira Code 字体声明 spacing/proportional 导致匹配评分落败；FC_DEBUG=1024 日志已写入快照 /root/downloads/fc-debug.log 待分析。fbterm-zh 显式字体列表不受影响。
  - **代理备注（2026-08-22）**：本机直连 GitHub 大文件下载会截断，需 `curl --proxy http://127.0.0.1:7890` 拉 run 日志 zip。
- [x] 16. **根因二十九：Arch 仓库下载 SSL 证书验证失败（run#69 实证，已修）** —— chroot 缺 ca-certificates 导致 curl 下载 core.db/extra.db 失败，修复：06-xorg-xfce.sh fetch() 加 `-k` 跳过验证。
- [x] 17. **initramfs sort 缺失 + OVIMGeneric 补丁修正 + 字体渲染 + sudo（2026-08-24，run#87 from-base 已验证）**：
  - **根因三十：/init line 59 `sort: command not found`** —— initramfs init 脚本用 `sort` 排序 /proc/partitions 设备名，但 copy_deps 清单未包含它 → 添加 `copy_deps sort` 并纳入 /usr/bin 自检列表。
  - **OVIMGeneric 补丁实证修正**：fuzzyMatch 参数语义纠正（对候选文本做子序列匹配，首字符必须匹配）；getCandidatesWithFuzzy 真正调用 fuzzyMatch 过滤；compose 中去重/locality bonus/弱匹配单候选直发均接入；candidateEvent 记录选中词供 locality bonus。
  - **字体过粗追加修复**：ucimf.conf 补 font-antialias=1/font-rgba=rgb/font-lcdfilter=lcddefault（此前 autohint=0/hinting=1/embedbitmap=0 不够）。
  - **fbterm 重启问题**：ucimf.conf plugin-path=/usr/lib/ucimf:/usr/lib/openvanilla + im-autoload=fbterm_ucimf + modules.list 索引。
  - **ESC 关闭输入法**：fbterm-zh 快捷键文档更新（Esc 关闭输入法/清空缓冲）。
  - **新增 sudo 1.9.17p2**（版本经 sudo.ws/releases/stable 实证）：env.sh 加 SUDO_VER；宿主侧下载表加 sudo.ws/dist 源码包；chroot 侧 BLFS 风格源码构建（--libexecdir=/usr/lib --with-secure-path --with-env-editor，无 PAM 回退 shadow 认证）+ /etc/sudoers（root + %wheel，secure_path 显式）+ wheel 组创建 + pkg_register 入 [lfscn] 本地仓 + 自检加 /usr/bin/sudo、visudo、/etc/sudoers。run#87（2026-08-24 from-base）实证：除 visudo 自检路径写错（根因三十一，实装 /usr/sbin）外全部通过（15 包注册/cs-oi+zhuyin 码表/OVIMGeneric 索引/pacman -Q 正常）→ 已修，待下轮 from-base 复验。

## 本地 ISO 修复（initramfs 重打包，2026-08-20，无管理员/无 WSL/Docker/无 QEMU 验证）
**对 `C:\Users\yl\Downloads\lfs-cn-live-iso\lfs-cn-13.0-systemd-x86_64.iso`（781MB，含旧 initramfs）手工重打包，仅改 initramfs（不碰 squashfs）。**
- 流程（Windows 免管理员工具链）：7-Zip 解 ISO → 解 initramfs → init 加 tmpfs /var /home → 重打包 → xorriso 复刻引导。
- 关键坑（已解决）：
  1. Windows 无法建符号链接（无 SeCreateSymbolicLinkPrivilege）→ 原 `bin/sh->/usr/bin/bash` 软链接改为 bash 普通副本（init shebang 照常工作）。
  2. bsdtar（System32 tar.exe）在 Windows 上把一切文件写 0644，exec 位丢失 → 内核会 "Failed to execute /init"。用 `--format=newc` 重打包后**字节级解析 newc 头部**（mode 字段在每条目 110 字节头 +14 偏移，8 位 ASCII 十六进制），按名称规则重写 mode：目录 040755、工具二进制 0100755（umount 0104755 setuid）、usr/lib/* 0100644、init 0100755。步进公式 `stride=roundup(110+namesize,4)+roundup(filesize,4)`。
  3. PowerShell `>` 重定向会文本化损坏 gzip 二进制 → 改用 .NET `GZipStream`（CompressionLevel::Optimal）压缩，头 `1f 8b` 正确。
  4. xorriso.exe（Cygwin 构建）路径需 `/cygdrive/d/...` POSIX 格式。
- 复刻引导：xorriso -as mkisofs 按原 ISO `-report_el_torito as_mkisofs` 参数（`-b /boot/grub/i386-pc/eltorito.img -boot-load-size 4 --grub2-boot-info`、`-e /efi.img`、`--grub2-mbr`（前 16 扇区 8192B 提取为 grub2-mbr.bin）、`--protective-msdos-label`、GPT/APM/hfsplus）。产物 `D:\iso-fix\lfs-cn-13.0-systemd-x86_64-fixed.iso`（383143 扇区，597 文件，El Torito 复测与原版一致）。
- 验证：新 initramfs `tar -xOf ./init` 确认含 `mount -t tmpfs tmpfs /newroot/var` / `/newroot/home`；条目 50、权限 init=0755/umount=4755 正确。
- 待办：用户 QEMU 实测新 ISO 无三个 FAILED；磁盘 C 仅剩 4.3GB，`D:\iso-fix` 工作目录约占用 1.5GB+，验证后可删。
- [ ] 10. （可选）清理 `D:\wbw121124` 遗留 `ghlog.py tail --latest` 进程（PID 4732）。

## run#17 结果（2026-08-14，回顾）
**交叉工具链（ch5+ch6）构建成功**。日志 73802 行实证：`libgcc_s.so` 安装于 `/mnt/lfs/usr/lib/`（常规 GCC 布局），工具链断言文件 `10-host-stage.sh` 曾错误地在 gcc 私有目录（`$LFS/usr/lib/gcc/$LFS_TGT/15.2.0/`）查找 → 断言误报。修复：断言路径改动态推导（`-print-libgcc-file-name`）；glibc 5.5 校验块加 `CCACHE_DISABLE=1`。

## 历史根因（已修复，run#13/14/15 定案）
**ccache-wrap 为 `x86_64-lfs-linux-gnu-cc`/`-c++` 建了符号链接，但 gcc pass1 install 从不安装这两个真实编译器** → gcc pass2 目标编译器搜到毒链接 → `configure-target-libgcc` 用 `x86_64-lfs-linux-gnu-cc` 编译探测失败（ccache 找不到真实编译器）→ libgcc 从未构建/安装，base job 端暴露（crtbeginS.o/-lgcc/-lgcc_s not found）。修复：`01-host-prep.sh` 移除这两个包装链接，目标编译器回落 `-gcc`。

## run#23 结果（2026-08-15，HEAD=244d808，plan-only）
**仅更新 plan.md（记录 Tcl 根因二的预告）。toolchain success；base job failure 在 8.17 Tcl-8.6.17（pkg_run 尚未修复）**。
- 失败点证据：`/build/common.sh: line 31: cd: tcl8.6.17-src: No such file or directory`（与 run#22 相同的「根因二」模式）。该 run 与 run#24 紧邻（09:34 / 09:35 UTC 先后 push）。

## run#25 观察（2026-08-15，HEAD=bd932dc，卡死，处置：建议 cancel 后重跑）
**toolchain success（新 ccache key 全 miss 重编）；base 进入 ch8 后 in_progress，systemd-259.1 全量编译（2330 目标）在 [668/2330] 处进程停滞。**
- util-linux 修复未及验证（尚未跑到 util-linux）。证据链：
  - 日志 blob `job-logs.txt`（44MB, 20260815T0230）`Last-Modified=02:30:23Z`，最后一行 `[668/2330] Compiling C object systemd-hostnamed.p/src_hostname_hostnamed.c.o`；此后 2h+ 无任何新日志 → 非 GitHub 页面缓冲，是 job 内部进程停滞。
  - job API：base job（94942251835）run#25 内 `Build base system in chroot` step 01:28:49Z 起 in_progress，无 timeout 配置（GitHub 默认 6h 将强制 cancel，本地 <15:30）。
  - cancel 403：`action-log.html` 的 TOKEN_DEFAULT 是 Actions:Read 只读 token，无法 cancel/trigger → 需用户网页操作或提供 write token。
- 可能根因（未证实）：ccache key 变化（bd932dc 改 scripts/30-ch8-stage.sh）→ run#25 的 ccache 全 miss → systemd 2330 目标全量编译。run#24 该处命中旧缓存（systemd 仅 2.5min）。磁盘充足（run#24 die 时 145G/46%）。停滞点无日志 → 疑似子进程死锁/runner 资源问题，需重跑确认是否偶发。
- 待办：cancel+重跑观察 systemd 是否复现；若复现需针对性加固（如 systemd 降并行/跳过测试/拆步骤，或给 ccache 预留）。

## run#37 结果（2026-08-17，HEAD=0ede7e2，extras 全过！）
**resume（v2 语义：skip toolchain+base）→ config+extras **success** —— fbterm `-Wno-narrowing` 修复实证通过，Node/Rust/ICU/nano/freetype/fontconfig/fbterm/字体/编辑器配置全部安装完成 → snapshot-config 已上传（run#37）；但 Kernel+ISO 被 skipped（跳过传播沿 needs 链递归，见 Resume v3）→ 用户要求 resume 直接跳 iso（v3）。**
- 里程碑：extras 环节（下载/安装/字体/配置）全链路打通；剩余唯一链条：iso job（内核 defconfig+fragment、initramfs、squashfs、GRUB 双引导 ISO —— 全新领域，从未跑过）。

## 根因十一（run#38 实证，已修）
**initramfs copy_deps 硬编码 /usr/bin/ 路径，但 switch_root（util-linux）、insmod/modprobe（kmod）安装在 /usr/sbin/ → copy_deps 返回 1 → set -e 静默退出 rc=1（无任何错误输出）。**
- 证据：run#38 日志 bzImage 构建成功（`Kernel: arch/x86/boot/bzImage is ready (#1)`），内核安装复制正常，initramfs copy_deps 复制序列 bash→mount→umount 后在 switch_root 处中断，chroot 静默 rc=1；宿主 15GB RAM/4 核，排除 OOM。
- 修复（已实施）：copy_deps 改为按名字在 `/usr/bin /usr/sbin /bin /sbin` 依次查找（找到即用），缺失打 WARN 继续（不再触发 set -e）。

## 根因十二（run#39 产物实证，已修）
**initramfs 修复（根因十一）不彻底：copy_deps 已支持 PATH 遍历，但调用处仍传绝对路径 `copy_deps /usr/bin/bash` → 函数按 `"$p/$name"` 拼接成 `/usr/bin//usr/bin/bash` 全部不存在 → 15 个工具全部静默跳过（打 WARN 而非失败）→ initramfs 只剩目录骨架+悬空 `bin/sh→/usr/bin/bash`+ld 链接器。**
- 证据：QEMU 实测 ISO 引导 `[4.055076] Failed to execute /init (error -2)`（shebang `#!/bin/sh` 找不到解释器 ENOENT）→ `Kernel panic - not syncing: No working init found.`；解包 initramfs 仅 18 项，`usr/bin`/`usr/sbin` 空目录。
- 修复（已实施，未构建验证）：
  1. copy_deps 参数兼容绝对路径（`name="${1##*/}"`），缺依赖与复制错误由静默改明示；
  2. 自检硬性化：bin/sh、bash、mount、switch_root、链接器等缺失 → `die` 中止构建（`chroot/06-kernel-initramfs.sh`）；
  3. 打包后产物反查：`gzip -dc | cpio -it` 校验必需条目，缺失即 die（`06-kernel-iso.sh`）。
- 待办：push 触发 resume 重建（约 15min，内核重编不可避免），新 ISO 必须通过 QEMU 引导至 GRUB 菜单→live 登录。

## run#38 结果（2026-08-17，HEAD=0464302，resume v3 首验）
**resume v3 实证：push 自动只跑 iso job（Toolchain/Base/Config+extras 全 skipped，find-config 找到 run#37 snapshot-config 恢复）→ 内核 defconfig+fragment 配置通过、bzImage 构建成功（~12min）→ initramfs 阶段失败（根因十一，switch_root 路径）→ 14m14s 失败。**
- 里程碑：iso job 前半程（配置/编译/内核安装）全部打通；剩余：initramfs（修复中）→ mksquashfs → grub-mkrescue（全新领域）。

## 根因十（run#36 实证，已修）
**fbterm-1.7（2012 年代码）在 GCC 15 下编译失败：`src/lib/vterm_states.cpp` 多处 `{ -1 }` 初始化 `u16`（unsigned short）→ C++11 起 list-initialization 的 narrowing 为 ill-formed，GCC 默认报错（`错误：narrowing conversion of '-1' from 'int' to 'u16' [-Wnarrowing]`）→ make 退出 rc=2。**
- 证据：run#36 日志 Node/PATH 修复后已越过 Node（`node --version` 通过）、Rust/ICU/nano 等段（fbterm 段在 nano/freetype/fontconfig 之后？实际先到 fbterm 编译段即失败）；`make[3]: *** [Makefile:301：libshell_a-vterm_states.o] 错误 1`。
- 修复（已实施）：`./configure --prefix=/usr CXXFLAGS="-O2 -Wno-narrowing"`（GNU 文档：-Wno-narrowing 允许该转换）→ 待 run#37 验证。若后续还有旧代码兼容错误（-Werror=... 类），同段继续补。

## run#36 结果（2026-08-17，HEAD=6d0db27，resume 再验）
**resume 机制二次验证：config+extras 独立运行（toolchain/base skipped）→ 11 文件下载全成（多源重试机制未触发即过）→ Node PATH 修复生效（Node 安装 + version 通过）→ Rust/ICU 等段正常 → fbterm 编译失败（根因十，GCC 15 narrowing）→ 4m23s 失败；iso 未跑。**
- 里程碑：extras 下载环节全部通过（此前 run#31/32/35 均死在下载/PATH）；剩余链条：fbterm → 字体 → 编辑器配置 → snapshot config → iso job（内核+initramfs+squashfs+GRUB，全新领域）。

## 根因九（run#35 实证，已修）+ 下载多源重试（新增）
**chroot 内 extras 安装失败：chroot 入口 PATH=/usr/bin:/usr/sbin 不含 /usr/local/bin → `node --version`（chroot/05-extras.sh:27）`command not found`（rc=127）。Node/Rust/nvim/pwsh 的二进制都 ln 到 /usr/local/bin，此前从未跑到该段（run#31/32 均死在下载），首次暴露。**
- 证据：run#35 日志 node/nano/icu/fbterm/powershell/rust/freetype/fontconfig/nvim 11 文件下载全部成功（node 单 v、fbterm Debian pool 修复生效），chroot 内 `tar xf node-... --transform` 三链接成功 → `node: command not found`。
- 附带验证：本地实测 node tarball `--transform='s,^node-v[0-9.]*-linux-x64,lib/nodejs,'` 在 GNU tar 下解压为 `lib/nodejs/bin/node` 正常（排除 transform 问题，根因锁定 PATH）。
- 修复（已实施）：chroot/05-extras.sh 头部 `export PATH="/usr/local/bin:/opt/rust/bin:$PATH"`。
- **下载多源重试**（用户要求）：05-extras.sh 下载循环重构 —— 每文件主源 3 次尝试（curl --retry 1 + 3 轮，失败 rm 残留 + sleep 3）→ 失败自动切换镜像源再 3 次 → 仍失败才 die。镜像（已实测 200）：node → npmmirror、fbterm → ubuntu archive；rust 镜像实测均不可用（rsproxy 504/USTC 403/清华 404）→ 仅主源重试。本地冒烟测试通过（主源 404×3 → 镜像成功 186364 字节）。

## run#35 结果（2026-08-17，HEAD=86c705d，resume 机制首验）
**resume 机制实证成功：toolchain/base 均 skipped（跳过传播 bug 已修，config-extras 用 always() 条件正常运行），config+extras 从 run#32 的 snapshot-base artifact 恢复 → 只跑 extras 相关步骤（1m6s 内下载 11 文件全成）→ 卡于 Node PATH 问题（根因九）；iso 未跑。**
- 全链路验证：push 自动 resume ✓；skipped 传播修复 ✓；历史 artifact 查找/下载 ✓。

## 根因八（run#32 实证，已修）+ Resume 机制（新增）
**05-extras.sh 下载 node 双 v bug：`NODE_VER=v24.19.0`（env.sh 已含 `v` 前缀），下载侧写成 `node-v$NODE_VER-linux-x64.tar.xz` → `node-vv24.19.0...`，URL `https://nodejs.org/dist/v24.19.0/node-vv24.19.0-linux-x64.tar.xz` 404（本地预验证时误用单 v URL 漏检）；chroot 侧引用 `node-$NODE_VER`（单 v）正确，两侧不一致。** 修复：下载侧改 `node-$NODE_VER`（05-extras.sh:22）。实测单 v 200 / 双 v 404。
- **run#32 已实证**：fbterm（根因六 Debian pool）下载成功、node 下载 404 失败 → 此轮 config+extras 卡在 node；其余 extras URL 无新问题。
- **Resume 机制（v3 迭代，当前）**：resume 语义改为 **skip toolchain + base + extras，直接跑 iso**（从最近成功 run 的 snapshot-config 恢复）。
  - 触发矩阵：**push → 自动 resume（只跑 iso）**；dispatch 勾选 resume = 同左；dispatch 不勾选 = 全量（toolchain→base→config+extras→iso）。
  - 关键实证（run#37）：config-extras success 后 **iso 仍被 skipped** —— GitHub 的跳过传播沿 needs 链递归生效（base/toolchain skipped → 下游 iso 即使直接 needs 的 job success 也被跳过，必须显式 if 覆盖）→ iso 加 `always() && (push || resume || needs.config-extras.result == 'success')`。
  - iso 步骤加 find-config（push/resume 时查历史 snapshot-config run_id）+ download-artifact run-id。
- 注意：run#31/32 的 snapshot-base artifact 保留 7 天，resume 需在其 retention 内使用。

## run#32 结果（2026-08-17，HEAD=d0d1a14，ch8 三度卡死防线实证）
**toolchain success；base success（约 2h5m，外层 timeout 14400 未触发即正常完成 —— 根因七防线就位）；config+extras failure（node 双 v 404，见根因八）；iso skipped。**
- 卡死观察：本轮 base 全程正常（14:46 UTC 起 ~2h 完成），未遇 texinfo/systemd 停滞；根因七的 4h 外层兜底未动用即通过，仍保留。
- run#31（texinfo 卡死）处置：cancelled（用户网页取消，run#32 排队后开跑）。

## 根因七（run#31 实证，已修）
**base job step 用 `bash 03-chroot-base.sh 2>&1 | tee base.log` 管道；当 chroot 内构建进程脱离 pkg_run 看门狗（timeout）进程组时，pkg_run 超时 die 后孤儿进程仍持管道写端 → tee 永不 EOF → step 永不结束 → job 挂到 GitHub 6h 强杀（cancelled）——run#25/26/31 三度发生（run#25/26 systemd 卡死、run#31 texinfo 卡死，卡死点随机）。**
- 证据（run#31）：base job 日志停滞于 `==> build texinfo-7.2` configure 中段（REPLACE_* sed 输出后）长达 3h+（ghlog get/tail 均挂起）；pkg_run 看门狗（7200s）已到却无 TIMEOUT 输出可见 → step 未收尾；jobs API 恒 in_progress。有 swap 时 run#28/29/30 连续 3 次通过、run#31 再卡 → 卡死为随机 runner/进程问题，swap 非充分保护。
- 修复（已实施）：base step 外层包 `timeout 14400 bash -c '... | tee base.log'`（4h 进程组级兜底，正常构建 2-3.5h 不受影响；卡死时强制清整个 step 进程组 → step 结束 → failure + 日志/artifact 上传照常）。config+extras/iso 步骤无 tee 管道（GitHub 直接捕获），无此风险，不改。
- 遗留观察：3 次卡死点均不同（systemd×2、texinfo）→ 疑似 runner 偶发资源/虚拟化问题，无法代码根治，外层兜底为现实方案。

## run#31 结果（2026-08-17，HEAD=a37b462，chroot 卡死再现）
**toolchain success（~16min，05-extras.sh 改动触发 ccache 全 miss 重编）；base 卡死于 texinfo-7.2 configure（14:25 UTC 起 3h+ 无输出，job 至截稿仍 in_progress，预计 6h 强杀 cancel）；config+extras/iso 未跑。**
- 意义：run#28/29/30（有 swap）三连过证明 swap 修复有效；run#31 卡死点不同于 run#25/26（systemd）→ 卡死随机化，根因七的 step 收尾兜底是唯一可靠防线。
- fbterm URL 修复（根因六）本 run 未及验证 → run#32 重验。

## 根因六（run#30 实证，已修）
**05-extras.sh 下载 fbterm-1.7.tar.gz 404：SourceForge 项目 `fbterm` 已下线（`downloads.sourceforge.net/project/fbterm/...` 与 `sourceforge.net/projects/fbterm/files/...` 均 404，webfetch 项目页亦 404）。**
- 证据：run#30 config+extras job 日志 `[05:53:32] curl: (22) The requested URL returned error: 404`，fail 于 `downloading fbterm-1.7.tar.gz`（wqy/nano/icu4c/libunwind 均成功，其余 URL 预验证全部 200）。
- 修复（已实施）：URL 改 Debian pool 镜像 `https://deb.debian.org/debian/pool/main/f/fbterm/fbterm_1.7.orig.tar.gz`（200；本地实测顶层目录 `fbterm-1.7/` 与 chroot 脚本 `tar xf fbterm-1.7.tar.gz; cd fbterm-1.7` 兼容，下载文件名不变）→ 待 run#31 验证。
- 附带预验证（curl HEAD 全 200）：node/rust/powershell/nvim/freetype/fontconfig/libunwind URL。

## run#30 结果（2026-08-17，HEAD=1fa15ac，ch8 全过！）
**toolchain success（~16min）；base success —— ch8 全部完成（8.85 strip 修复实证：`.socket` 非 ELF 跳过、ELF 正常 strip；8.86 cleanup 通过）！config+extras failure（fbterm 404，见「根因六」）；iso skipped。**
- base job 13:54:42 success（自 12:10 起约 1h45m），`usr/.base-system-complete` 已写入，base 快照（3 分卷）已上传 → run#31 无需重跑 toolchain/base，直接从 base 快照继续 config+extras。
- 8.85/8.86 通过的意义：ch8 81 包全部成功，剩余链条只剩 extras 下载/安装、内核+initramfs+squashfs+GRUB ISO。

## 根因五（run#29 实证，已修）
**8.85 Stripping 失败：`find /usr/lib -type f -name \*.so*` 的 glob `*.so*` 是子串匹配，会命中 `.socket`/`.sock` 等非 ELF 单元文件（如 `/usr/lib/systemd/user/systemd-ask-password.socket`）→ `strip: file format not recognized` rc=1 → `set -e` 下 shell_run 直接失败。**
- 证据：run#29 base job 日志 `[11:48:50] strip: /usr/lib/systemd/user/systemd-ask-password.socket: file format not recognized` → `ERROR: shell_run block failed (rc=1)`。此前 objcopy 分离 debug 的 save_usrlib 循环全部成功（removed/-> 输出可见），说明失败仅在该 strip 循环。
- 这是 ch8 最后一个阶段（8.85 strip + 8.86 cleanup），首次跑到即失败；LFS 书无 `set -e`（手动执行时该错误可忽略），故书中命令照抄到 set -e 环境即暴露。
- 修复（已实施）：该循环 `strip --strip-debug $i || true`（非 ELF 跳过，ELF 正常 strip）→ 待 run#30 验证。

## 代码审查报告处置（2026-08-17，run#29 结束后）
另一 agent 对 util-linux timeout 修复的审查（8 文件只读），逐项处置：
- **[严重] timeout 仅杀直接子进程、孤儿持管道 → step 挂死 6h**：**实证否定**。GNU timeout 默认 setpgid 后向整个进程组发 TERM/KILL；run#28（7200s 看门狗）与 run#29（600s 测试兜底，03:38:39 挂死 → 03:48:15 make install 继续，恰 600s）均证明超时后进程组被整体清理、step 正常收尾（Process completed 出现、后续步骤照常）。不实施改动。
- **[一般] 超时快照 ps head -40 截断**：**已修**（common.sh 去 head，全量输出）。
- **[一般] pkg_run 顶层目录兜底仅处理单顶层且不防 ./ 前缀**：**已修**（common.sh：sed 去 ./ 前缀 + sort -u 要求恰好一个顶层条目才 mv；本地 tcl/bison tarball 验证通过）。
- **[建议] swap 检测 `grep -q swap` 子串匹配**：**已修**（workflow：`swapon --show --noheadings | grep -q .`，以"存在任何已激活 swap"为准）。
- **[建议] `timeout 600` 魔法数字 + 无 command -v 守卫**：**已修**（30-ch8-stage.sh util-linux：command -v 守卫分支，与 common.sh:36 风格一致）。

## run#29 结果（2026-08-17，HEAD=2f9235f，util-linux timeout 验证通过，fail 于 8.85 strip）
**toolchain job success；base job 推进至 ch8 8.85 Stripping（ch8 最后一个阶段前）后失败。**
- util-linux 修复实证通过：11:37:10 build 开始 → 测试跑至 lsns 挂死 → `timeout 600` 进程组信号清理（03:38:39 → 03:48:15 恰 600s）→ `touch /etc/fstab` + `make install` 完成 → e2fsprogs-1.47.3 全过（`libext2fs.dvi Error 1 (ignored)` 为 make 忽略项，不阻断）。
- 失败点：8.85 Stripping（见「根因五」）。8.83.2 配置 sed、8.85 的 objcopy 分离 debug 循环均通过。
- 附带确认：swap（3.0Gi）与 systemd 编译本轮继续正常；run#29 base 从 09:03 恢复快照到 11:48 失败，约 2h45m。

## run#28 结果（2026-08-15，HEAD=3fe6672，swap 修复生效，fail 于 util-linux 测试挂死）
**toolchain job success（~17min，快照 1.9GB 上传）；base job 推进至 8.82 util-linux-2.41.3 后看门狗超时（exit 1，total 时长 ~6h 含等待基建）。**
- swap 修复验证通过：超时快照显示 `Swap: 3.0Gi` 就位且 0B 使用；systemd-259.1 本轮无卡死（18:29:16 起 3min 内完成，dbus/man-db/procps-ng 均过）。
- 失败点：util-linux `tests/run.sh` 挂死（详见「根因三」深化）。本轮 `make check-programs` 生效：测试实际运行约 1 分钟（file-show/lsfd/lslocks/lsmem 等大量 OK），至 `lsns: NETNSID compare to ip-link` 后 2h 无输出 → pkg_run 7200s 看门狗触发。
- 新验证：看门狗按设计工作——超时后上传 .diag artifact（base-failure-logs.zip，ID 9246992877，含 df/free/meminfo/ps 快照），残留树保留用于 triage。但注意 GitHub Actions artifact blob API 401 仍阻塞自动下载，本次日志经网页手工下载。
- 时间线：18:25:32 iproute2 → 18:33:41 build util-linux 开始 → 18:35:31 测试挂死 → 20:33:41 看门狗 TIMEOUT（恰好 7200s）。

## run#27 结果（2026-08-15，HEAD=5cb7045，swap 步骤自身失败，未开始构建）
**toolchain success（~17min，ccache 回退命中）；base job 在第一步 swap 即挂：`fallocate: fallocate failed: Text file busy` → exit 1 → base 立即失败。**
- 原因：ubuntu-latest runner 镜像自带 `/swapfile`（已 swapon）→ fallocate 4G 冲突。修复：swap 步骤改为检测已有 swap/`/swapfile`（swapon --show 有则跳过、有 /swapfile 则 enable、否则才创建）→ 待 run#28 验证。
- 观察：run#26 卡死中，看门狗预计 09:47Z 触发（systemd pkg_run 07:47Z + 2h），将上传 .diag artifact（含 ps 快照）——若内存假说不成立，快照可揭示卡死进程。

## run#25 + run#26 卡死根因（systemd 全量编译确定性停滞，待 run#27 验证修复）
**两次（run#25 @[668/2330] hostnamed.c、run#26 @[547/2330] unit-printf.c）均卡死在 systemd-259.1 全量编译中段，普通 C 文件编译后无任何新日志（run#25 停滞 5h+ 直至 6h 强制 cancel；run#26 停滞 30min+ 确认同模式）。**
- 共同点：ccache key 全 miss（ch8 编译不经 ccache，CCACHE_* 无关）；J2 并行 GCC -O3；runner 7GB RAM 无 swap。
- 排除：磁盘（145G 大盘）、ccache、构建命令差异。
- 新假说（未证实）：GCC 15.2 -O3 编译 systemd 核心文件内存尖峰 → runner cgroup 内存冻结/无 swap stall → 进程无输出挂死。run#24 该处 ccache 命中（每文件 <1s 无内存峰值累积）通过支持该假说。
- 修复（已实施，common.sh + workflow）：宿主 `fallocate 4G /swapfile + swapon`（base job 步骤，改 workflow 不触发 ccache key）；超时快照加 `free -h`/meminfo 诊断。run#26 仍在卡（看门狗 2h 将触发并上传 .diag artifact 含 ps 快照，可作证据）。

## run#24 结果（2026-08-15，HEAD=d7381c2）
**toolchain job success；base job failure，推进至 8.82 util-linux-2.41.3。**
- 根因二（Tcl 顶层目录）修复验证通过：run#24 越过 Tcl-8.6.17，并连续通过 Expect、DejaGNU、Python 系（openssl/elfutils/libffi/sqlite/Python-3.14.3）、systemd-259.1、dbus、man-db、procps-ng 等直至 util-linux。
- 失败点：util-linux-2.41.3（见「根因三」）。日志 `ERROR: build of 'util-linux-2.41.3' failed (rc=1)`；make 全量 CCLD 成功，`bash tests/run.sh` 报 "Tests not compiled!" 退出。
- 附带观察：die 分支 ERROR/df/mount 输出本次正常透传（`ERROR: build of ...` 与 `Filesystem ... df` 均出现在 job 日志）。
- 日志来源：`C:\Users\yl\Downloads\logs_86238926001\2_Base system (ch8).txt`（44MB，203804 行，失败行 203803）。

## run#22 结果（2026-08-14，HEAD=cb86455，run_id=31785299090)
**toolchain job（94719761110）success；base job（94722721282）failure，推进至 8.17 Tcl-8.6.17。**
- ch7 全部通过（gettext 探针 `manual_conftest_rc=0`）；ch8 已越过 glibc-2.43、flex-2.6.4 等大量包直到 Tcl。
- 失败点：Tcl-8.6.17 见上方「根因二」。
- 观察点：die 分支的 ERROR/df/mount 输出未出现在 job 日志（`grep -E 'ERROR|failed \(rc|df -h'` 无结果），但 job 确实在 tcl 处退出（exit code 1）→ 需在修根因二后验证 die 输出是否正常透传（可能 chroot 内 stdout 缓冲问题）。
- artifact 9214217592（822895 字节）已上传（base.log + /mnt/lfs/sources/.diag/），下载仍受 blob 401 阻塞。

## 历史修补与审计清单（run#17 之前轮次）
- **10-host-stage.sh**：
  - glibc 5.5 工具链校验块加 `CCACHE_DISABLE=1`（ccache 命中时 `-v` 预处理输出不回放 → grep 误杀）。
  - gcc pass2 断言：crtbeginS.o/libgcc.a 查 gcc 私有目录（动态推导），libgcc_s.so 查 `$LFS/usr/lib/`。
- **30-ch8-stage.sh**（对照 LFS-CN ch8 逐段审计）：
  - glibc：删 `rm -f /usr/sbin/nscd` + `systemctl disable --now nscd`（旧版升级说明，systemd 未装 → command not found）；`make DESTDIR=$PWD/dest install`+`install dest/usr/lib/*.so.*` 改为书式 `make install`（DESTDIR 两行同为升级说明残留）。
  - tzdata：`tar -xf ../../tzdata2025c.tar.gz` → `tar -xf tzdata2025c.tar.gz`（shell_run cwd=/sources，`../../` 解析到 `/`）。
  - 删交互式 `tzselect`；`ln -sf /usr/share/zoneinfo/<xxx>` → `Asia/Shanghai`。
  - GMP：删 `awk '/# PASS:/{total+=$3}' gmp-check-log`（文件不存在 → rc=2）。
  - Coreutils：删 `groupdel dummy`（无该组 → rc=6）。
  - Groff：`PAGE=<paper_size>` → `PAGE=A4`。
- **chroot/04-sysconfig.sh**：删死代码 10-eth-static.network（Match=ether0 永不应配，DHCP 已配）；hosts 加 `lfs-cn`；locale grep `-qi '^zh_CN\.utf-?8$'`；加 `systemd-resolved` stub `/etc/resolv.conf` 链接（live DHCP DNS 可用）。
- **chroot/05-extras.sh + 05-extras.sh**：
  - Rust 用完整 toolchain 包 `rust-$RUST_VER-x86_64-unknown-linux-gnu.tar.xz`（rustc-only 组件包缺 cargo/rust-std/rustfmt），`--strip-components=2` 解到 /opt/rust，逐个 symlink 8 个工具 + rust-lld。
  - ICU 下载名 `icu4c-78_2-src.tar.xz`（404）→ `icu4c-$ICU_VER-sources.tgz`（验证 200，顶层 `icu/`）。
- **chroot/06-kernel-initramfs.sh**：`/bin/sh`→`usr/bin/bash` 符号链接（init 是 #!/bin/sh）；`/sbin/init`→`/usr/lib/systemd/systemd` 保险链接；ISO 探测由 `seq` 换 while 算术循环（30 次轮询）；cpio 打包移除（chroot 内无 cpio）。
- **06-kernel-iso.sh**：initramfs 打包移入 host 侧（`( cd "$LFS_ROOT/boot/initramfs-lfs-cn" && find . -print0 | cpio ... | gzip )`）。
- **build-lfs-iso.yml**：iso job 在 `06-kernel-iso.sh` 前加 `bash scripts/01-host-prep.sh`（ubuntu-24.04 无 mksquashfs/grub-mkrescue/xorriso）。
- **40/50 stage**：加 `DO NOT RUN` 头注释（含交互/占位命令）。
- **chroot/06-kernel-initramfs.sh**：内核源码树构建后 `rm -rf`（省 runner 磁盘）。

## 剩余风险（run#18 观察点）
- ch8 81 包长跑是新领域：逐段审计过 vs 书，但仍可能有书中版本差异导致的失败（set -e 下立即暴露，直接看日志）。
- 断言路径动态推导依赖 `CCACHE_DISABLE=1 $LFS_TGT-gcc -print-libgcc-file-name`（真实 gcc 输出）。
- ch8 systemd 阶段（8.78）`systemd-machine-id-setup` 在 chroot 中运行 —— 已按书保留，风险低。

## run#15 前置修补（set -e 引入的误报面）
- ch8 glibc：`grep "Timed out" ...` 无超时即 rc=1 → 加 `|| true`。
- ch8 binutils：`grep '^FAIL:' ...` 无失败即 rc=1 → 加 `|| true`。
- ch8 GMP：删除损坏行 `ABI=32 ./configure ...`（原静默失败，set -e 下会阻断 8.22）。

## 注意事项
- **ccache key**：`ccache-${{ hashFiles('scripts/**', 'tools/x86_64/md5sums') }}`；改 `scripts/` 下任何文件 → ccache 全 miss → toolchain 重编。改 `.github/workflows/build-lfs-iso.yml` 不触发 key 变化。
- **pkg_run 失败后仍 `rm -rf $SOURCES/$dir`**（config.log 等现场丢失）→ 断言轮建议同时保留 config.log 副本。
- **chroot 冒烟**：chroot 内 `/tmp` 在 ch7.5 之前不存在，冒烟编译必须先 `mkdir -p /tmp`。
- **日志工具**：`py D:\wbw121124\ghlog.py runs / jobs <run_id> / get <job_id> -o <file>`；日志 API 刚开跑时常 404，需等待重试。
- 历史 run：run#13=15562bb、run#14=5582590，均为同一 gettext-1.0 失败模式；run#15 验证修复。

## 相关文件
- `D:\wbwlinux\scripts\stages\10-host-stage.sh`：gcc pass2 在 314-353 行（configure 332-349），主修复点；改它会失效 ccache。
- `D:\wbwlinux\scripts\common.sh`：pkg_run 错误处理（待查），断言插入点。
- `D:\wbwlinux\.github\workflows\build-lfs-iso.yml`：HEAD=bb1ba4d，含 DIAGNOSE 冒烟步骤（mkdir -p /tmp + gcc -v、binutils 运行时、libgcc 位置检查）。
- `D:\wbw121124\log14tc.txt`：根因证据（09:14:36-37 configure-target-libgcc Error 1/2）。
- `D:\wbw121124\log14base.txt`：base 失败证据（ld cannot find crtbeginS.o / -lgcc / -lgcc_s，约 320 行）。
- LFS-CN 参考：https://lfs.xry111.site/zh_CN/systemd/chapter06/gcc-pass2.html

## 根因三十六（OVIMGeneric 补丁 malformed patch）
`ovimgeneric.patch` 的 hunk header 行数几乎全部错误，导致 `patch` 工具在第二个 hunk 处解析失败：`malformed patch at line 100: +        }`。另外第181行有一个多余的 `}` 会导致 compose 函数提前关闭（编译错误）。

- 证据：`Hunk #1 succeeded at 33 (offset 23 lines). patch: **** malformed patch at line 100: +        }`
- 根因：手工维护的 unified diff，hunk header 中的 `+行数` 与实际 `+` 行数不匹配（例如声称85行实际122行），patch 工具读取超出 hunk 范围后遇到无法解析的行。
- 修复：重写整个补丁文件，逐 hunk 校正行数 + 删除多余 `}`。
- 附带变更：neovim 从预编译二进制（/opt/nvim-linux-x86_64）改为源码编译（cmake → /usr/local）；新增 NetworkManager 1.58.1 / VS Code 1.134.0 / Firefox 154.0 pacman 包；.bashrc PATH 移除 /opt/nvim-linux-x86_64/bin。

## 根因三十七（neovim FindLuv 失败：构建顺序错误）
直接用 `cmake -B build` 配置 neovim 时，`find_package(Luv)` 在**配置阶段**即报错（`missing: LUV_LIBRARY LUV_INCLUDE_DIR`），因为 luv 是 bundled 依赖，必须先由 `cmake.deps/` 子项目构建到 `.deps/` 目录下。之前尝试 `cmake --build build --target deps` 无效——deps 目标是构建阶段操作，而 configure 已经失败。

- 证据：`Could NOT find Luv (missing: LUV_LIBRARY LUV_INCLUDE_DIR) (Required is at least version "1.43.0")`，cmake/FindLuv.cmake:4。
- 修复：改用 neovim 官方 Makefile 流程（`make` → Makefile 内部先构建 `.deps`，再配置/构建主项目）。cmake 放入 `$PATH`（`/opt/cmake-$CMAKE_VER-linux-x86_64/bin`），避免用 `"$CMAKE_BIN"` 变量（Makefile 子进程需要在 PATH 上找到 cmake）。

## 根因三十八（ovimgeneric.patch 内容错误：源码已含 keyseq.clear + hunk 行数不匹配）
`ovimgeneric.patch` 尝试在 `compose()` 函数中添加 `keyseq.clear()`，但源码已有该行；同时多个 hunk header 中的 old/new 行数与实际上下文/新增行数不匹配，导致 patch 工具报 "malformed patch"。

- 证据：CI 输出 `patch: **** malformed patch at line 144: @@ -360,6 +481,21 @@`；本地 MSYS2 patch 确认。
- 修复：根据 OpenVanilla Modules 源码 commit 28d0dd6 重写整个 patch 文件，移除已存在的 `keyseq.clear` 相关 hunk，校正全部 hunk header 行数（共 6 个 hunk）。

---

## 新增 CI Job：构建自由软件包 + 主题 + GitHub Pages 部署

### 概述

在现有 ISO 构建流水线之外，新增两个 CI job：

1. **`packages`** — 在 chroot 中从源码构建自由软件包（Yaru 主题 + fcitx5 输入法栈等），产出 pacman 二进制包 + 源码包 + pacman 数据库。**与 `iso` job 并行运行**（均依赖 `config-extras`），单个包构建失败不阻塞整个 job。
2. **`deploy-pages`** — **手动触发**，将 `packages` job 产出的 pacman 仓库发布到 GitHub Pages。

### 设计约束

- **不打入 ISO**：`packages` job 的产出仅发布到 GitHub Pages，不参与 ISO 打包。
- **pacman -Sy 数据库**：产出包含 `lfscn.db.tar.gz` 等数据库文件，用户可通过 `pacman -Sy` 从 Pages 安装。
- **二进制包 + 源码包**：每个包同时产出 `.pkg.tar.zst`（二进制）和 `.src.tar.gz`（源码）。
- **单包容错**：每个包的构建在子 shell 中执行，失败只跳过该包，不中断整个脚本。
- **Yaru 主题版本**：Ubuntu 26.04 LTS 对应版本 `26.04.5.1ubuntu`（commit `f01c3e9a257296242806f8e0c5d4a660516f2181`，2026-04-13），含 GTK2/GTK3/GTK4 主题、图标、光标、GNOME Shell 主题。
- **fcitx5**：从 Arch `extra` 仓库预构建包解包（`fcitx5` + `fcitx5-gtk` + `fcitx5-chinese-addons`），LFS 已有库跳过。

### 包列表

| 包名 | 来源 | 说明 |
|---|---|---|
| `yaru-theme` | Ubuntu 26.04 LTS 源码（`26.04.5.1ubuntu`） | GTK2/GTK3/GTK4 主题 + Yaru 图标 + Yaru 光标 + GNOME Shell 主题 |
| `fcitx5` | Arch `extra` 预构建 | 输入法框架核心 |
| `fcitx5-gtk` | Arch `extra` 预构建 | GTK IM Module（IMModule2/3） |
| `fcitx5-chinese-addons` | Arch `extra` 预构建 | 拼音/双拼/五笔等中文输入法插件 |

### 文件变更

| 文件 | 变更 |
|---|---|
| `scripts/env.sh` | 新增 `YARU_VER`、`YARU_COMMIT`、`FCITX5_ARCH_PKG` 等版本变量 |
| `scripts/07-packages.sh` | 新建。宿主端：下载 Yaru 源码 + Arch fcitx5 包。chroot 内：构建 Yaru 主题包、解包 fcitx5、生成 pacman 数据库。产出目录 `/mnt/lfs/pkgrepo/` |
| `.github/workflows/build-lfs-iso.yml` | 新增 `packages` job（依赖 `config-extras`，与 `iso` 并行）+ `deploy-pages` job（manual-only，`github-pages` 环境） |
| `plan.md` | 本段 |
| `README.md` | 包列表更新 |

### `packages` job 工作流

```
config-extras (完成)
    ├── iso job (内核 + ISO)
    └── packages job (自由软件包 + GitHub Pages)
          └── deploy-pages job (手动触发 → Pages)
```

1. 下载 `snapshot-config` 快照，还原 chroot
2. 宿主端下载 Yaru 源码 tarball + Arch fcitx5 预构建包
3. chroot 内执行 `scripts/07-packages.sh`：
   - 构建 Yaru 主题（meson + ninja），打包为 pacman 包
   - 解包 Arch fcitx5 预构建包，注册到 pacman
   - 生成 pacman 数据库（`repo-add`）
   - 产出复制到 `/mnt/lfs/pkgrepo/`
4. 将 `/mnt/lfs/pkgrepo/` 上传为 artifact `packages-repo`
5. **单包容错**：每个包构建失败只 log warning，不退出脚本

### `deploy-pages` job 工作流

- **触发方式**：仅 `workflow_dispatch`（手动）
- 下载 `packages-repo` artifact
- 部署到 GitHub Pages（`actions/deploy-pages@v4`）
- Pages URL: `https://wbw121124.github.io/wbwlinux/`

## 根因三十九（ovimgeneric.patch 缺少 .h 文件声明）
`ovimgeneric.patch` 仅修改 `OVIMGeneric.cpp`（添加 VSCode-like 特性的函数实现），但未修改 `OVIMGeneric.h`（缺少 `deduplicateCandidates`、`recordSelectedWord`、`localityBonus`、`applyLocalityBonus`、`fuzzyMatch`、`isWeakMatchEnabled`、`getCandidatesWithFuzzy` 共 7 个方法声明），导致编译时报 "no declaration matches" 错误。

- 证据：`OVIMGeneric.cpp:263:6: error: no declaration matches 'void OVGenericContext::applyLocalityBonus(...)'`；同理 `fuzzyMatch`、`isWeakMatchEnabled`、`getCandidatesWithFuzzy`、`recordSelectedWord`、`deduplicateCandidates` 均无声明。
- 修复：在 `ovimgeneric.patch` 末尾追加 `OVIMGeneric.h` hunk（`@@ -86,10 +86,18 @@`），在 `cancelAutoCompose` 声明后插入7个方法声明。验证 MSYS2 patch 和 Linux GNU patch 均通过。

## 根因四十（packages job 调用 chroot 脚本而非宿主端包装器）
`07-packages.sh` 是 chroot 内脚本（需要 mount/kernfs/chroot 环境），但 workflow 中直接 `bash scripts/07-packages.sh` 调用，缺少宿主端包装器（复制脚本到 chroot + mount + chroot 执行）。

- 证据：workflow line 371 `run: bash scripts/07-packages.sh`，而 `scripts/07-packages.sh`（chroot 版）首行 `set -euo pipefail` + `source /build/env.sh`，在宿主机上执行会失败。
- 修复：创建 `scripts/07-packages.sh`（宿主端包装器），复制 `chroot/07-packages.sh` + `arch-resolve-fcitx5.py` 到 chroot，mount kernfs，执行 `chroot ... /build/chroot/07-packages.sh`。命名与现有模式一致（`scripts/05-extras.sh` 宿主端 vs `scripts/chroot/05-extras.sh` chroot 端）。

## 根因四十一（Rea-Dark 主题 tar --strip-components 多了1层）
`chroot/05-extras.sh` 中 `tar xf ... --strip-components=3` 多剥了1层目录。GitHub tarball 路径为 `XFCE-.../Rea/Rea-Dark/gtk-3.0/...`（3个前缀组件），`--strip-components=3` 将 `Rea-Dark/` 也剥掉，导致解压到 `/usr/share/themes/gtk-3.0/` 而非 `/usr/share/themes/Rea-Dark/gtk-3.0/`。

- 证据：`ERROR: Rea-Dark theme missing gtk-3.0`
- 修复：`--strip-components=3` → `--strip-components=2`。

## 根因四十二（GNU tar -C 位置敏感：pattern 在前时失效）
`tar xf ARCHIVE --wildcards 'PAT' --strip-components=2 -C DIR` 中，成员 pattern 出现在 `-C` 之前，导致 GNU tar 1.35 将文件解到**当前目录**而非 `-C DIR`（exit 0 静默成功）。因此即使修正了 strip-components（根因四十一），主题仍被解到 chroot 的 `/root/Rea-Dark`，自检 `[ -d /usr/share/themes/Rea-Dark/gtk-3.0 ]` 继续失败。

- 证据：本地 MSYS2 GNU tar 1.35 复现——pattern 在 `-C` 前 → 文件落在 cwd；`-C` 放最前 → 正常落入目标目录；无成员参数的经典用法 `tar xf a.tgz -C dir` 不受影响（这也是 Arch 导入 `06-xorg-xfce.sh` 一直正常的原因）。
- 修复：`tar -C /usr/share/themes/ -xf "$THEME_DL" --wildcards '*/Rea/Rea-Dark/*' --strip-components=2`（`-C` 提到最前），并预先 `mkdir -p /usr/share/themes/Rea-Dark`。

## 根因四十三（NetworkManager 段函数外使用 local）
`chroot/05-extras.sh` NetworkManager 段在顶层作用域写了 `local nm_paths=()`（bash 的 `local` 只能在函数内使用），且该数组构建后从未被消费（纯死代码）。Rea-Dark 主题修复后流程首次推进到此处即中止。

- 证据：`/build/chroot/05-extras.sh: 第 1706 行:local: 只能在函数中使用`
- 修复：删除死代码块（`local nm_paths=()` + while/find 循环 + `/etc` append，共8行）。
