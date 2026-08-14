# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：gettext 根因（toolchain 快照 exclude）已修复并验证，run#22 已越过 ch7 全部包、ch8 推进至 8.17 Tcl-8.6.17，修复后继续 ch8 长跑直至产出 ISO。

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

## 待办任务
- [x] 1-6（历史，见下）ccache-wrap 根治 → run#17 toolchain 通过。
- [x] 7. gettext 根因定位（sys/cdefs.h）与修复（cb86455）→ run#22 ch7 全过。
- [x] 8. **修 pkg_run 顶层目录名不匹配**（tcl8.6.17-src 解压出 tcl8.6.17/）→ 已修（common.sh：`tar -tf` 取真实顶层名 + mv 重命名，本地模拟验证含残留目录场景）→ 待 run#23 验证。
- [ ] 9. ch8 剩余（8.18 Expect 起）逐个处理后续失败直至 ISO。
- [ ] 10. （可选）清理 `D:\wbw121124` 遗留 `ghlog.py tail --latest` 进程（PID 4732）。

## run#17 结果（2026-08-14，回顾）
**交叉工具链（ch5+ch6）构建成功**。日志 73802 行实证：`libgcc_s.so` 安装于 `/mnt/lfs/usr/lib/`（常规 GCC 布局），工具链断言文件 `10-host-stage.sh` 曾错误地在 gcc 私有目录（`$LFS/usr/lib/gcc/$LFS_TGT/15.2.0/`）查找 → 断言误报。修复：断言路径改动态推导（`-print-libgcc-file-name`）；glibc 5.5 校验块加 `CCACHE_DISABLE=1`。

## 历史根因（已修复，run#13/14/15 定案）
**ccache-wrap 为 `x86_64-lfs-linux-gnu-cc`/`-c++` 建了符号链接，但 gcc pass1 install 从不安装这两个真实编译器** → gcc pass2 目标编译器搜到毒链接 → `configure-target-libgcc` 用 `x86_64-lfs-linux-gnu-cc` 编译探测失败（ccache 找不到真实编译器）→ libgcc 从未构建/安装，base job 端暴露（crtbeginS.o/-lgcc/-lgcc_s not found）。修复：`01-host-prep.sh` 移除这两个包装链接，目标编译器回落 `-gcc`。

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
