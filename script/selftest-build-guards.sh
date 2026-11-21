#!/usr/bin/env bash
# File: selftest-build-guards.sh — Build 工作流「静默失败护栏」的行为自测
# Copyright (c) 2024-2026 QC3284. GPL-3.0-only.
# https://github.com/QC3284/openwrt-actions
#
# 为什么需要它: 这类护栏的失效方式恰恰是"该红却绿" —— 空矩阵或空产物时整次
# 运行 0 秒结束且显示成功, 人肉回归只会看到绿灯。这里直接从两个 Build 工作流
# 抽取护栏步骤的 run 脚本原文 (逐字节复用 CI 执行的代码), 在临时目录上跑场景
# 矩阵并断言退出码与错误消息; 同时用哨兵断言关键错误文案仍在脚本里, 防止
# 护栏被删/改名后场景矩阵"无步骤可跑"而假绿。
#
# 用法: bash script/selftest-build-guards.sh [--repo <仓库根目录>] [--keep]
#   退出码: 0 = 全部场景符合预期; 1 = 有场景不符 (CI 依据此项失败)

set -uo pipefail

REPO_DIR=""
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --help|-h) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1 (--help 查看用法)" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${REPO_DIR:="$SCRIPT_DIR/.."}"

WF_MATRIX="$REPO_DIR/.github/workflows/Build-immortalwrt.yml"
WF_SINGLE="$REPO_DIR/.github/workflows/Build-immortalwrt-single.yml"
DIY2="$REPO_DIR/script/immortalwrt-actions-diy2.sh"

TMP="$(mktemp -d)"
WD="$TMP/work"
mkdir -p "$WD"
cleanup() { [ "$KEEP" = "1" ] || rm -rf "$TMP"; }
trap cleanup EXIT

PASSED=0
FAILED=0
LAST_RC=0
LAST_LOG="$TMP/last.log"

# 抽取工作流中某个步骤的 run 脚本原文 (按步骤名定位, 去掉 YAML 缩进)
extract_run() { # $1=workflow 文件 $2=步骤名子串 $3=输出文件
  python3 - "$1" "$2" "$3" <<'PY'
import sys

path, needle, out = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().split("\n")

start = None
for i, line in enumerate(lines):
    if line.strip().startswith("- name:") and needle in line:
        start = i
        break
if start is None:
    sys.exit("抽取失败: 未在 %s 找到步骤 [%s]" % (path, needle))

run_at = None
for j in range(start + 1, len(lines)):
    stripped = lines[j].strip()
    if stripped.startswith("- name:"):
        break
    if stripped == "run: |":
        run_at = j
        break
if run_at is None:
    sys.exit("抽取失败: 步骤 [%s] 里没有 run: | 块" % needle)

indent = None
body = []
for k in range(run_at + 1, len(lines)):
    line = lines[k]
    if line.strip().startswith("- name:"):
        break
    if indent is None:
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
    if line.strip():
        if len(line) - len(line.lstrip(" ")) < indent:
            break
        body.append(line[indent:])
    else:
        body.append("")
while body and not body[-1].strip():
    body.pop()
if not body:
    sys.exit("抽取失败: 步骤 [%s] 的 run 块为空" % needle)
open(out, "w", encoding="utf-8").write("\n".join(body) + "\n")
PY
}

# 把抽取出的脚本中的 ${{ github.workspace }} 换成沙盒目录
render_workspace() { # $1=源脚本 $2=仓库工作区目录 $3=输出文件
  python3 - "$1" "$2" "$3" <<'PY'
import sys

src, ws, out = sys.argv[1], sys.argv[2], sys.argv[3]
tok = "$" + "{{ github.workspace }}"
text = open(src, encoding="utf-8").read()
if tok not in text:
    sys.exit("渲染失败: %s 中没有 %s 占位符" % (src, tok))
open(out, "w", encoding="utf-8").write(text.replace(tok, ws))
PY
}

# 把抽取出的校验脚本中的矩阵占位符换成固定矩阵 JSON
render_matrix_json() { # $1=源脚本 $2=矩阵 JSON $3=输出文件
  python3 - "$1" "$2" "$3" <<'PY'
import sys

src, matrix, out = sys.argv[1], sys.argv[2], sys.argv[3]
tok = "$" + "{{ needs.prepare.outputs.matrix }}"
text = open(src, encoding="utf-8").read()
if tok not in text:
    sys.exit("渲染失败: %s 中没有矩阵占位符" % src)
open(out, "w", encoding="utf-8").write(text.replace(tok, matrix))
PY
}

