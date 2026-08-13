# LFS-CN Live ISO 构建计划

## 目标
在 GitHub Actions 上构建 LFS-CN Live ISO。当前阶段：修复 base 系统构建在 ch7.7 gettext-1.0 处 `C compiler cannot create executables` 失败，推进到 ch8 81 包长跑直至产出 ISO。

## 根因（已定位，run#13/14 实证）
1. **gcc pass2 的 `make all` 阶段 `configure-target-libgcc` 失败**（log14tc.txt 09:14:36-37）：
   ```
   checking for x86_64-lfs-linux-gnu-gcc... x86_64-lfs-linux-gnu-cc  --sysroot=/mnt/lfs
   configure: error: cannot compute suffix of object files: cannot compile
   make[1]: *** [Makefile:14488: configure-target-libgcc] Error 1
   make: *** [Makefile:1065: all] Error 2
   ```
2. 由此 libgcc（crtbeginS.o / crtbegin.o / libgcc.a / libgcc_s.so*）**从未构建/安装**，快照中 `/usr/lib/gcc/x86_64-lfs-linux-gnu/15.2.0/` 缺失这些文件。
3. 但随后的 `make DESTDIR=$LFS install` 照跑（gcc driver、cc1、fixincludes、libstdc++ 都装上）→ chroot 内 gcc/cc1 冒烟正常，实际链接时 ld 报：
   `cannot find crtbeginS.o` / `cannot find -lgcc` / `cannot find -lgcc_s`（log14base.txt ~320 行）。
4. **脚本未拦截 make 失败** → toolchain job 报绿但产物带病，失败延迟到 base job 才暴露。
5. 附带异常：
   - 09:07:06 libstdc++ configure：`checking for shared libgcc... no` + `WARNING: === you are not building a shared libgcc_s.`
   - libstdc++ 头被装到 `/mnt/lfs/tools/x86_64-lfs-linux-gnu/include/c++/15.2.0`（tools 前缀，非 /usr）——怀疑 `--with-gxx-include-dir` 或 gcc_tooldir 解析问题。

## 待办任务
- [x] 1. 修 `scripts/stages/10-host-stage.sh` gcc pass2 configure（6.18 节，332-352 行），对照 LFS-CN ch6.18 补齐：
  - `--disable-fixincludes`
  - `CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++"`（文档强调：不用宿主编译器构建目标运行库）
  - `target_configargs=gcc_cv_target_thread_file=posix`
- [x] 2. 核对 pass2 无 `--with-gxx-include-dir`（头不应装到 /tools）；`LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc` 已有。（5.6 libstdc++ 的 `--with-gxx-include-dir=/tools/...` 按书保留）
- [x] 3. `scripts/common.sh`：pkg_run/shell_run/chroot_wrap 的 body 改 `bash -e -c`（原 `bash -c` 只返回最后一条命令退出码 → run#13/14 中 pass2 `make` 失败被后续 `ln -sv` 成功掩盖）；失败时保留 config.log 到 `$SOURCES/.diag/`。
- [x] 4. pass2 `make DESTDIR=$LFS install` 后加断言：`$LFS/usr/lib/gcc/$LFS_TGT/15.2.0/{crtbeginS.o,libgcc.a,libgcc_s.so}`，缺失即 die。
- [ ] 5. 提交推送 → run#15（改 scripts/ → ccache key 变化 → toolchain 全量重编，耗时较长）。
- [ ] 6. base 越过 gettext-1.0 后继续 ch8 长跑，逐个处理后续失败。
- [ ] 7. （可选）清理 `D:\wbw121124` 遗留 `ghlog.py tail --latest` 进程（PID 4732）。

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
- `D:\wbwlinux\.github\workflows\build-lfs-iso.yml`：HEAD=5582590，含 DIAGNOSE 冒烟步骤（mkdir -p /tmp + gcc -v、binutils 运行时、libgcc 位置检查）。
- `D:\wbw121124\log14tc.txt`：根因证据（09:14:36-37 configure-target-libgcc Error 1/2）。
- `D:\wbw121124\log14base.txt`：base 失败证据（ld cannot find crtbeginS.o / -lgcc / -lgcc_s，约 320 行）。
- LFS-CN 参考：https://lfs.xry111.site/zh_CN/systemd/chapter06/gcc-pass2.html
