#!/usr/bin/env bash
# File: setup-device.sh — 设备配置一键接入 (README 快速开始第 3~5 步)
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions

set -euo pipefail

# ===== 颜色 (仅 TTY 且未设 NO_COLOR 时启用; 管道/CI 自动降级纯文本) =====
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD="\033[1m"; DIM="\033[2m"
  GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; CYAN="\033[36m"; BLUE="\033[34m"
  RESET="\033[0m"
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; BLUE=""; RESET=""
fi
STEP_TOTAL=5

info()  { printf "%b\n" "${GREEN}ℹ${RESET} $*"; }
ok()    { printf "%b\n" "${GREEN}✓${RESET} $*"; }
warn()  { printf "%b\n" "${YELLOW}⚠ $*${RESET}" >&2; }
error() { printf "%b\n" "${RED}✖ $*${RESET}" >&2; exit 1; }
step()  { printf "%b\n" "${CYAN}${BOLD}── 步骤 $1/${STEP_TOTAL} · $2 ──${RESET}"; }

usage() {
  cat <<'USAGE_EOF'
用法:
  bash script/setup-device.sh                                   # 交互问答模式
  bash script/setup-device.sh --config <.config路径> [选项...]  # 命令行模式

选项:
  --config <path>   本地 .config 文件路径 (必要项, 交互模式循环询问直到有效)
  --chip <name>     芯片型号 (如 mt7981/mt7987); 缺省取历史配置最近值
  --branch <name>   源码分支; 仅在非默认分支时写入 device-branch.txt
  --diy <true|false> 该设备 DIY 开关; 缺省/true 均不写控制文件 (默认 true), 仅 false 写入
  --yes             跳过所有交互确认, 自动采用推断值/默认值 (非交互友好)
  --dry-run         只打印将执行的操作, 不修改任何文件
  --help            显示本帮助

交互模式: 全部配置均可逐项设置; 非必要项留空即用默认值,
          连续 3 次无效输入自动采用默认值并给出提醒。
USAGE_EOF
  exit 0
}

confirm_step() { # $1=描述; --yes 或 dry-run 时自动通过
  [ "${YES:-0}" = "1" ] && return 0
  [ "${DRY_RUN:-0}" = "1" ] && return 0
  if [ -t 0 ]; then
    printf "%s [Y/n] " "$1"
    read -r ans
    case "$ans" in ""|y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
  fi
  return 0
}

# 交互输入: 空输入取默认值; 无效输入最多重试 3 次, 之后取默认值并提醒
# $1=提示 $2=默认值 $3=校验正则 $4=值描述; 输出结果到 stdout
ask_value() {
  local prompt="$1" default="$2" pattern="$3" desc="$4"
  local attempt=0 ans=""
  while [ "$attempt" -lt 3 ]; do
    if [ -n "$default" ]; then
      printf "%b" "${CYAN}${prompt}${RESET} ${DIM}[${YELLOW}${default}${RESET}${DIM}]${RESET}: " >&2
    else
      printf "%b" "${CYAN}${prompt}${RESET}: " >&2
    fi
    read -r ans || { echo ""; ans=""; }
    if [ -z "$ans" ]; then
      if [ -n "$default" ]; then
        printf "%s\n" "$default"
        return 0
      fi
      warn "未输入, 请重试 ($desc)"
      attempt=$((attempt + 1))
      continue
    fi
    if [[ "$ans" =~ $pattern ]]; then
      printf "%s\n" "$ans"
      return 0
    fi
    warn "无效输入: $ans ($desc)"
    ans=""
    attempt=$((attempt + 1))
  done
  warn "输入错误超过 3 次, 采用默认值: ${default:-<无默认值>}"
  printf "%s\n" "$default"
  return 0
}

# ===== 确定仓库根目录 =====
if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE/config" ]; then
  ROOT_DIR="$GITHUB_WORKSPACE"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT_DIR="${SCRIPT_DIR}/.."
fi
CONFIG_DIR="$ROOT_DIR/config/immortalwrt-mt798x"
ENABLE_FILE="$ROOT_DIR/config/immortalwrt-mt798x-enable-configs.txt"
BRANCH_FILE="$ROOT_DIR/config/immortalwrt-device-branch.txt"
DEFAULT_BRANCH_FILE="$ROOT_DIR/config/immortalwrt-default-branch.txt"
DIY_FILE="$ROOT_DIR/config/immortalwrt-diy-control.txt"

