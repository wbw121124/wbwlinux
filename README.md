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
| Neovim | 0.12.5 | 源码编译（cmake 构建，安装到 /usr/local） |
| Nano | 8.7.1 | BLFS 源码编译（UTF-8） |
| ICU | 78.2 | BLFS 源码编译 |
| fbterm + 文泉驿微米黑 | 1.7 / 0.2.0-beta | 源码/字体 |
| Fira Code | 6.2 | 官方 release（等宽编程字体） |
| ucimf + fbterm-ucimf | 2.3.8 / 0.2.9 | 源码编译（控制台输入法框架） |
| OVIMGeneric + zh_CN 码表 | openvanilla-modules | 源码编译（拼音/双拼/五笔/郑码等） |
| man-pages-zh | 1.6.4.5-1 | Debian 预编译数据包解包（简体中文 man 手册） |
| Fira Code 字体优先级 + 彩色 prompt | — | fontconfig prefer + /root/.bashrc |
| pacman | 7.1.0 | 源码编译（含 ninja/meson/curl/libarchive 依赖链，`[lfscn]` 本地仓库） |
| curl | 8.21.0 | LFS 源码编译（pacman 依赖链，同时作为独立工具注册） |
| wget | 1.25.0 | 源码编译（`--with-ssl=openssl`） |
| git | 2.55.0 | 源码编译（NO_TCLTK/NO_PERL/NO_PYTHON，仅核心功能） |
| fd / ripgrep / bat | 10.4.2 / 15.2.0 / 0.26.1 | 官方 musl 静态二进制（零依赖直接运行） |
| htop | 3.5.3 | Debian 预编译（仅依赖 ncurses/libc） |
| sudo | 1.9.17p2 | 源码编译（BLFS 风格，shadow 认证 + `/etc/sudoers` + wheel 组，visudo 在 `/usr/sbin`） |
| which | — | 最小 POSIX sh 脚本实现 |
| NetworkManager | 1.58.1 | Arch 预编译包解包（pacman 7.1 需要，`[lfscn]` 仓库可安装） |
| VS Code | 1.134.0 | 微软官方 tarball 解包（`[lfscn]` 仓库可安装，默认未安装） |
| Firefox | 154.0 | Mozilla 官方 tarball 解包（`[lfscn]` 仓库可安装，默认未安装） |
| X.Org Server + XFCE4 | xorg-server / xfce4 全家桶 | Arch 二进制仓库依赖闭包导入（构建期解析，LFS 已有库全部跳过） |
| Rea-Dark 主题 | 1a422b0 (2026-02-24) | GitHub orchyn/XFCE（GTK2/GTK3/xfwm4，默认暗色主题，compositing 关闭） |

以及 LFS 书中全部基础包（glibc、systemd、perl、openssl、util-linux 等）。

## 中文终端体验

- `zh_CN.UTF-8` locale（含 GB18030）
- `/etc/vimrc`、`/etc/nanorc`、`/etc/xdg/nvim/init.lua` 已配置 UTF-8/GB18030
- tty1 自动登录 root，自动启动 fbterm（Fira Code 西文 + 文泉驿微米黑中文，16 号）
- 引导与文本登录界面保持英文（vconsole 无中文字形）；进入 fbterm 后界面与消息全中文
- `Ctrl+Space` 开/关中文输入，`Ctrl+Shift` 切换输入法（拼音、双拼、五笔86、郑码等 12 种 zh_CN 码表，
  另含自建 **cs-oi.cin**：简拼缩写 → 算法竞赛中文术语 220 词条，如 `dp`→动态规划、`bcj`→并查集、`xds`→线段树）
- `fbterm-zh` 命令可手动启动中文终端
- `man ls` 等命令中文手册（man-pages-zh，zh_CN 会话自动生效；英文会话保持英文页）
- 彩色提示符（root 红 user@host + 蓝路径）与 `ls --color=auto`
- systemd-networkd 自动 DHCP

## 包管理器（pacman）与持久化

- 预装 pacman 7.1.0，配置文件 `/etc/pacman.conf`：
  - 数据库放在 `/usr/local/lib/pacman`（`/var` 在 live 系统是 tmpfs，不能存状态）
  - 内置本地仓库 `[lfscn]`：nodejs、rust、powershell、neovim、fira-code-fonts、
    wqy-microhei-fonts、fbterm-ucimf-stack、man-pages-zh、curl、wget、fd、ripgrep、
    bat、htop 十四个包已注册，
    可用 `pacman -Q`/`pacman -Qi <包名>` 查询、`pacman -R <包名>` 卸载
  - Arch 官方源默认注释禁用——运行期 pacman 不可直接安装 Arch 包（滚动版二进制
    链接最新 glibc，与本系统的 LFS 13.0 工具链不匹配）。X.Org+XFCE 是**构建期**
    受控导入：依赖闭包解析时 LFS 已提供的库全部跳过（绝不引入 Arch 的 glibc/gcc-libs），
    解包用 tar `--skip-old-files` 保证已有文件以 LFS 版本为准，仅新增文件落盘
- **会话持久化**：引导时 initramfs 自动探测各分区
  - 分区根目录含 `upper/` 目录 → 直接作为 overlay 上层（建议 ext4 并设卷标 `LFS-CN-PERSIST`）
  - 或分区根目录含 `lfs-cn-persistence.img` 文件（ext4 镜像，FAT/exFAT U 盘也可用）→ loop 挂载后作为上层
  - 找到任一介质即「持久会话」：写入 /etc、/root 等在重启后保留（`/var`、`/home` 仍为 tmpfs）
  - GRUB 第二菜单项「volatile session」加 `persist=off` 强制关闭探测
  - 制作镜像文件示例（在任意 FAT32 U 盘上）：`truncate -s 8G lfs-cn-persistence.img && mkfs.ext4 -F lfs-cn-persistence.img`

## 流水线结构（4 个串行 job）

1. **toolchain** — 宿主依赖 + 下载校验全部源码 + ch5/ch6 交叉工具链
2. **base** — 进入 chroot 构建 ch7.5–7.13 + ch8 全部基础包
3. **config+extras** — 系统配置（中文 locale/网络/时区）+ 预编译软件 + ICU/nano/fbterm/字体
   + CLI 工具包（fd/rg/bat/htop/wget/which）+ X.Org+XFCE 二进制闭包导入
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
                                      # + fd/rg/bat/htop/wget/which 下载与分发
  06-kernel-iso.sh                    # 内核 + initramfs + squashfs + GRUB ISO
  chroot/                             # chroot 内执行的脚本
    05-extras.sh                      #   extras 安装（含 cs-oi.cin 码表、pacman tmpfiles 修复）
    06-xorg-xfce.sh                   #   Arch 二进制闭包导入 X.Org+XFCE
    arch-resolve.py                   #   依赖闭包解析器（SKIP LFS 已有库）
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
