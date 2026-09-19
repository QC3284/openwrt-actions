#!/usr/bin/env bash
# File: selftest-validate.sh — Validate.yml 配置校验步骤的行为自测
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions
#
# 为什么需要它: "启用设备↔配置文件" 这类校验一旦被改坏, 表现是"该红却绿" ——
# 推送全绿、定时编译静默跳过设备、几个月后才发现。人肉回归已被证明会看走眼
# (改完只看 CI 绿不绿, 无法区分"护栏生效"与"护栏被摘掉")。
#
# 做法: 直接从 .github/workflows/Validate.yml 抽取该步骤的 run 脚本原文,
# 逐字节复用 CI 执行的那份代码 (不用副本, 不做二次实现), 在临时镜像目录上
# 跑场景矩阵, 断言退出码与 ❌ 消息数量。
#
# 用法: bash script/selftest-validate.sh [--repo <仓库根目录>] [--keep]
#   退出码: 0 = 全部场景符合预期; 1 = 有场景不符 (CI 依据此项失败)

set -uo pipefail

REPO_DIR=""
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --help|-h) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1 (--help 查看用法)" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${REPO_DIR:="$SCRIPT_DIR/.."}"

CONFIG_SRC="$REPO_DIR/config"
TMP="$(mktemp -d)"
WD="$TMP/work"
mkdir -p "$WD"
cleanup() { [ "$KEEP" = "1" ] || rm -rf "$TMP"; }
trap cleanup EXIT

PASSED=0
FAILED=0

# 抽取 Validate.yml 中某个步骤的 run 脚本原文 (按步骤名定位, 去缩进)
extract_step() { # $1=仓库根 $2=步骤名子串 $3=输出文件
  python3 - "$1" "$2" "$3" <<'PY'
import sys

root, needle, out = sys.argv[1], sys.argv[2], sys.argv[3]
path = root + "/.github/workflows/Validate.yml"
lines = open(path, encoding="utf-8").read().split("\n")

start = None
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("- name:") and needle in stripped:
        start = i
        break
if start is None:
    sys.exit("抽取失败: 未在 Validate.yml 找到步骤 [%s]" % needle)

run_at = None
for j in range(start + 1, len(lines)):
    if lines[j].strip().startswith("- name:"):
        break
    if lines[j].strip() == "run: |":
        run_at = j
        break
if run_at is None:
    sys.exit("抽取失败: 步骤 [%s] 里没有 run: | 块" % needle)

body = []
for line in lines[run_at + 1:]:
    if line.strip().startswith("- name:"):
        break
    if line.strip() and not line.startswith(" " * 10):
        break
    body.append(line[10:] if line.startswith(" " * 10) else "")
while body and not body[-1].strip():
    body.pop()
if not body:
    sys.exit("抽取失败: 步骤 [%s] 的 run 块为空" % needle)

open(out, "w", encoding="utf-8").write("\n".join(body) + "\n")
print("  抽取 %s → %d 行" % (needle, len(body)))
PY
}

# 在镜像目录里执行抽取出的步骤脚本 (脚本用相对路径, 故 cd 进镜像)
run_step() { # $1=抽取出的脚本
  ( cd "$WD" && bash -c 'set -e; . "$1"' _ "$1" ) > "$TMP/out" 2>&1
  LAST_EXIT=$?
}

# 组装镜像: 复制仓库全部 config/ 后, 由调用方按场景破坏
build_mirror() {
  rm -rf "$WD"
  mkdir -p "$WD"
  cp -r "$CONFIG_SRC" "$WD/config"
}
mut() { # $1=类型 $2=设备名 (用数组接 glob, 避免引号包住通配符使其不展开)
  local files=("$WD/config/immortalwrt-mt798x/"immortalwrt-actions-*-"$2"-*.config)
  if [ ! -e "${files[0]}" ]; then echo "  脚手架错误: 未匹配到 $2 的配置文件" >&2; return 1; fi
  case "$1" in
    none) ;;
    # rename: 破坏命名规则 → 该设备"查无配置", 由本次新增的护栏单独捕获
    rename) mv "${files[0]}" "$WD/config/immortalwrt-mt798x/immortalwrt-actions-mt7981-$2-broken.config" ;;
    # rename_bad_name: 改名后仍符合 <芯片>-<设备>-<时间戳> 规则但设备段不同
    # → 同时触发"启用设备无配置"与既有的"文件名设备与 CONFIG_TARGET_DEVICE 不一致"
    rename_bad_name)
      local new_dev="${2//_/-}"
      mv "${files[0]}" "$WD/config/immortalwrt-mt798x/immortalwrt-actions-mt7981-${new_dev}-20260710202710.config" ;;
    rm)     rm -f "${files[@]}" ;;
    tamper) sed -i "s/^CONFIG_TARGET_mediatek_filogic_DEVICE_$2=y$/# 篡改/" "${files[@]}" ;;
  esac
}

