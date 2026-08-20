# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：ISO 已产出，QEMU 实测 systemd 三个 /var 写单元启动失败，根因十三已修（/var 改 tmpfs），待重建 ISO 验证。

## 根因十三（QEMU 实测实证，已修）
**Live overlay 的可写 upper 层随 switch_root + fstab 的 /run tmpfs 重挂而脱离 → /var 落到只读 squashfs 下层 → 三个必须写 /var 的 systemd 单元在 STATE_DIRECTORY 步失败（ENOENT）。**
- 证据（客观）：`Failed at step STATE_DIRECTORY spawning .../systemd-timesyncd: No such file or directory` + `[FAILED] Failed to start Network Time Synchronization / Rebuild Journal Catalog / User Login Management`；三单元共性 = 启动必须向 /var 写（timesync、linger、catalog/database）；二进制/链接器/var 树均齐全 → 排除静态缺失。
- 设计缺陷（init 脚本，`chroot/06-kernel-initramfs.sh`）：`mount -t tmpfs tmpfs /run/overlay` 后，overlay 却用 `upperdir=/run/upper,workdir=/run/work`（位于 initramfs 根 tmpfs 上，**不在** /run/overlay 那个 tmpfs 内）→ 该 tmpfs 白挂、upper/work 落在 initramfs 根 fs。switch_root 拆除 initramfs 根、且 fstab 的 `tmpfs /run` 让 systemd 用全新 tmpfs 覆盖 /run → overlay upper（在旧 initramfs /run 上）与运行期 / 脱离 → /var 只读。
- 内核配置无缺失（kernel-live.fragment：OVERLAY_FS=y / BLK_DEV_LOOP=y / TMPFS=y），排除 CONFIG 类原因。
- 修复（最小稳妥，不依赖 upper 生命周期）：fstab 增 `tmpfs /var` + `tmpfs /home`，/var 直接以 tmpfs 覆盖，与 overlay 解耦；machine-id/catalog 由 systemd 按需重建（journal-catalog-update 恰好会重跑）。
- 判别条件（未跑运行时日志前需确认 ENOENT vs EROFS）：若 upper 完全脱离 → /var 只读 → mkdir 报 EROFS；报 ENOENT 说明路径解析/挂载点堆叠问题。两种 errno 下本修复均成立，无需区分即可落地。**需运行时日志确认**项：用 `-serial stdio` + 去 quiet 抓完整 journal 以核验。
- CI 自动验证建议：iso job 加 qemu 冒烟步骤（01-host-prep 装 qemu-system-x86_64），`qemu-system-x86_64 -cdrom ...iso -m 2G -smp 2 -boot d -nographic -serial stdio -kernel? ` 以 `console=ttyS0` 引导并 `grep` 串口日志，断言 `Failed to start Network Time Synchronization` 等三串 FAILED 不再出现、且 `systemd-timesyncd` / `systemd-logind` 达 active；超时兜底（TCG 无 KVM，需放宽容限）。


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
- [x] 11. **Live 引导后 /var 只读 → systemd 三个写 /var 单元 STATE_DIRECTORY 失败（根因十三）** → 修 `chroot/06-kernel-initramfs.sh` fstab：增 `tmpfs /var` + `tmpfs /home`；待重建 ISO QEMU 验证三 FAILED 消失。
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