require_text() { # $1=文件或脚本 $2=必须出现的关键字 $3=说明
  if grep -qF "$2" "$1"; then
    PASSED=$((PASSED + 1))
    printf '  ✅ %-44s 哨兵命中: %s\n' "$3" "$2"
  else
    FAILED=$((FAILED + 1))
    printf '  ❌ %-44s 哨兵缺失: %s (%s)\n' "$3" "$2" "$1"
  fi
}

run_step() { # $1=工作目录 $2=脚本
  ( cd "$1" && bash "$2" ) >"$LAST_LOG" 2>&1
  LAST_RC=$?
}

scenario() { # $1=场景名 $2=期望退出码 $3=日志中必须出现的正则(可空)
  local name="$1" want="$2" pattern="${3:-}" ok=1
  [ "$LAST_RC" -eq "$want" ] || ok=0
  if [ -n "$pattern" ] && ! grep -qE "$pattern" "$LAST_LOG"; then
    ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    PASSED=$((PASSED + 1))
    printf '  ✅ %-44s rc=%s\n' "$name" "$LAST_RC"
  else
    FAILED=$((FAILED + 1))
    printf '  ❌ %-44s rc=%s (期望 %s)\n' "$name" "$LAST_RC" "$want"
    sed 's/^/      | /' "$LAST_LOG" | tail -n 6
  fi
}

echo "--- 护栏脚本抽取与哨兵 ---"
extract_run "$WF_MATRIX" "生成编译矩阵 (Generate Build Matrix)" "$TMP/matrix.sh" || exit 1
extract_run "$WF_MATRIX" "校验本次运行产物 (Verify Build Artifacts)" "$TMP/verify.sh" || exit 1
echo "  已抽取: matrix.sh / verify.sh"

require_text "$TMP/matrix.sh" "编译矩阵为空" "矩阵空护栏"
require_text "$TMP/matrix.sh" "台启用设备缺少配置" "启用设备缺配置护栏"
require_text "$TMP/verify.sh" "没有任何固件资产" "Release 空资产护栏"
require_text "$TMP/verify.sh" "在本次运行中没有 Release" "Release 缺失护栏"
require_text "$WF_SINGLE" "拒绝发布空 Release" "单设备工作流空产物护栏"
require_text "$DIY2" "拒绝静默回退" "OpenClash 硬失败护栏"
require_text "$REPO_DIR/script/immortalwrt-actions-diy1.sh" "probe_openclash_version" "OpenClash 版本探测"

render_workspace "$TMP/matrix.sh" "$WD" "$TMP/matrix-run.sh" || exit 1

echo
echo "--- 编译矩阵护栏 (Generate Build Matrix) ---"
CONF_DIR="$WD/config/immortalwrt-mt798x"
ENABLE_FILE="$WD/config/immortalwrt-mt798x-enable-configs.txt"
mkdir -p "$CONF_DIR"
make_config() { : > "$CONF_DIR/immortalwrt-actions-$1-$2-20260101010101.config"; }

# 场景 A: 一台启用设备且有合法配置 -> 正常出矩阵
printf 'glinet_gl-mt3000\n' > "$ENABLE_FILE"
make_config mt7981 glinet_gl-mt3000
: > "$TMP/out.txt"
GITHUB_OUTPUT="$TMP/out.txt" run_step "$WD" "$TMP/matrix-run.sh"
if grep -q '"device":"glinet_gl-mt3000"' "$TMP/out.txt"; then LAST_RC=0; else LAST_RC=9; fi
scenario "启用设备有配置 -> 出矩阵" 0

# 场景 B: 部分启用设备无配置 -> 必须失败并点名
printf 'glinet_gl-mt3000\nkonka_komi-a31\n' > "$ENABLE_FILE"
: > "$TMP/out.txt"
GITHUB_OUTPUT="$TMP/out.txt" run_step "$WD" "$TMP/matrix-run.sh"
scenario "部分启用设备缺配置 -> 失败" 1 "konka_komi-a31"

# 场景 C: 所有启用设备都无配置 -> 空矩阵必须失败 (旧行为: 绿色结束)
printf 'ghost_device_one\nghost_device_two\n' > "$ENABLE_FILE"
: > "$TMP/out.txt"
GITHUB_OUTPUT="$TMP/out.txt" run_step "$WD" "$TMP/matrix-run.sh"
scenario "全部启用设备缺配置 -> 失败" 1 "2 台启用设备缺少配置"

