# openwrt-actions

[![Build ImmortalWrt](https://github.com/QC3284/openwrt-actions/actions/workflows/Build-immortalwrt.yml/badge.svg)](https://github.com/QC3284/openwrt-actions/actions/workflows/Build-immortalwrt.yml)
[![Validate](https://github.com/QC3284/openwrt-actions/actions/workflows/Validate.yml/badge.svg)](https://github.com/QC3284/openwrt-actions/actions/workflows/Validate.yml)

A GitHub Actions CI/CD project for building OpenWrt-based firmware. Supports multi-device matrix builds, automatic source change detection, build failure diagnostics, firmware checksum verification, and first-boot auto-configuration (LAN IP, SSH migration, mirror switching).

> [!WARNING]
> Only the **ImmortalWrt** workflows are actively maintained. The remaining workflows (LEDE / OpenWrt / X-Wrt) have been discontinued. They may still run but firmware may contain unresolved defects, and related issues will not be addressed. Use at your own risk.

> [中文文档](README.md)

## Workflows

| Workflow | Source | Status | Description |
| --- | --- | --- | --- |
| `Build-immortalwrt.yml` | [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) | ✅ Active | Matrix parallel builds with change-skip, failure diagnostics, SHA256 checksums, build traceability |
| `Build-immortalwrt-single.yml` | [immortalwrt-mt798x-rebase](https://github.com/chasey-dev/immortalwrt-mt798x-rebase) | ✅ Active | Single-device manual build with branch and config override |
| `Build-lede.yml` | [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) | ⛔ Discontinued | Build LEDE |
| `Build-openwrt.yml` | [openwrt/openwrt](https://git.openwrt.org/openwrt/openwrt.git) | ⛔ Discontinued | Build official OpenWrt (main branch) |
| `Build-X-wrt.yml` | [x-wrt/x-wrt](https://github.com/x-wrt/x-wrt) | ⛔ Discontinued | Build X-Wrt by specified tag |
| `Clean-old-configs.yml` | — | ✅ Active | Weekly cleanup, keeping only the latest config per device |
| `Validate.yml` | — | ✅ Active | Auto-validate Shell/Python/YAML/config on PR/push |

`Build-immortalwrt.yml` schedule: Wed & Sat 03:00 (UTC+8), also supports manual triggers (`workflow_dispatch` / `repository_dispatch`).
`Clean-old-configs.yml` schedule: Sun 23:00 (UTC+8), also supports manual triggers.
`Build-immortalwrt-single.yml` is manual-only with device name, branch, and config inputs.

### Current Build Targets (ImmortalWrt)

| Device | Chip | Branch |
|------|------|------|
| `glinet_gl-mt3000` | mt7981 | 25.12 |
| `konka_komi-a31` | mt7981 | 25.12 |
| `glinet_gl-mt3600be` | mt7987 | 25.12-dev-wifi7 |

## Quick Start

### First-Time Setup (ImmortalWrt)

1. Fork this repository
2. In repo Settings → Actions → General, ensure Actions are enabled (disabled by default after fork)
3. Edit `config/immortalwrt-mt798x-enable-configs.txt` and add the device names to build
4. Name your `.config` as `immortalwrt-actions-<chip>-<device>-<timestamp>.config` and place it in `config/immortalwrt-mt798x/`
5. To change the default branch, edit `config/immortalwrt-default-branch.txt`; for per-device branches, edit `config/immortalwrt-device-branch.txt`
6. Manually trigger `Build-immortalwrt-single.yml` from the Actions tab to test a single device
7. Once verified, `Build-immortalwrt.yml` will run automatically on schedule

### Single-Device Test (ImmortalWrt)

Select `Build-immortalwrt-single.yml` → Run workflow in the Actions tab:
- `device`: Enter the device name (e.g., `glinet_gl-mt3000`)
- `branch`: Leave blank to use config file, or specify manually (e.g., `25.12-dev-wifi7`)
- `config`: Leave blank for auto-selection (latest), or specify a filename

## ImmortalWrt Build Pipeline

1. **check-source**: On schedule, fetches the latest upstream commits via `git ls-remote` and compares against `config/immortalwrt-last-commit.txt`. Skips building if no source changes are detected. Manual triggers always proceed.
2. **prepare**: Reads `config/immortalwrt-mt798x-enable-configs.txt` for enabled devices, scans `config/immortalwrt-mt798x/` for the latest `.config` per device (by timestamp), and generates a build matrix.
3. **compile** (matrix, one job per device):
   - Pulls source code and switches branch via `script/immortalwrt-switch-branch.sh` using `config/immortalwrt-device-branch.txt` (falls back to `config/immortalwrt-default-branch.txt`, defaulting to `25.12`)
   - Runs DIY scripts to inject third-party packages, updates and installs feeds
   - Copies `files/etc/uci-defaults/99-custom.sh` for first-boot auto-configuration (see uci-defaults below)
   - Compiles with `make -j$(nproc+1)`, falling back to `make -j1 V=s` on failure for detailed diagnostics
   - **Success**: Packages bin directory (bin.7z), generates `sha256sums.txt` and `build-info.txt` (with source branch/commit traceability), uploads Artifact and creates Release
   - **Failure**: Extracts key errors into `error_report.md` (visible in Step Summary), uploads logs and creates a draft Release
   - Concurrency control: automatically cancels stale in-progress runs on schedule, manual triggers unaffected
   - make.logs exceeding 100,000 lines are truncated to first and last 3,000 lines to prevent upload failures
   - A `summarize` job aggregates all device results, outputs a summary report, and cleans up old Releases

## Directory Structure

> Note: Contains workflow scripts and configs for all 4 firmware builds. `immortalwrt-*` prefixed files are ImmortalWrt-specific; `lede-*` / `x-wrt-*` are legacy files from discontinued workflows.

```
├── .github/workflows/        # Workflow definitions
├── .github/dependabot.yml     # Automated GitHub Actions updates
├── .gitignore
├── config/
│   ├── immortalwrt-mt798x/                    # Per-device build configs (chip-device-timestamp)
│   ├── immortalwrt-mt798x-enable-configs.txt  # Enabled device list
│   ├── immortalwrt-device-branch.txt          # Per-device source branch mapping
│   ├── immortalwrt-default-branch.txt         # Default source branch (for unmatched devices)
│   ├── immortalwrt-last-commit.txt            # Last built commit SHA per branch
│   ├── *-url.txt                              # Source repository URLs
│   ├── *-banner*.txt                          # LEDE custom login banner
│   ├── x-wrt-config-tag.txt                   # X-Wrt build tag
│   └── old_configs/                           # Historical config archive
└── script/
    ├── immortalwrt-actions-diy1.sh   # Pre-feeds-update: clone third-party packages
    ├── immortalwrt-actions-diy2.sh   # Post-feeds-update: replace OpenClash
    ├── immortalwrt-switch-branch.sh  # Switch source branch per device
    ├── immortalwrt-uci-defaults.sh   # uci-defaults: LAN IP, SSH migration, mirrors.sh
    ├── lede-github-actions-ip.sh     # LEDE: modify default LAN IP
    ├── lede-github-actions-rl.sh     # LEDE: generate release notes
    ├── x-wrt-actions-txt-001.sh      # X-Wrt: generate release notes
    ├── x-wrt-git-001.sh              # Replace coremark package
    ├── x-wrt-make-001.sh             # Pre-download dependencies, clean incomplete files (shared by ImmortalWrt/X-Wrt)
    └── gitcj.py + giturl.txt         # Batch clone third-party LuCI plugins
```

## Common Operations (ImmortalWrt)

### Adding / Updating a Device Config

1. Name the `.config` as `immortalwrt-actions-<chip>-<device>-<YYYYMMDDHHMMSS>.config` (e.g., `immortalwrt-actions-mt7981-glinet_gl-mt3000-20260710202710.config`) and place it in `config/immortalwrt-mt798x/`
2. Add the device name to `config/immortalwrt-mt798x-enable-configs.txt` (one per line, `#` for comments)
3. For non-default branches, add `<device> <branch>` to `config/immortalwrt-device-branch.txt`; to change the global default, edit `config/immortalwrt-default-branch.txt`

The workflow automatically selects the latest config by timestamp for each device.

### Disabling a Device (ImmortalWrt)

Delete or comment out the corresponding line in `config/immortalwrt-mt798x-enable-configs.txt`. The config files can remain.

### Custom Build Plugins

Edit `script/immortalwrt-actions-diy1.sh` to add or remove third-party packages integrated during compilation. Add new plugins at the end with: `git clone --depth 1 <URL> package/<dir> || { echo "警告: 克隆失败"; }`. Currently included:

| Plugin | Source | Description |
|------|------|------|
| OpenClash | `vernesong/OpenClash` | Proxy tool |
| luci-app-quickfile | `sbwml/luci-app-quickfile` | File manager |
| luci-theme-proton2025 | `ChesterGoodiny/luci-theme-proton2025` | Theme |
| luci-app-run | `wukongdaily/luci-app-run` | Run utility |

### Custom uci-defaults Configuration

Edit the `LAN_IP` variable at the top of `script/immortalwrt-uci-defaults.sh` to change the default LAN address. Mirror sources in `mirrors.sh` can be modified in the `select_mirror()` function (lines 68-78).

## uci-defaults First-Boot Configuration

Automatically embedded as `files/etc/uci-defaults/99-custom.sh` during build and executed on the device's first boot:

1. **LAN IP**: Set to `192.168.5.1/24` (CIDR format, OpenWrt 21.02+ compatible)
2. **SSH Migration**:
   - If openssh-server is installed, disables dropbear via init.d and sets `uci set enabled='0'` for LuCI status sync
   - Enables sshd, modifies `/etc/ssh/sshd_config` for root password login (`PermitRootLogin yes`), and restarts sshd
   - Migrates `/etc/dropbear/` keys and authorized_keys to `/root/.ssh/`
3. **mirrors.sh**: Interactive repository mirror switching script at `/root/mirrors.sh`
   - 7 mirror options: Official / Custom / USTC / TUNA / Aliyun / Tencent / vsean
   - Command-line argument support (e.g., `mirrors.sh 3`), defaults to custom mirror with no input
   - Compatible with opkg (24.10 and earlier) and apk (25.12 and later)
   - Strips mirror path prefixes (`/openwrt`, `/immortalwrt`, `/lede`), auto-backs up before replacing
   - Dependency-free: only requires busybox ash + sed
4. **luci-app-quickfile Detection**: If installed, auto-configures nginx UCI and restarts nginx; silently skipped otherwise
5. **wget HSTS Initialization**: Creates `/root/.wget-hsts` if missing, preventing wget HTTPS download errors

## Default Firmware Info (ImmortalWrt)

The following is applied by the uci-defaults script on first boot:

- LAN Address: `192.168.5.1/24`
- Login: `root` / no password (set a password after first login)
- SSH: If `openssh-server` is selected at build time, sshd is enabled and dropbear disabled with root password login permitted; otherwise dropbear remains active
- LuCI: Enabled by default if the `luci` package is selected, accessible at `http://192.168.5.1`

## License

[GPL-3.0](LICENSE)
