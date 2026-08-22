# LFS-CN — 基于 LFS 13.0 (systemd) 的 Live ISO 构建流水线

在 GitHub Actions 上从零编译 Linux From Scratch 13.0-systemd，产出 x86_64
Live ISO（GRUB 双引导 BIOS/UEFI，中文终端环境）。

## 包含软件

| 软件 | 版本 | 来源 |
|---|---|---|
| Linux 内核 | 6.18.10 | LFS 源码编译 |
| GCC | 15.2.0 | LFS 源码编译 |
| Python | 3.14.3 | LFS 源码编译 |
| Vim | 9.2.0078 | LFS 源码编译 |
| Bash | 5.3 | LFS 源码编译 |
| Node.js | 24.19.0 | 官方预编译二进制 |
| Rust | 1.93.1 | 官方预编译二进制 |
| PowerShell | 7.6.4 | 官方 tarball |
| Neovim | stable | 官方预编译 |
| Nano | 8.7.1 | BLFS 源码编译（UTF-8） |
| ICU | 78.2 | BLFS 源码编译 |
| fbterm + 文泉驿微米黑 | 1.7 / 0.2.0-beta | 源码/字体 |
| Fira Code | 6.2 | 官方 release（等宽编程字体） |
| ucimf + fbterm-ucimf | 2.3.8 / 0.2.9 | 源码编译（控制台输入法框架） |
| OVIMGeneric + zh_CN 码表 | openvanilla-modules | 源码编译（拼音/双拼/五笔/郑码等） |

以及 LFS 书中全部基础包（glibc、systemd、perl、openssl、util-linux 等）。

## 中文终端体验

- `zh_CN.UTF-8` locale（含 GB18030）
- `/etc/vimrc`、`/etc/nanorc`、`/etc/xdg/nvim/init.lua` 已配置 UTF-8/GB18030
- tty1 自动登录 root，自动启动 fbterm（Fira Code 西文 + 文泉驿微米黑中文，16 号）
- 引导与文本登录界面保持英文（vconsole 无中文字形）；进入 fbterm 后界面与消息全中文
- `Ctrl+Space` 开/关中文输入，`Ctrl+Shift` 切换输入法（拼音、双拼、五笔86、郑码等 12 种 zh_CN 码表）
- `fbterm-zh` 命令可手动启动中文终端
- systemd-networkd 自动 DHCP

## 流水线结构（4 个串行 job）

1. **toolchain** — 宿主依赖 + 下载校验全部源码 + ch5/ch6 交叉工具链
2. **base** — 进入 chroot 构建 ch7.5–7.13 + ch8 全部基础包
3. **config+extras** — 系统配置（中文 locale/网络/时区）+ 预编译软件 + ICU/nano/fbterm/字体
4. **iso** — 内核（defconfig + 定制 fragment）+ initramfs + squashfs + GRUB live ISO

每 job 结束把 `/mnt/lfs` 打成 `tar.zst` 快照，经 artifact 传给下一 job，
失败重跑只需从上一个快照继续。

## 触发方式

- 手动：Actions → Build LFS-CN Live ISO → Run workflow
- push 到 main 分支自动触发

## 注意事项

- 完整构建约 3.5–5 小时（2 核 runner），4 个 job 的代码与工具链约 8–12 GB artifact。
  快照按 `450M` 分卷上传（`SNAP_PART_SIZE` 可调），规避单文件限制。
  免费 GitHub 账户 artifact 存储配额有限（数百 MB），若配额不足请及时清理
  旧的快照 artifact，或使用付费/企业账户。
- 快照需要 ~10 GB runner 磁盘，`ubuntu-latest`（14 GB）满足要求。
- 全部脚本在仓库内自包含，源码清单见 `tools/x86_64/wget-list`（LFS 13.0）。

## 目录结构

```
.github/workflows/build-lfs-iso.yml   # 4 job 流水线
scripts/
  env.sh                              # 全局版本/路径
  common.sh                           # pkg_run/shell_run/chroot/快照 等
  01-host-prep.sh                     # 宿主依赖 + 源码下载校验
  02-toolchain.sh                     # ch5 + ch6（宿主侧）
  03-chroot-base.sh                   # ch7.5-7.13 + ch8（chroot 内）
  04-sysconfig.sh                     # 系统配置（zh_CN/网络/自动登录）
  05-extras.sh                        # Node/Rust/PowerShell/Neovim/ICU/nano/fbterm/字体
  06-kernel-iso.sh                    # 内核 + initramfs + squashfs + GRUB ISO
  chroot/                             # chroot 内执行的脚本
  stages/                             # 由 LFS 书自动生成的构建块（tools/gen_stage_scripts.py）
tools/
  gen_stage_scripts.py                # 从 LFS 书 HTML 提取命令生成 stages
  x86_64/wget-list, md5sums           # LFS 13.0 源码清单
config/
  kernel-live.fragment                # live 内核配置片段
```

## 本地验证

```bash
bash -n scripts/*.sh            # 语法检查
python tools/gen_stage_scripts.py <LFS-BOOK.html> scripts/stages  # 重新生成阶段脚本
```