# ===== 参数解析 =====
CONFIG_PATH=""
CHIP=""
CHIP_FROM_ARG=0
BRANCH=""
BRANCH_FROM_ARG=0
DIY=""
DIY_FROM_ARG=0
YES=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --chip)   CHIP="$2"; CHIP_FROM_ARG=1; shift 2 ;;
    --branch) BRANCH="$2"; BRANCH_FROM_ARG=1; shift 2 ;;
    --diy)    DIY="$2"; DIY_FROM_ARG=1; shift 2 ;;
    --yes)    YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage ;;
    *) error "未知参数: $1 (--help 查看用法)" ;;
  esac
done
[ -z "$DIY" ] || [ "$DIY" = "true" ] || [ "$DIY" = "false" ] || error "--diy 仅接受 true/false"
[ -z "$BRANCH" ] || [[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || error "--branch 含非法字符: $BRANCH"
[ -z "$CHIP" ] || [[ "$CHIP" =~ ^[a-z0-9]+$ ]] || error "--chip 含非法字符: $CHIP"

[ "$DRY_RUN" = "1" ] && { printf "%b\n" "${YELLOW}${BOLD}── dry-run 预览模式, 不会修改任何文件 ──${RESET}"; }

# ===== 收集 .config (必要项: 无默认值, 交互模式循环询问直到有效) =====
step 1 "读取配置"
if [ -z "$CONFIG_PATH" ]; then
  if [ ! -t 0 ]; then
    error "非交互模式必须指定 --config"
  fi
  while :; do
    printf "%b" "${CYAN}本地 .config 文件路径${RESET}: " >&2
    read -r CONFIG_PATH || { echo ""; CONFIG_PATH=""; }
    if [ -f "${CONFIG_PATH:-}" ]; then break; fi
    warn "文件不存在: ${CONFIG_PATH:-<空>}"
    CONFIG_PATH=""
  done
fi
[ -n "$CONFIG_PATH" ] || error "未提供 .config 路径"
[ -f "$CONFIG_PATH" ] || error "配置文件不存在: $CONFIG_PATH"

# ===== 从 .config 提取设备名 =====
# 匹配 CONFIG_TARGET_<target>_DEVICE_<device>=y, 排除 target/subtarget 级条目
DEVICE_MATCHES="$(grep -E "^CONFIG_TARGET_.+_DEVICE_.+=y$" "$CONFIG_PATH" | sed -E "s/.*_DEVICE_(.*)=y/\1/")"
[ -n "$DEVICE_MATCHES" ] || error "未在 $CONFIG_PATH 中找到 CONFIG_TARGET_..._DEVICE_<name>=y 条目"
DEVICE_COUNT="$(printf "%s\n" "$DEVICE_MATCHES" | sed "/^$/d" | wc -l)"
if [ "$DEVICE_COUNT" -gt 1 ]; then
  echo "✖ 检测到多个设备选择, 请清理 .config 后重试:" >&2
  printf "%s\n" "$DEVICE_MATCHES" >&2
  exit 1
fi
DEVICE="$(printf "%s\n" "$DEVICE_MATCHES" | sed "/^$/d" | head -1)"
case "$DEVICE" in *[!a-z0-9_-]*) error "设备名含非法字符: $DEVICE" ;; esac
ok "设备名: $DEVICE"

# ===== 读取默认分支 (非必要项 branch 的默认值) =====
DEFAULT_BRANCH="$(head -1 "$DEFAULT_BRANCH_FILE" 2>/dev/null | tr -d "[:space:]")"

# ===== 芯片/分支/DIY (非必要项: 默认值兜底, 交互可覆盖) =====
step 2 "确定芯片与编译参数"
if [ -z "$CHIP" ]; then
  LATEST_TS=""
  while IFS= read -r -d "" file; do
    filename="$(basename "$file")"
    if [[ "$filename" =~ ^immortalwrt-actions-([a-z0-9]+)-${DEVICE}-([0-9]{14})\.config$ ]]; then
      if [ -z "$LATEST_TS" ] || [ "${BASH_REMATCH[2]}" \> "$LATEST_TS" ]; then
        CHIP="${BASH_REMATCH[1]}"
        LATEST_TS="${BASH_REMATCH[2]}"
      fi
    fi
  done < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name "immortalwrt-actions-*-${DEVICE}-*.config" -print0 2>/dev/null || true)