device_config_count() { find "$WD/config/immortalwrt-mt798x" -name 'immortalwrt-actions-*.config' | wc -l; }

scenario() { # $1=描述 $2=期望exit $3=期望❌数 $4=输出正则
  local desc="$1" want_exit="$2" want_err="$3" want_msg="$4" got_err=0
  local got_exit="$LAST_EXIT"
  got_err=$(grep -aE '❌' "$TMP/out" | wc -l | tr -d ' ')
  local ok=1
  [ "$got_exit" = "$want_exit" ] || ok=0
  [ "$want_err" = "-" ] || [ "$got_err" = "$want_err" ] || ok=0
  if [ -n "$want_msg" ] && ! grep -aqE "$want_msg" "$TMP/out"; then ok=0; fi
  if [ "$ok" = "1" ]; then
    PASSED=$((PASSED + 1))
    printf '  ✅ %-46s exit=%s ❌=%s\n' "$desc" "$got_exit" "$got_err"
  else
    FAILED=$((FAILED + 1))
    printf '  ❌ %-46s 期望 exit=%s ❌=%s 正则[%s], 实得 exit=%s ❌=%s\n' \
      "$desc" "$want_exit" "$want_err" "$want_msg" "$got_exit" "$got_err"
    sed -n 's/^/       | /p' "$TMP/out" | head -12
  fi
}

echo "=== Validate.yml 配置校验自测 ==="
echo "仓库: $REPO_DIR"
extract_step "$REPO_DIR" "校验配置文件内容格式" "$TMP/content.sh" || exit 1
extract_step "$REPO_DIR" "校验配置文件 " "$TMP/presence.sh" || exit 1
# 哨兵: 抽取到的文本里必须留有设备↔配置判定。不在此处直接退出 ——
# 若直接退出, "护栏被摘掉"时就看不到场景矩阵的结论了, 也就无法证明矩阵本身
# 是否足够敏感 (负向验证会被哨兵短路而失去意义); 改为记一个待判场景。
SENTINEL_OK=1
grep -q '每个启用设备均有配置文件' "$TMP/content.sh" || SENTINEL_OK=0
if [ "$SENTINEL_OK" = "0" ]; then
  echo "  ⚠️ 抽取到的内容步骤里没有设备↔配置判定 (步骤名或结构可能已被改动)"
fi

echo
echo "--- 内容格式步骤 (Validate Config Content) ---"
build_mirror; run_step "$TMP/content.sh"
scenario "仓库现状 (3 台设备)" 0 0 '中每个启用设备均有配置文件'

build_mirror; printf '# 全部注释\n\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "启用列表为空" 1 1 '未包含任何启用的设备'

build_mirror; printf 'glinet_gl-mt3000\nfoo_bar-baz\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "启用未知设备" 1 1 '启用设备 \[foo_bar-baz\].*没有配置文件'

build_mirror; printf 'glinet_gl-mt3000\n../outside/x\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "路径穿越 (防绕过)" 1 1 '非法设备名.*\.\./outside/x'

build_mirror; printf 'glinet_gl-mt3000\nGl-Mt3000\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "大写设备名" 1 1 '非法设备名.*Gl-Mt3000'

build_mirror; printf 'glinet_gl-mt3000   # 行尾注释\n  konka_komi-a31\nglinet_gl-mt3600be\t# 制表符\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "行尾注释/首尾空白/制表符" 0 0 '中每个启用设备均有配置文件'

build_mirror; printf 'glinet_gl-mt3000\nglinet_gl-mt3000\nkonka_komi-a31\nglinet_gl-mt3600be\n' > "$WD/config/immortalwrt-mt798x-enable-configs.txt"; run_step "$TMP/content.sh"
scenario "重复行" 0 0 '中每个启用设备均有配置文件'

build_mirror; mut rename glinet_gl-mt3000; run_step "$TMP/content.sh"
scenario "启用设备查无配置 (仅新护栏可捕获)" 1 1 '启用设备 \[glinet_gl-mt3000\].*没有配置文件'

build_mirror; mut rename_bad_name konka_komi-a31; run_step "$TMP/content.sh"
scenario "配置改名致双判定同时触发" 1 2 '文件名设备 \[konka-komi-a31\] 与 CONFIG_TARGET_DEVICE 不一致'

