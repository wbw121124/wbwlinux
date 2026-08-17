# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：gettext 根因（toolchain 快照 exclude）已修复并验证（run#22 ch7 全过），Tcl/sys 传递（根因二/三）已修；run#28 推进至 ch8 8.82 util-linux（测试挂死，已加 timeout），修复后继续 ch8 长跑直至产出 ISO。

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
- [ ] 9. ch8 剩余（8.79 D-Bus 起）逐个处理后续失败直至 ISO。
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