fi
if [ "$CHIP_FROM_ARG" = "0" ] && [ -t 0 ] && [ "$YES" != "1" ]; then
  CHIP="$(ask_value "芯片型号 (如 mt7981/mt7987)" "${CHIP:-}" "^[a-z0-9]+$" "芯片型号仅含小写字母与数字")"
fi
[ -n "$CHIP" ] || error "无法确定芯片型号, 请用 --chip 指定 (如 mt7981/mt7987)"
case "$CHIP" in *[!a-z0-9]*) error "芯片型号含非法字符: $CHIP" ;; esac
info "芯片型号: $CHIP"

if [ "$BRANCH_FROM_ARG" = "0" ] && [ -t 0 ] && [ "$YES" != "1" ]; then
  BRANCH="$(ask_value "源码分支 (留空=默认分支)" "${BRANCH:-${DEFAULT_BRANCH:-}}" "^[A-Za-z0-9._/-]+$" "分支名仅含字母数字与 ._/- 字符")"
fi
[ -z "$BRANCH" ] || [[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || error "分支含非法字符: $BRANCH"
if [ "$DIY_FROM_ARG" = "0" ] && [ -t 0 ] && [ "$YES" != "1" ]; then
  DIY="$(ask_value "DIY 脚本开关 (true/false, 留空=默认 true)" "${DIY:-true}" "^(true|false)$" "仅接受 true 或 false")"
fi
[ -z "$DIY" ] || [ "$DIY" = "true" ] || [ "$DIY" = "false" ] || error "DIY 仅接受 true/false: $DIY"

# ===== 目标文件名与复制 (内容级防重) =====
step 3 "复制配置文件"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
TARGET_NAME="immortalwrt-actions-${CHIP}-${DEVICE}-${TIMESTAMP}.config"
TARGET_PATH="$CONFIG_DIR/$TARGET_NAME"
EFFECTIVE_CONFIG="$TARGET_NAME"

# 找出该设备时间戳最新的现有配置
LATEST_EXISTING=""
LATEST_EXISTING_TS=""
while IFS= read -r -d "" file; do
  filename="$(basename "$file")"
  if [[ "$filename" =~ ^immortalwrt-actions-([a-z0-9]+)-${DEVICE}-([0-9]{14})\.config$ ]]; then
    if [ -z "$LATEST_EXISTING_TS" ] || [ "${BASH_REMATCH[2]}" \> "$LATEST_EXISTING_TS" ]; then
      LATEST_EXISTING="$file"
      LATEST_EXISTING_TS="${BASH_REMATCH[2]}"
    fi
  fi
done < <(find "$CONFIG_DIR" -maxdepth 1 -type f -name "immortalwrt-actions-*-${DEVICE}-*.config" -print0 2>/dev/null || true)

if [ -n "$LATEST_EXISTING" ] && cmp -s "$CONFIG_PATH" "$LATEST_EXISTING"; then
  # 内容与该设备最新配置一致 → 跳过复制, 不产生冗余副本
  EFFECTIVE_CONFIG="$(basename "$LATEST_EXISTING")"
  ok "配置内容与最新配置一致, 无需新增副本: $EFFECTIVE_CONFIG"
elif [ -f "$TARGET_PATH" ]; then
  info "目标配置已存在, 跳过复制: $TARGET_NAME"
else
  confirm_step "复制 $CONFIG_PATH → $TARGET_NAME?" || error "已取消"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] cp $CONFIG_PATH $TARGET_PATH"
  else
    mkdir -p "$CONFIG_DIR"
    cp "$CONFIG_PATH" "$TARGET_PATH"
    ok "已复制: $TARGET_NAME"
  fi
fi

# ===== upsert 辅助: 按键 (首列) 更新或追加文本文件 (删旧行后追加, 避免 sed 转义问题) =====
upsert_file() { # $1=文件 $2=键 $3=完整行 $4=描述
  local file="$1" key="$2" line="$3" desc="$4"
  if [ ! -f "$file" ]; then
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] 创建 $file: $line"; return 0; fi
    printf "%s\n" "$line" > "$file"
    ok "已创建$desc: $line"
    return 0
  fi
  if grep -qE "^${key}([[:space:]].*)?$" "$file"; then
    old="$(grep -E "^${key}([[:space:]].*)?$" "$file" | head -1)"
    if [ "$old" = "$line" ]; then
      info "$desc已是最新: $line"
      return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] $desc更新: $old → $line"; return 0; fi
    sed -i "/^${key}[[:space:]]/d; /^${key}$/d" "$file"
    printf "%s\n" "$line" >> "$file"
    ok "$desc已更新: $old → $line"
  else
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] $desc追加: $line"; return 0; fi
    printf "%s\n" "$line" >> "$file"
    ok "$desc已追加: $line"
  fi
}

