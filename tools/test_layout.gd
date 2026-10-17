extends SceneTree

## 竖屏布局算式回归（plan-2026.10.15.a §4.3）。
## 跑法：Godot --headless --path . --script res://tools/test_layout.gd
## 退出码 0 = 全通过
##
## 钉三件事：
##   1. 默认态必须是横屏：headless / CI 里没有"窗口"可言，判错朝向会把
##      后续所有桌面断言带崩；content_scale_for 的横屏基准是 (1280,720)。
##   2. 桌面零漂：加了 Layout 分支后，BoardView.board_origin_for 与
##      HUD.content_rect 在 1280×720 + 零安全区下必须逐字节照旧
##      （(510,360) 与 (910,12,356,696)）——这是"桌面逐像素不变"红线的算式层。
##   3. 竖屏自检表（plan-a §4.1 三行：66.12 / 62.96 / 45.3）逐个对上，
##      且棋盘外接尺寸落进棋盘区、信息区不压棋盘、内容不越安全区。

var _pass := 0
var fails := 0

func _initialize() -> void:
	# ---------- 一、默认态 = 横屏 ----------
	_check("默认 is_portrait()=false（headless 无窗口）", Layout.is_portrait() == false)
	_check("横屏基准 content_scale_for(false)=(1280,720)", Layout.content_scale_for(false) == Vector2i(1280, 720))
	_check("竖屏基准 content_scale_for(true)=(720,1280)", Layout.content_scale_for(true) == Vector2i(720, 1280))
	_check("is_portrait_for_window(0,0)=false（headless）", Layout.is_portrait_for_window(Vector2i(0, 0)) == false)
	_check("is_portrait_for_window(1280,720)=false", Layout.is_portrait_for_window(Vector2i(1280, 720)) == false)
	_check("is_portrait_for_window(720,1280)=true", Layout.is_portrait_for_window(Vector2i(720, 1280)) == true)
	_check("is_portrait_for_window(1080,2400)=true", Layout.is_portrait_for_window(Vector2i(1080, 2400)) == true)
	_check("is_portrait_for_window(1536,2048)=true", Layout.is_portrait_for_window(Vector2i(1536, 2048)) == true)

	# ---------- 二、桌面零漂 ----------
	var vp := Vector2(1280, 720)
	var zero := Vector4.ZERO
	var o := BoardView.board_origin_for(vp, zero)
	_check("横屏棋盘原点仍是 (510,360)（实得 %s）" % [o], o.is_equal_approx(Vector2(510, 360)))
	var r0 := HUD.content_rect(vp, zero)
	_check("横屏内容盒仍是 (910,12) 356×696（实得 %s）" % [r0],
		r0.position.is_equal_approx(Vector2(910, 12)) and r0.size.is_equal_approx(Vector2(356, 696)))

	# ---------- 三、竖屏自检表（容差 0.1） ----------
	Layout.set_portrait(true)
	var ins := Vector4(18, 34, 18, 18)

	# 行 1：1080×2400 机型 → vp 720×1600
	var vp1 := Vector2(720, 1600)
	_check("行1 ui_height=768（实得 %.1f）" % Layout.ui_height(vp1), is_equal_approx(Layout.ui_height(vp1), 768.0))
	var bz1 := Layout.board_rect(vp1, ins)
	_check("行1 board_rect=(26,42) 668×760（实得 %s）" % [bz1],
		bz1.position.is_equal_approx(Vector2(26, 42)) and _near_v2(bz1.size, Vector2(668, 760)))
	var px1 := Layout.px_per_unit_for(bz1)
	_check("行1 px_per_unit=66.12（实得 %.2f）" % px1, absf(px1 - 66.12) <= 0.1)

	# 行 2：1080×1920 机型 → vp 720×1280
	var vp2 := Vector2(720, 1280)
	_check("行2 ui_height=614.4（实得 %.1f）" % Layout.ui_height(vp2), is_equal_approx(Layout.ui_height(vp2), 614.4))
	var bz2 := Layout.board_rect(vp2, ins)
	_check("行2 board_rect=(26,42) 668×593.6（实得 %s）" % [bz2],
		bz2.position.is_equal_approx(Vector2(26, 42)) and _near_v2(bz2.size, Vector2(668, 593.6)))
	var px2 := Layout.px_per_unit_for(bz2)
	_check("行2 px_per_unit=62.96（实得 %.2f）" % px2, absf(px2 - 62.96) <= 0.1)

	# 行 3：iPad 3:4 → vp 720×960（能跑不崩即可）
	var vp3 := Vector2(720, 960)
	var bz3 := Layout.board_rect(vp3, ins)
	_check("行3 board_rect=(26,42) 668×427.2（实得 %s）" % [bz3],
		bz3.position.is_equal_approx(Vector2(26, 42)) and _near_v2(bz3.size, Vector2(668, 427.2)))
	var px3 := Layout.px_per_unit_for(bz3)
	_check("行3 px_per_unit=45.3（实得 %.2f）" % px3, absf(px3 - 45.3) <= 0.1)

	# ---------- 四、几何关系（用行 2 做主断言机） ----------
	var cover := Vector2(Layout.BOARD_W_U * px1, Layout.BOARD_H_U * px1)
	_check("棋盘外接尺寸 %.1f×%.1f 落进行1棋盘区 %s 内" % [cover.x, cover.y, bz1.size],
		cover.x < bz1.size.x and cover.y < bz1.size.y)

	var pr := Layout.panel_rect(vp2, ins)
	_check("信息区顶 %.1f > 棋盘底 %.1f（不压棋盘）" % [pr.position.y, bz2.end.y],
		pr.position.y >= bz2.end.y - 0.01)
	_check("信息区铺到屏底（底缘 %.1f = vp 高）" % pr.end.y, is_equal_approx(pr.end.y, vp2.y))

	var cr := Layout.content_rect(vp2, ins)
	_check("内容区宽高 > 0（%.0f×%.0f）" % [cr.size.x, cr.size.y], cr.size.x > 0 and cr.size.y > 0)
	_check("内容区左缘 %.0f ≥ 安全区左 %.0f" % [cr.position.x, ins.x], cr.position.x >= ins.x)
	_check("内容区右缘 %.0f ≤ 安全区右界 %.0f" % [cr.end.x, vp2.x - ins.z], cr.end.x <= vp2.x - ins.z)
	_check("内容区底缘 %.0f ≤ 安全区底界 %.0f" % [cr.end.y, vp2.y - ins.w], cr.end.y <= vp2.y - ins.w)

	# 竖屏入口：BoardView 棋盘原点在竖屏 = 棋盘区中心；HUD.content_rect 走 Layout
	var o2 := BoardView.board_origin_for(vp2, ins)
	_check("竖屏棋盘原点 = 棋盘区中心（实得 %s）" % [o2], o2.is_equal_approx(bz2.get_center()))
	var r2 := HUD.content_rect(vp2, ins)
	_check("竖屏内容盒 = Layout.content_rect（实得 %s）" % [r2], r2.is_equal_approx(cr))

	# ---------- 五、收尾复原 ----------
	Layout.set_portrait(false)
	_check("复原后 is_portrait()=false", Layout.is_portrait() == false)
	var o_back := BoardView.board_origin_for(vp, zero)
	_check("复原后横屏原点回到 (510,360)（实得 %s）" % [o_back], o_back.is_equal_approx(Vector2(510, 360)))

	print("通过 %d · 失败 %d" % [_pass, fails])
	print("竖屏布局回归：%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

## Godot 的 is_equal_approx 没有容差参数，自检表的 0.1 容差自己包一个
func _near_v2(a: Vector2, b: Vector2, tol: float = 0.1) -> bool:
	return absf(a.x - b.x) <= tol and absf(a.y - b.y) <= tol

func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		fails += 1
		print("  [FAIL] %s" % what)
