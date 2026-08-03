# openwrt-actions

[![Build ImmortalWrt](https://github.com/QC3284/openwrt-actions/actions/workflows/Build-immortalwrt.yml/badge.svg)](https://github.com/QC3284/openwrt-actions/actions/workflows/Build-immortalwrt.yml)
[![Validate](https://github.com/QC3284/openwrt-actions/actions/workflows/Validate.yml/badge.svg)](https://github.com/QC3284/openwrt-actions/actions/workflows/Validate.yml)

> [English](README_EN.md)

基于 GitHub Actions 的 OpenWrt 系固件持续集成项目，支持多设备矩阵并行编译、源码变更自动检测、编译失败诊断报告、固件校验、首次启动自动配置（LAN IP / SSH 切换 / 软件源替换）等功能。

> [!WARNING]
> 目前仅 **ImmortalWrt** 工作流处于积极维护中，其余工作流（LEDE / OpenWrt / X-Wrt）已停止更新，仍可运行但可能存在未知问题，请谨慎使用。
>
> 已停更的工作流不保证能正常运行，固件可能存在未修复的缺陷，相关问题不再接受反馈和处理。使用者需自行评估风险。

## 工作流

| 工作流 | 源码 | 状态 | 说明 |
| --- | --- | --- | --- |
| `Build-immortalwrt.yml` | [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) | ✅ 维护中 | 矩阵并行编译，含变更跳过、失败诊断、SHA256 校验、构建追溯 |
| `Build-immortalwrt-single.yml` | [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) | ✅ 维护中 | 单设备手动编译，支持指定分支和配置文件 |
| `Build-lede.yml` | [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) | ⛔ 停止更新 | 编译 LEDE |
| `Build-openwrt.yml` | [openwrt/openwrt](https://git.openwrt.org/openwrt/openwrt.git) | ⛔ 停止更新 | 编译官方 OpenWrt (main 分支) |
| `Build-X-wrt.yml` | [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt) | ⛔ 停止更新 | 按指定 tag 编译 X-Wrt |
| `Clean-old-configs.yml` | — | ✅ 维护中 | 每周日清理旧配置，每设备仅保留最新 |
| `Validate.yml` | — | ✅ 维护中 | PR/推送时自动校验 Shell/Python/YAML/配置文件 |

`Build-immortalwrt.yml` 定时触发：每周三、六 03:00（北京时间），同时支持手动触发 (`workflow_dispatch` / `repository_dispatch`)。
`Clean-old-configs.yml` 定时触发：每周日 23:00（北京时间），同时支持手动触发。
`Build-immortalwrt-single.yml` 仅手动触发，可指定设备名、分支和配置文件。

### 当前编译设备 (ImmortalWrt)

| 设备 | 芯片 | 分支 |
|------|------|------|
| `glinet_gl-mt3000` | mt7981 | 25.12 |
| `konka_komi-a31` | mt7981 | 25.12 |
| `glinet_gl-mt3600be` | mt7987 | 25.12-dev-wifi7 |

## 快速开始 (Quick Start)

### 首次使用 (ImmortalWrt)

1. Fork 本仓库
2. 在仓库 Settings → Actions → General 中确保 Actions 已启用（Fork 后默认禁用）
3. 编辑 `config/immortalwrt-mt798x-enable-configs.txt`，添加需要编译的设备名
4. 将对应 `.config` 命名为 `immortalwrt-actions-<芯片>-<设备名>-<时间戳>.config` 放入 `config/immortalwrt-mt798x/`
5. 如需修改默认分支，编辑 `config/immortalwrt-default-branch.txt`；如需按设备指定分支，编辑 `config/immortalwrt-device-branch.txt`
6. 在 Actions 页面手动触发 `Build-immortalwrt-single.yml` 测试单个设备
7. 确认无误后，`Build-immortalwrt.yml` 将按定时自动执行编译

### 单设备快速测试 (ImmortalWrt)

在 Actions 页面选择 `Build-immortalwrt-single.yml` → Run workflow：
- `device`：输入设备名（如 `glinet_gl-mt3000`）
- `branch`：留空使用配置文件中的分支，或手动指定（如 `25.12-dev-wifi7`）
- `config`：留空自动选取最新，或手动指定文件名
- `diy_enabled`：留空读取控制文件，或手动指定 `true` / `false` 覆盖

## ImmortalWrt 编译流程

1. **check-source**：定时触发时通过 `git ls-remote` 获取源码远端最新提交，与 `config/immortalwrt-last-commit.txt` 对比；若所有设备源码均未变更则跳过编译，手动触发不检查
2. **prepare**：读取 `config/immortalwrt-mt798x-enable-configs.txt` 中启用的设备，在 `config/immortalwrt-mt798x/` 中按文件名时间戳自动选取每个设备最新的 `.config`，生成编译矩阵
3. **compile**（矩阵并行，每设备独立 job）：
   - 执行 DIY 脚本注入第三方插件（可由 `config/immortalwrt-diy-control.txt` 按设备控制），更新并安装 feeds
   - 打入 `files/etc/uci-defaults/99-custom.sh`（首次启动自动执行，见下文 uci-defaults）
   - 先 `make -j$(nproc+1)` 编译，失败自动回退 `make -j1 V=s` 定位错误
   - **成功**：打包 bin 目录 (bin.7z)，生成 `sha256sums.txt` 和 `build-info.txt`（含源码分支/提交等溯源信息），上传 Artifact 并发布 Release
   - **失败**：提取关键错误生成 `error_report.md`（输出到 Step Summary），上传日志并创建草稿 Release
   - 支持 `concurrency` 控制：定时触发时自动取消未完成的旧执行，手动触发不受影响
   - make.log 超过 10 万行时自动截断为首尾各 3000 行，避免上传失败
   - `summarize` job 在编译结束后汇总所有设备结果，输出报告并清理旧 Release

## 目录结构

> 注：包含全部 4 个固件的工作流脚本和配置，其中 `immortalwrt-*` 前缀为 ImmortalWrt 专用，`lede-*` / `x-wrt-*` 为对应停更工作流的遗留文件。

```
├── .github/workflows/        # 各源码的编译工作流
├── .github/dependabot.yml     # GitHub Actions 自动更新配置
├── .gitignore
├── config/
│   ├── immortalwrt-mt798x/                    # 各设备编译配置 (按 芯片-设备名-时间戳 命名)
│   ├── immortalwrt-mt798x-enable-configs.txt  # 启用编译的设备列表
│   ├── immortalwrt-device-branch.txt          # 机型与源码分支对应表
│   ├── immortalwrt-default-branch.txt         # 默认源码分支 (未匹配设备时使用)
│   ├── immortalwrt-last-commit.txt            # 各分支上次编译时的远端提交 SHA
│   ├── immortalwrt-diy-control.txt            # DIY 脚本开关 (按设备启用/禁用)
│   ├── *-url.txt                              # 各源码仓库地址
│   ├── *-banner*.txt                          # LEDE 自定义登录 banner
│   ├── x-wrt-config-tag.txt                   # X-Wrt 编译使用的 tag
│   └── old_configs/                           # 历史配置存档
└── script/
    ├── immortalwrt-actions-diy1.sh   # feeds update 前：克隆第三方插件
    ├── immortalwrt-actions-diy2.sh   # feeds update 后：替换 OpenClash
    ├── immortalwrt-switch-branch.sh  # 按机型切换源码分支
    ├── immortalwrt-uci-defaults.sh    # uci-defaults: LAN IP, SSH 切换, mirrors.sh
    ├── lede-github-actions-ip.sh     # LEDE: 修改默认管理 IP
    ├── lede-github-actions-rl.sh     # LEDE: 生成 Release 说明
    ├── x-wrt-actions-txt-001.sh      # X-Wrt: 生成 Release 说明
    ├── x-wrt-git-001.sh              # 替换 coremark 包
    ├── x-wrt-make-001.sh             # 预下载依赖并清理残缺包 (ImmortalWrt/X-Wrt 共用)
    └── gitcj.py + giturl.txt         # 批量克隆第三方 luci 插件
```

## 常用操作 (ImmortalWrt)

### 新增/更新设备配置

1. 将 `.config` 命名为 `immortalwrt-actions-<芯片型号>-<设备名>-<YYYYMMDDHHMMSS>.config`（如 `immortalwrt-actions-mt7981-glinet_gl-mt3000-20260710202710.config`）放入 `config/immortalwrt-mt798x/`
2. 在 `config/immortalwrt-mt798x-enable-configs.txt` 中添加设备名（每行一个，`#` 为注释）
3. 如需非默认分支，在 `config/immortalwrt-device-branch.txt` 中添加 `<设备名> <分支名>`；要修改全局默认分支则编辑 `config/immortalwrt-default-branch.txt`

工作流会自动选取每个设备时间戳最新的配置文件。

### 停用某个设备 (ImmortalWrt)

在 `config/immortalwrt-mt798x-enable-configs.txt` 中删除或注释对应行即可，无需删除配置文件。

### 控制 DIY 脚本

编辑 `config/immortalwrt-diy-control.txt` 可按设备控制是否执行 DIY 脚本（第三方插件注入）。格式：`<设备名> <true|false>`。未列出的设备默认启用。

例如禁用 `glinet_gl-mt3600be` 的 DIY：

```
glinet_gl-mt3000 true
konka_komi-a31 true
glinet_gl-mt3600be false
```

### 自定义编译插件

编辑 `script/immortalwrt-actions-diy1.sh` 可添加或移除编译时集成到固件的第三方插件。新插件按以下格式追加到末尾：`git clone --depth 1 <URL> package/<目录> || { echo "警告: 克隆失败"; }`。当前集成：

| 插件 | 来源 | 说明 |
|------|------|------|
| OpenClash | `vernesong/OpenClash` | 代理工具 |
| luci-app-quickfile | `sbwml/luci-app-quickfile` | 文件管理 |
| luci-app-harbor-file | `destan19/luci-app-harbor-file` | 文件管理 |
| luci-theme-proton2025 | `ChesterGoodiny/luci-theme-proton2025` | 主题 |
| luci-app-run | `wukongdaily/luci-app-run` | 运行工具 |

### 自定义 uci-defaults 配置

编辑 `script/immortalwrt-uci-defaults.sh` 顶部的 `LAN_IP` 变量可修改默认管理地址。mirrors.sh 的镜像源列表可在脚本的 `select_mirror()` 函数中增删。

## uci-defaults 首次启动配置

编译时自动打入 `files/etc/uci-defaults/99-custom.sh`，设备首次启动后自动执行：

1. **LAN IP**：设置为 `192.168.5.1/24`（CIDR 格式，适配 OpenWrt 21.02+）
2. **SSH 切换**：
   - 检测 openssh-server 已安装后，通过 init.d 禁用 dropbear 并使用 `uci set enabled='0'` 确保 LuCI 状态同步
   - 启用 sshd，直接修改 `/etc/ssh/sshd_config` 允许 root 密码登录 (`PermitRootLogin yes`) 并重启 sshd 使配置生效
   - 迁移 `/etc/dropbear/` 下的密钥和 authorized_keys 至 `/root/.ssh/`
3. **生成 mirrors.sh**：在 `/root/mirrors.sh` 生成交互式换源脚本
   - 支持 7 个镜像源：官方 / 自定义 / USTC / TUNA / 阿里云 / 腾讯云 / vsean
   - 支持命令行参数直接指定（如 `mirrors.sh 3`），无输入则默认自定义镜像
   - 兼容 opkg（24.10 及以前）和 apk（25.12 及以后）
   - 自动去除镜像路径前缀（`/openwrt`、`/immortalwrt`、`/lede`），替换前自动备份
   - 仅依赖 busybox ash + sed，无额外依赖
4. **luci-app-quickfile 检测**：如已安装，自动配置 nginx UCI 并重启 nginx，未安装则静默跳过
5. **wget HSTS 初始化**：检查 `/root/.wget-hsts`，不存在则自动创建，避免 wget https 下载异常

## 固件默认信息 (ImmortalWrt)

以下信息由 `uci-defaults` 脚本在首次启动时自动配置：

- 管理地址：`192.168.5.1/24`
- 账号/密码：`root` / 无密码（首次登录后请设置密码）
- SSH：若编译时选中 `openssh-server`，则自动启用 sshd 并禁用 dropbear、允许 root 密码登录；否则保持 dropbear 不变
- LuCI：若编译时选中 `luci` 包则默认启用，通过 `http://192.168.5.1` 访问

## 许可证

[GPL-3.0](LICENSE)
