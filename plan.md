# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：run#17 已成功越过交叉工具链（gcc pass2），准备 run#18 推进 ch8 81 包长跑直至产出 ISO。

## 根因（已定位，run#13/14/15 实证，run#15 完整日志定案）
**最终根因：ccache-wrap 为 `x86_64-lfs-linux-gnu-cc`/`-c++` 建了符号链接，但 gcc pass1 install 从不安装这两个真实编译器。**
1. `01-host-prep.sh` 在 `$LFS_ROOT/ccache-wrap` 建指向 ccache 的链接（gcc g++ cc c++ 及 `$LFS_TGT-{gcc,g++,cc,c++}`）。
2. gcc pass2 configure（顶层，11:43:44）为目标编译器搜索 PATH，`$LFS_TGT-cc` 命中 ccache-wrap 链接（只查存在性，不探测）→ `CC_FOR_TARGET='x86_64-lfs-linux-gnu-cc --sysroot=/mnt/lfs'`。
3. `configure-target-libgcc`（11:51:35）用该 CC 做编译探测 → ccache 按名字找真实编译器：
   `ccache: error: Could not find compiler "x86_64-lfs-linux-gnu-cc" in PATH`（`$LFS/tools/bin` 无此名）→
   `configure: error: cannot compute suffix of object files: cannot compile` → `Makefile:14145: configure-target-libgcc` Error 1。
4. 原始 LFS（无 ccache-wrap）PATH 里没有 `$LFS_TGT-cc` → 搜索落到 `$LFS_TGT-gcc`（真实存在）→ 一切正常。`-gcc`/`-g++` 包装器全程正常（glibc 及 pass2 自身均用它们编译成功）。
5. 由此 libgcc（crtbeginS.o / crtbegin.o / libgcc.a / libgcc_s.so*）从未构建/安装；旧 run 中后续 `make install` 照跑、脚本未拦截 → 快照带病，base job 才暴露（crtbeginS.o/-lgcc/-lgcc_s not found）。
6. 附带异常（run#15 中为正常现象）：libstdc++ configure 的 `shared libgcc... no` 警告由 5 引起。

## 待办任务
- [x] 1. 修 `scripts/stages/10-host-stage.sh` gcc pass2 configure（6.18 节，332-352 行），对照 LFS-CN ch6.18 补齐：
  - `--disable-fixincludes`
  - `CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++"`（文档强调：不用宿主编译器构建目标运行库）
  - `target_configargs=gcc_cv_target_thread_file=posix`
- [x] 2. 核对 pass2 无 `--with-gxx-include-dir`（头不应装到 /tools）；`LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc` 已有。（5.6 libstdc++ 的 `--with-gxx-include-dir=/tools/...` 按书保留）
- [x] 3. `scripts/common.sh`：pkg_run/shell_run/chroot_wrap 的 body 改 `bash -e -c`（原 `bash -c` 只返回最后一条命令退出码 → run#13/14 中 pass2 `make` 失败被后续 `ln -sv` 成功掩盖）；失败时保留 config.log 到 `$SOURCES/.diag/`。
- [x] 4. pass2 `make DESTDIR=$LFS install` 后加断言：`$LFS/usr/lib/gcc/$LFS_TGT/15.2.0/{crtbeginS.o,libgcc.a,libgcc_s.so}`，缺失即 die。
- [x] 5. 提交推送（b270277、f74afd1）→ run#15/16 同点失败（ccache-wrap `-cc` 毒链接），详见上方根因。
- [x] 6. **根治 ccache-wrap**：`scripts/01-host-prep.sh` 移除 `x86_64-lfs-linux-gnu-cc` / `x86_64-lfs-linux-gnu-c++` 包装链接（真实编译器不存在）→ gcc pass2 目标编译器回落 `-gcc`。→ run#17 验证。
- [ ] 7. base 越过 gettext-1.0 后继续 ch8 长跑，逐个处理后续失败。
- [ ] 8. （可选）清理 `D:\wbw121124` 遗留 `ghlog.py tail --latest` 进程（PID 4732）。

## run#17 结果（2026-08-14）
**交叉工具链（ch5+ch6）构建成功**。日志 73802 行实证：`libgcc_s.so` 安装于 `/mnt/lfs/usr/lib/`（常规 GCC 布局），工具链断言文件 `10-host-stage.sh` 错误地在 gcc 私有目录（`$LFS/usr/lib/gcc/$LFS_TGT/15.2.0/`）查找它 → 断言误报失败。根因修复后 toolchain 已通过。
- 附带发现：断言路径硬编码 15.2.0 → 已改动态推导（`-print-libgcc-file-name`）。

## 本轮修复清单（未提交，准备 run#18）
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
