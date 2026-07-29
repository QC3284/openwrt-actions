# openwrt-actions

利用 GitHub Actions 自动编译 OpenWrt / ImmortalWrt / LEDE / X-Wrt 固件。

> [!WARNING]
> 目前仅 **ImmortalWrt** 工作流处于积极维护中，其余工作流（LEDE / OpenWrt / X-Wrt）已停止更新，仍可运行但可能存在未知问题，请谨慎使用。

## 工作流

| 工作流 | 源码 | 状态 | 说明 |
| --- | --- | --- | --- |
| `Build-immortalwrt.yml` | [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) | ✅ 维护中 | 多设备矩阵并行编译 (MT798x 系列)，含失败处理 |
| `Build-lede.yml` | [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) | ⛔ 停止更新 | 编译 LEDE |
| `Build-openwrt.yml` | [openwrt/openwrt](https://git.openwrt.org/openwrt/openwrt.git) | ⛔ 停止更新 | 编译官方 OpenWrt (main 分支) |
| `Build-X-wrt.yml` | [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt) | ⛔ 停止更新 | 按指定 tag 编译 X-Wrt |
| `Clean-old-configs.yml` | — | ✅ 维护中 | 每周日清理旧配置，每设备仅保留最新 |

所有工作流均支持定时触发（每周三、六 03:00 北京时间）、手动触发 (workflow_dispatch) 和 repository_dispatch。
`Clean-old-configs.yml` 每周日 23:00（北京时间）执行。

## ImmortalWrt 编译流程

1. **check-source**：定时触发时通过 `git ls-remote` 获取源码远端最新提交，与 `config/immortalwrt-last-commit.txt` 对比；若所有设备源码均未变更则跳过编译，手动触发不检查
2. **prepare**：读取 `config/immortalwrt-mt798x-enable-configs.txt` 中启用的设备，在 `config/immortalwrt-mt798x/` 中按文件名时间戳自动选取每个设备最新的 `.config`，生成编译矩阵
3. **compile**（矩阵并行，每设备独立 job）：
   - 拉取源码后，通过 `script/immortalwrt-switch-branch.sh` 按 `config/immortalwrt-device-branch.txt` 切换设备对应分支（未配置则默认 `25.12`）
   - 执行 DIY 脚本注入第三方插件，更新并安装 feeds
   - 打入 `files/etc/uci-defaults/99-custom.sh`（首次启动自动执行，见下文 uci-defaults）
   - 先 `make -j$(nproc+1)` 编译，失败自动回退 `make -j1 V=s` 定位错误
   - **成功**：打包 bin 目录 (bin.7z)，生成 `sha256sums.txt` 和 `build-info.txt`（含源码分支/提交等溯源信息），上传 Artifact 并发布 Release
   - **失败**：提取关键错误生成 `error_report.md`（输出到 Step Summary），上传日志并创建草稿 Release
   - 支持 `concurrency` 控制：定时触发时自动取消未完成的旧执行，手动触发不受影响
   - make.log 超过 10 万行时自动截断为首尾各 3000 行，避免上传失败

## 目录结构

```
├── .github/workflows/        # 各源码的编译工作流
├── config/
│   ├── immortalwrt-mt798x/                    # 各设备编译配置 (按 设备名-时间戳 命名)
│   ├── immortalwrt-mt798x-enable-configs.txt  # 启用编译的设备列表
│   ├── immortalwrt-device-branch.txt          # 机型与源码分支对应表
│   ├── immortalwrt-last-commit.txt            # 各分支上次编译时的远端提交 SHA
│   ├── *-url.txt                              # 各源码仓库地址 (含分支参数)
│   ├── *-banner*.txt                          # 自定义登录 banner
│   ├── x-wrt-config-tag.txt                   # X-Wrt 编译使用的 tag
│   └── old_configs/                           # 历史配置存档
└── script/
    ├── immortalwrt-actions-diy1.sh   # feeds update 前：克隆第三方插件
    ├── immortalwrt-actions-diy2.sh   # feeds update 后：替换 OpenClash
    ├── immortalwrt-switch-branch.sh  # 按机型切换源码分支
    ├── immortalwrt-uci-defaults.sh  # uci-defaults: LAN IP, SSH 切换, mirrors.sh
    ├── *-ip.sh                       # 修改默认管理 IP (192.168.5.1)
    ├── *-txt*.sh / *-rl.sh           # 生成 Release 说明
    ├── x-wrt-git-001.sh              # 替换 coremark 包
    ├── x-wrt-make-001.sh             # 预下载依赖并清理残缺包
    └── gitcj.py + giturl.txt         # 批量克隆第三方 luci 插件
```

## 常用操作

### 新增/更新设备配置 (ImmortalWrt)

1. 将 `.config` 命名为 `immortalwrt-actions-<芯片型号>-<设备名>-<YYYYMMDDHHMMSS>.config`（如 `immortalwrt-actions-mt7981-glinet_gl-mt3000-20260710202710.config`）放入 `config/immortalwrt-mt798x/`
2. 在 `config/immortalwrt-mt798x-enable-configs.txt` 中添加设备名（每行一个，`#` 为注释）
3. 如需非默认分支，在 `config/immortalwrt-device-branch.txt` 中添加 `<设备名> <分支名>`

工作流会自动选取每个设备时间戳最新的配置文件。

### 停用某个设备

在 `config/immortalwrt-mt798x-enable-configs.txt` 中删除或注释对应行即可，无需删除配置文件。

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

- 管理地址：`192.168.5.1/24`
- 账号/密码：`root` / 无密码
- SSH：`openssh-server` 已启用（允许 root 密码登录），`dropbear` 已禁用（LuCI 状态同步）
- LuCI：默认启用，通过 `http://192.168.5.1` 访问

## 许可证

[GPL-3.0](LICENSE)