# 移除指定键的所有行 (恢复默认行为); 键不存在则静默跳过
remove_file_key() { # $1=文件 $2=键 $3=描述
  local file="$1" key="$2" desc="$3"
  if [ -f "$file" ] && grep -qE "^${key}([[:space:]].*)?$" "$file"; then
    if [ "$DRY_RUN" = "1" ]; then echo "[dry-run] 移除$desc显式设置: $key"; return 0; fi
    sed -i "/^${key}[[:space:]]/d; /^${key}$/d" "$file"
    ok "已移除$desc显式设置 (恢复默认): $key"
  else
    info "$desc保持默认 (无显式设置): $key"
  fi
}

# ===== 更新仓库配置文件 =====
step 4 "更新仓库配置"
# 1) enable-configs
if grep -qxF "$DEVICE" "$ENABLE_FILE" 2>/dev/null; then
  info "设备已在启用列表: $DEVICE"
else
  confirm_step "将 $DEVICE 加入启用设备列表?" || error "已取消"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] 追加 $DEVICE 到 $ENABLE_FILE"
  else
    printf "%s\n" "$DEVICE" >> "$ENABLE_FILE"
    ok "已加入启用列表: $DEVICE"
  fi
fi

# 2) device-branch (仅非默认分支)
if [ -n "$BRANCH" ] && [ "$BRANCH" != "${DEFAULT_BRANCH:-}" ]; then
  confirm_step "写入分支映射: $DEVICE → $BRANCH?" || error "已取消"
  upsert_file "$BRANCH_FILE" "$DEVICE" "$DEVICE $BRANCH" "分支映射"
elif [ -n "$BRANCH" ]; then
  info "分支 $BRANCH 与默认分支一致, 无需写入分支文件"
fi

# 3) diy-control (仓库约定: 未列出=默认 true, 仅 false 才需写入)
if [ "$DIY" = "false" ]; then
  confirm_step "写入 DIY 开关: $DEVICE → false?" || error "已取消"
  upsert_file "$DIY_FILE" "$DEVICE" "$DEVICE false" "DIY 开关"
elif [ "$DIY" = "true" ]; then
  # 默认即 true: 不写行, 并清理可能存在的旧显式设置
  remove_file_key "$DIY_FILE" "$DEVICE" "DIY 开关"
else
  info "DIY: 未指定, 保持默认 true (不写控制文件)"
fi

# ===== 汇总 =====
echo ""
step 5 "汇总"
printf "%b\n" "${BLUE}──────────────── 配置总览 ────────────────${RESET}"
printf "  %-6s %s\n" "设备" "$DEVICE"
printf "  %-6s %s\n" "芯片" "$CHIP"
printf "  %-6s %s\n" "配置" "$EFFECTIVE_CONFIG"
if [ -n "$BRANCH" ]; then
  printf "  %-6s %s\n" "分支" "$BRANCH"
else
  printf "  %-6s %s (默认)\n" "分支" "${DEFAULT_BRANCH:-?}"
fi
if [ "$DIY" = "false" ]; then
  printf "  %-6s %s\n" "DIY" "false (显式禁用)"
else
  printf "  %-6s %s\n" "DIY" "true (默认, 未写控制文件)"
fi
printf "%b\n" "${BLUE}──────────────────────────────────────────${RESET}"
[ "$DRY_RUN" = "1" ] && printf "%b\n" "${YELLOW}(dry-run 模式, 未做任何修改)${RESET}"
printf "%b\n" "${YELLOW}${BOLD}下一步: 在 Actions 页面手动触发 Build-immortalwrt-single.yml 测试该设备${RESET}"
exit 0