build_mirror; rm -f "$WD/config/immortalwrt-mt798x/"*.config; run_step "$TMP/content.sh"
scenario "设备目录为空" 1 3 '没有配置文件'

build_mirror; mut tamper glinet_gl-mt3000; run_step "$TMP/content.sh"
scenario "篡改 CONFIG_TARGET_DEVICE (既有回归)" 1 1 '文件名设备 \[glinet_gl-mt3000\] 与 CONFIG_TARGET_DEVICE 不一致'

if [ "$SENTINEL_OK" = "1" ]; then
  PASSED=$((PASSED + 1))
  printf '  ✅ %-46s exit=- ❌=-\n' "内容步骤含设备↔配置判定 (哨兵)"
else
  FAILED=$((FAILED + 1))
  printf '  ❌ %-46s 步骤内已找不到设备↔配置判定文本\n' "内容步骤含设备↔配置判定 (哨兵)"
fi

# 不变量: 失败草稿 Release 的保留额度必须 <= 1
# 该动作只删除"不匹配保留关键字且超出保留额度"的 Release —— 曾把矩阵工作流
# 设为 5, 而历史失败草稿常年只有 2 个, 于是每次运行都成功(绿)但一个也没删。
# 单设备工作流此前压根没有清理步骤, 失败草稿只增不减。
check_keep_latest() { # $1=workflow 文件 $2=期望 <= 的上限
  local file="$1" limit="$2" value
  # 按缩进逐行扫描, 不靠跨行正则: 正则版曾越过步骤边界读到下一个步骤的
  # keep_latest=20 (假红), 且多层转义极易出错。扫描规则:
  # 以 "      - name:" 开头算一个步骤, 找到名字含 failed 的那个, 在其内部取值。
  value=$(python3 - "$file" <<'PY'
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
step, in_step, value = "", False, ""
for line in lines:
    if line.startswith("      - name:"):
        if step and "failed" in step.lower() and value:
            break
        step, in_step, value = line.split("- name:", 1)[1].strip(), True, ""
    elif in_step and line.lstrip().startswith("releases_keep_latest:"):
        value = line.split("releases_keep_latest:", 1)[1].strip()
# 只认"失败草稿清理步骤"内的取值。刻意不做"找不到就取首处"的回退:
# 那样一旦该步骤被改名或删除, 会读到正式 Release 清理的 keep_latest=20
# 并判为通过 —— 能被骗过的护栏比没有护栏更糟。
if value and "failed" in step.lower():
    print(value)
PY
)
  if [ -z "$value" ]; then
    FAILED=$((FAILED + 1))
    printf '  ❌ %-46s %s 内没有失败草稿清理步骤\n' "失败草稿保留额度 (不变量)" "$(basename "$file")"
    return
  fi
  if [ "$value" -le "$limit" ]; then
    PASSED=$((PASSED + 1))
    printf '  ✅ %-46s %s: keep_latest=%s (≤%s)\n' "失败草稿保留额度 (不变量)" "$(basename "$file")" "$value" "$limit"
  else
    FAILED=$((FAILED + 1))
    printf '  ❌ %-46s %s: keep_latest=%s > %s → 该清理永不生效\n' \
      "失败草稿保留额度 (不变量)" "$(basename "$file")" "$value" "$limit"
  fi
}

echo
echo "--- 失败草稿 Release 清理不变量 ---"
check_keep_latest "$REPO_DIR/.github/workflows/Build-immortalwrt.yml" 1
check_keep_latest "$REPO_DIR/.github/workflows/Build-immortalwrt-single.yml" 1

echo
echo "--- 文件存在性步骤 (Validate Config Files) ---"
build_mirror; run_step "$TMP/presence.sh"
scenario "仓库现状" 0 0 'config/immortalwrt-url.txt'

build_mirror; mv "$WD/config/immortalwrt-device-branch.txt" "$WD/config/immortalwrt-device-branch.txt.bak"; run_step "$TMP/presence.sh"
scenario "可选文件缺失 (仅告警)" 0 0 '缺少可选文件'

build_mirror; mv "$WD/config/immortalwrt-url.txt" "$WD/config/immortalwrt-url.txt.bak"; run_step "$TMP/presence.sh"
scenario "必需文件缺失" 1 1 '缺少必需文件'

echo
if [ "$FAILED" -eq 0 ]; then
  echo "全部通过: $PASSED/$PASSED 项"
  exit 0
fi
echo "自测失败: $PASSED 项通过, $FAILED 项不符"
exit 1
