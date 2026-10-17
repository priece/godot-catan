#!/usr/bin/env bash
# ============================================================
# 竖屏启动脚本（macOS / Linux 版，对应仓库里的 portrait_start.bat）
#
# 用法：
#   ./portrait_start.sh              竖屏开一局（窗口 720x1280）
#   ./portrait_start.sh -f           全屏（只适合真正竖着的屏幕 / 竖屏模拟器）
#   ./portrait_start.sh -- auto      AI 接管人类座位，自动演示
#   PORTRAIT_RES=1080x1920 ./portrait_start.sh    换一个竖屏分辨率
#
# 为什么给分辨率就等于竖屏：BoardView._ready 按**窗口物理尺寸**判宽<高，
# 命中就锁 portrait，内容基准从 1280x720 切到 720x1280（ui/layout.gd），
# 即"上棋盘 / 下信息区"。所以本脚本唯一的关键动作就是传 --resolution。
#
# 屏幕不够高时窗口会被系统压矮（实测 720x1280 → 窗口 720x1061、视口 868x1280），
# 仍是竖屏、布局照旧；只是此时窗口坐标 ≠ 视口坐标（系数 0.83），
# 手点没问题，写脚本推合成鼠标事件才要换算（AGENTS.md trap 18）。
# ============================================================
set -u

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
RES="${PORTRAIT_RES:-720x1280}"

# ---- 找 Godot 可执行文件：环境变量 > 仓库内 > /Applications > PATH ----
GODOT_EXE=""
for cand in \
	"${GODOT_BIN:-}" \
	"${GODOT:-}" \
	"$ROOT_DIR/Godot.app/Contents/MacOS/Godot" \
	"/Applications/Godot.app/Contents/MacOS/Godot" \
	"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
	"$(command -v godot 2>/dev/null)" \
	"$(command -v godot4 2>/dev/null)"
do
	[ -n "$cand" ] || continue
	if [ -x "$cand" ]; then
		GODOT_EXE="$cand"
		break
	fi
done

if [ -z "$GODOT_EXE" ]; then
	echo "[portrait_start] 找不到 Godot 可执行文件。找过这些位置：" >&2
	echo "  \$GODOT_BIN / \$GODOT 环境变量" >&2
	echo "  $ROOT_DIR/Godot.app/Contents/MacOS/Godot" >&2
	echo "  /Applications/Godot.app/Contents/MacOS/Godot" >&2
	echo "  \$HOME/Applications/Godot.app/Contents/MacOS/Godot" >&2
	echo "  PATH 里的 godot / godot4" >&2
	echo "可以直接指定：GODOT_BIN=/路径/到/Godot ./portrait_start.sh" >&2
	exit 1
fi

# ---- 首次运行（.godot 不存在）先导入，否则新加的 class_name 全是未定义 ----
if [ ! -d "$ROOT_DIR/.godot" ]; then
	echo "[portrait_start] 未发现导入缓存，先跑一次 --import（只需一次，稍等）"
	"$GODOT_EXE" --headless --path "$ROOT_DIR" --import >/dev/null 2>&1
fi

echo "[portrait_start] Godot   : $GODOT_EXE"
echo "[portrait_start] 项目    : $ROOT_DIR"
# ⚠️ 变量后面紧跟中文必须写 ${RES}：bash 会把全角字符的字节当成变量名的一部分
echo "[portrait_start] 分辨率  : ${RES}（宽<高 → 竖屏布局）"

exec "$GODOT_EXE" --path "$ROOT_DIR" --resolution "$RES" "$@"