# 场景 D: 启用列表为空 -> 失败 (既有护栏回归)
: > "$ENABLE_FILE"
: > "$TMP/out.txt"
GITHUB_OUTPUT="$TMP/out.txt" run_step "$WD" "$TMP/matrix-run.sh"
scenario "启用列表为空 -> 失败" 1 "未包含任何设备"

echo
echo "--- 产物校验护栏 (Verify Build Artifacts) ---"
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
case "${FAKE_SCENARIO:-ok}" in
  ok)
    cat <<'JSON'
[{"tagName":"glinet_gl-mt3000-202601010101-12345","assets":[{"name":"fw-squashfs-sysupgrade.bin"},{"name":"sha256sums.txt"}]},
 {"tagName":"konka_komi-a31-202601010105-12345","assets":[{"name":"fw2-squashfs-sysupgrade.bin"}]}]
JSON
    ;;
  missing)
    cat <<'JSON'
[{"tagName":"glinet_gl-mt3000-202601010101-12345","assets":[{"name":"fw-squashfs-sysupgrade.bin"}]}]
JSON
    ;;
  noasset)
    cat <<'JSON'
[{"tagName":"glinet_gl-mt3000-202601010101-12345","assets":[{"name":"sha256sums.txt"}]},
 {"tagName":"konka_komi-a31-202601010105-12345","assets":[{"name":"bin.202601010105.7z"}]}]
JSON
    ;;
  wrongrun)
    cat <<'JSON'
[{"tagName":"glinet_gl-mt3000-202601010101-99999","assets":[{"name":"fw-squashfs-sysupgrade.bin"}]},
 {"tagName":"konka_komi-a31-202601010105-99999","assets":[{"name":"fw2-squashfs-sysupgrade.bin"}]}]
JSON
    ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

render_matrix_json "$TMP/verify.sh" '[{"device":"glinet_gl-mt3000"},{"device":"konka_komi-a31"}]' "$TMP/verify-run.sh" || exit 1

verify_scenario() { # $1=场景名 $2=gh 场景 $3=期望退出码 $4=期望消息正则
  PATH="$TMP/bin:$PATH" FAKE_SCENARIO="$2" REPO="QC3284/openwrt-actions" RUN_ID=12345 \
    run_step "$WD" "$TMP/verify-run.sh"
  scenario "$1" "$3" "$4"
}

verify_scenario "两台设备 Release 与固件资产齐全 -> 通过" ok 0 "校验通过"
verify_scenario "少一台设备 Release -> 失败" missing 1 "konka_komi-a31.*没有 Release"
verify_scenario "Release 只有日志/校验和 -> 失败" noasset 1 "没有任何固件资产"
verify_scenario "Release 属其他 run_id -> 失败" wrongrun 1 "没有 Release"

echo
echo "--- OpenClash 强制替换 (diy2.sh) ---"
mkdir -p "$TMP/feeds/luci/applications/luci-app-openclash"
cp "$DIY2" "$TMP/diy2.sh"
printf 'PKG_VERSION:=0.46.000\n' > "$TMP/feeds/luci/applications/luci-app-openclash/Makefile"

reset_diy2() {
  rm -rf "$TMP/p-temp"
  mkdir -p "$TMP/p-temp/clash/luci-app-openclash"
  printf 'PKG_VERSION:=0.48.016\n' > "$TMP/p-temp/clash/luci-app-openclash/Makefile"
}

reset_diy2
OPENCLASH_VERSION=0.48.016 run_step "$TMP" "$TMP/diy2.sh"
if grep -qx 'PKG_VERSION:=0.48.016' "$TMP/feeds/luci/applications/luci-app-openclash/Makefile"; then :; else LAST_RC=9; fi
scenario "官方版本覆盖 feeds 旧版 -> 成功" 0 "已强制替换"

reset_diy2
printf 'PKG_VERSION:=0.47.001\n' > "$TMP/p-temp/clash/luci-app-openclash/Makefile"
OPENCLASH_VERSION=0.48.016 run_step "$TMP" "$TMP/diy2.sh"
scenario "替换后版本与探测版本不一致 -> 失败" 1 "不一致"

rm -rf "$TMP/p-temp"
OPENCLASH_VERSION=0.48.016 run_step "$TMP" "$TMP/diy2.sh"
scenario "缺 overlay 源 -> 硬失败(不再警告跳过)" 1 "拒绝静默回退"

echo
if [ "$FAILED" -eq 0 ]; then
  echo "全部通过: $PASSED/$PASSED 项"
  exit 0
fi
echo "自测失败: $PASSED 项通过, $FAILED 项不符"
exit 1
