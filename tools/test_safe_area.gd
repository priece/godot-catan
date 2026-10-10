extends SceneTree

## 安全区 / 布局回归。
## 跑法：Godot --headless --path . --script res://tools/test_safe_area.gd
## 退出码 0 = 全通过
##
## 为什么值得单开一个测试文件：
##   1. 安全区的取值只能在真机上才有意义（桌面恒为 0），所以布局算式必须抽成
##      纯函数才测得到 —— 本文件测的正是那两个纯函数本身。
##   2. 「桌面 1280×720 下棋盘原点必须还是 (510, 360)」是加安全区时的首要顾虑：
##      一旦被 MIN_* 边距污染，所有截图与旧版对比全部作废。这条钉死。
##   3. 左上角"?"按钮和它展开的图例都新占了一块地，不能压到棋盘上 ——
##      否则手机上会出现"点帮助却建了座村庄"。

var _pass := 0
var fails := 0

func _initialize() -> void:
	# ---------- 一、桌面 / headless：安全区必须为 0 ----------
	var ins := SafeArea.insets()
	_check("headless 下安全区为 0（实得 %s）" % [ins], ins == Vector4.ZERO)

	# ---------- 二、棋盘原点算式 ----------
	var vp := Vector2(1280, 720)
	var o := BoardView.board_origin_for(vp, ins)
	_check("1280×720 桌面下棋盘原点仍是 (510, 360)（实得 %s）" % [o],
		o.is_equal_approx(Vector2(510, 360)))

	# 左侧有挖孔 → 可用区左界右移，棋盘应随之右移（而不是被压住）
	var ins_l := Vector4(44, 0, 0, 0)
	var o_l := BoardView.board_origin_for(vp, ins_l)
	_check("左侧挖孔 44px 时棋盘右移 22px（实得 x=%.1f）" % o_l.x,
		is_equal_approx(o_l.x, 510.0 + 22.0))
	_check("左侧挖孔时不改变纵向位置", is_equal_approx(o_l.y, 360.0))

	# 上下留边（横屏时状态栏多在侧边，但竖屏/异形屏也可能在上下）
	var o_tb := BoardView.board_origin_for(vp, Vector4(0, 24, 0, 24))
	_check("上下安全区各 24px 时纵向居中在 360（实得 y=%.1f）" % o_tb.y,
		is_equal_approx(o_tb.y, 360.0))

	# 棋盘必须仍然完整落在"扣掉面板与安全区"的可用区里
	var avail_w: float = (vp.x - HUD.PANEL_W - ins_l.x - ins_l.z)
	var board_w: float = _board_pixel_width()
	_check("可用宽 %.0f ≥ 棋盘宽 %.0f（挖孔 44px 仍放得下）" % [avail_w, board_w],
		avail_w > board_w)

	# ---------- 三、HUD 内容盒算式 ----------
	var r0 := HUD.content_rect(vp, Vector4.ZERO)
	_check("1280×720 桌面下内容盒仍是 (910, 12) 356×696（实得 %s）" % [r0],
		r0.position.is_equal_approx(Vector2(910, 12)) and r0.size.is_equal_approx(Vector2(356, 696)))

	var ins_r := Vector4(0, 10, 44, 10)
	var r1 := HUD.content_rect(vp, ins_r)
	_check("右侧挖孔 44px 时内容右缘 %.0f ≤ 安全区左界 %.0f" % [r1.end.x, vp.x - ins_r.z],
		r1.end.x <= vp.x - ins_r.z)
	_check("上下安全区把内容盒上下各缩 10px（实得 y=%.0f h=%.0f）" % [r1.position.y, r1.size.y],
		is_equal_approx(r1.position.y, 22.0) and is_equal_approx(r1.size.y, 676.0))
	_check("内容盒不会缩没（宽 %.0f > 0，高 %.0f > 0）" % [r1.size.x, r1.size.y],
		r1.size.x > 100.0 and r1.size.y > 200.0)

	# ---------- 四、"?"按钮与图例的占位 ----------
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	# 图例面板的宽度是按文字实测算的，所以要给一个字体（_ready 里才设，测试里手动补）
	bv.font = bv._cjk_font()
	var hc := bv.help_center()

	_check("按钮完整落在左边界内（圆心 x=%.0f ≥ 半径 %.0f）" % [hc.x, BoardView.HELP_R],
		hc.x >= BoardView.HELP_R)
	_check("按钮完整落在上边界内", hc.y >= BoardView.HELP_R)
	_check("点按钮中心判定命中", bv._hit_help(hc))
	_check("点按钮外侧 30px 判定不命中", not bv._hit_help(hc + Vector2(30.0, 0.0)))

	# 按钮不能压到棋盘的命中热区上
	var nearest := INF
	for v in bv.topo.vertices.size():
		nearest = minf(nearest, bv._p(bv.topo.vertices[v]).distance_to(hc))
	var pick_r: float = BoardView.PICK_VERTEX_R * bv.px_per_unit
	_check("按钮离最近棋盘点 %.0fpx > 顶点热区 %.0fpx + 按钮半径 %.0fpx"
		% [nearest, pick_r, BoardView.HELP_R],
		nearest > pick_r + BoardView.HELP_R)

	# 展开的图例面板跟着安全区走（面板位置 = 按钮位置推出来的），
	# 所以按钮不被挖孔压住，面板也不会。内容 / 尺寸 / 命中判定在 test_legend.gd 里测。
	var legend := bv.legend_rect()
	_check("图例面板左缘 %.0f 与按钮左缘 %.0f 对齐"
		% [legend.position.x, hc.x - BoardView.HELP_R],
		is_equal_approx(legend.position.x, hc.x - BoardView.HELP_R))
	_check("图例面板挂在按钮下方，不与按钮重叠", legend.position.y > hc.y + BoardView.HELP_R)
	_check("图例面板不越出视口右缘", legend.end.x < 1280.0)

	bv.free()

	print("通过 %d · 失败 %d" % [_pass, fails])
	print("安全区 / 布局回归：%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

## 棋盘在屏幕上的实际宽度（最左最右顶点之间 + 两侧六边形半径）
func _board_pixel_width() -> float:
	var topo := BoardTopology.instance()
	var bv := BoardView.new()
	bv.topo = topo
	var mn := INF
	var mx := -INF
	for hi in topo.hexes.size():
		var x: float = bv._p(topo.hex_center[hi]).x
		mn = minf(mn, x - bv.px_per_unit)
		mx = maxf(mx, x + bv.px_per_unit)
	bv.free()
	return mx - mn

func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		fails += 1
		print("  [FAIL] %s" % what)
