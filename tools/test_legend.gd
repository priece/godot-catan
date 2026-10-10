extends SceneTree

## 图例（左上角"?"展开的面板）回归。
## 跑法：Godot --headless --path . --script res://tools/test_legend.gd
## 退出码 0 = 全通过
##
## 为什么值得单开一个测试文件：
##   1. 图例里那份「修路 / 村落 / 城市 / 发展卡 要花什么」**必须从 Res.COST_* 读**。
##      手抄一份进 UI 是这类说明性文案最容易出的错 —— 规则改了它不会跟着改，
##      而且错得很体面：数字看着都合理，要等玩家照着建不出来才发现。
##      所以这里断言的是"数据来源"，不是"文案长什么样"。
##   2. 面板宽度是**按文字实测算出来**的，没有写死。换字体 / 改文案后它可能悄悄
##      胀出视口或盖到右侧信息面板上，这里钉住。
##   3. 面板比原来宽，会压住棋盘最左边一点点 —— 这是有意的浮层。但既然视觉上
##      压住了，交互上就必须一起压住：落在面板上的点击要被面板吃掉，
##      否则又会变成"想看图例，结果在底下建了座村庄"。

var _pass := 0
var fails := 0

func _initialize() -> void:
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	bv.font = bv._cjk_font()
	bv.legend_open = true

	# ---------- 一、花费文案必须来自 Res.COST_* ----------
	var rows := bv._legend_cost_rows()
	_check("建造花费共 4 行（实得 %d）" % rows.size(), rows.size() == 4)

	var want_names := ["修路", "村落", "城市", "发展卡"]
	var want_costs := [
		Res.COST_ROAD, Res.COST_SETTLEMENT, Res.COST_CITY, Res.COST_DEV,
	]
	for i in rows.size():
		_check("第 %d 行卡名是「%s」（实得「%s」）" % [i + 1, want_names[i], rows[i][0]],
			rows[i][0] == want_names[i])
		# 同一份字典对象：图例只是引用规则层的花费表，没抄第二份
		_check("「%s」的花费就是 Res 里那本账（不得另抄一份）" % rows[i][0],
			rows[i][1] == want_costs[i])

	# 排版出来是短名 + 张数，例如「木1 砖1 羊1 麦1」
	var want_text := ["木1 砖1", "木1 砖1 羊1 麦1", "麦2 矿3", "羊1 麦1 矿1"]
	for i in rows.size():
		var got: String = bv._legend_cost_text(rows[i][1])
		_check("「%s」排版为「%s」（实得「%s」）" % [rows[i][0], want_text[i], got],
			got == want_text[i])

	# 每张牌花费的张数总和也要对得上规则层（防排版时漏掉一种资源）
	for i in rows.size():
		var got_n: int = 0
		for r in Res.R_COUNT:
			if rows[i][1].has(r):
				got_n += rows[i][1][r]
		_check("「%s」共 %d 张，与 Res.cost_total 一致" % [rows[i][0], got_n],
			got_n == Res.cost_total(rows[i][1]))

	# ---------- 二、地形那列不能漏地形 ----------
	_check("地形图例覆盖全部 6 种地形（实得 %d）" % BoardView.LEGEND_TERRAINS.size(),
		BoardView.LEGEND_TERRAINS.size() == Res.TERRAIN_CN.size())
	for t in BoardView.LEGEND_TERRAINS:
		var want: String = Res.TERRAIN_CN[t]
		var r: int = Res.TERRAIN_RES.get(t, -1)
		want += " · " + (Res.R_NAMES_CN[r] if r >= 0 else "无产出")
		_check("地形行「%s」与 Res.TERRAIN_RES 一致" % want,
			bv._legend_terrain_label(t) == want)

	# ---------- 三、面板几何 ----------
	var vp := Vector2(1280, 720)
	var rect := bv.legend_rect()
	var hc := bv.help_center()

	_check("面板左缘 %.0f 与按钮左缘 %.0f 对齐（含安全区）" % [rect.position.x, hc.x - BoardView.HELP_R],
		is_equal_approx(rect.position.x, hc.x - BoardView.HELP_R))
	_check("面板挂在按钮下方（间隔 %.0fpx）" % (rect.position.y - (hc.y + BoardView.HELP_R)),
		is_equal_approx(rect.position.y, hc.y + BoardView.HELP_R + BoardView.LEGEND_GAP))
	_check("面板不与按钮重叠", rect.position.y > hc.y + BoardView.HELP_R)
	_check("面板完整落在视口内（右 %.0f < %.0f，下 %.0f < %.0f）"
		% [rect.end.x, vp.x, rect.end.y, vp.y],
		rect.end.x < vp.x and rect.end.y < vp.y)
	_check("面板不侵入右侧信息面板（右缘 %.0f < HUD 左缘 %.0f）"
		% [rect.end.x, vp.x - HUD.PANEL_W],
		rect.end.x < vp.x - HUD.PANEL_W)
	_check("两列都不会被算成 0 宽（左 %.0f · 右 %.0f）"
		% [bv._legend_col_widths().x, bv._legend_col_widths().y],
		bv._legend_col_widths().x > 0.0 and bv._legend_col_widths().y > 0.0)

	# 面板是浮层，会压到棋盘左上角那一小块（两列比原来一列宽）。
	# 底线是**不能压住任何地块** —— 地块几何是固定的（与种子无关），所以这条守得住；
	# 港口牌的位置随种子变，偶尔被擦到一角是浮层的正常行为，只在下面报个数。
	var hex_hit := 0
	for hi in bv.topo.hexes.size():
		if _hex_hits_rect(bv._hex_poly(hi), rect):
			hex_hit += 1
	_check("面板不压住任何地块（实得 %d 个地块与面板相交）" % hex_hit, hex_hit == 0)

	# ---------- 四、命中判定：面板要吃掉落点 ----------
	_check("面板中心在命中区内", bv._hit_legend(rect.get_center()))
	_check("面板右下角在内（面板盖住棋盘的那块也算面板）",
		bv._hit_legend(rect.end - Vector2(4.0, 4.0)))
	_check("面板外的点不命中", not bv._hit_legend(rect.end + Vector2(40.0, 0.0)))
	_check("按钮本身不算面板（否则点按钮展不开）",
		not bv._hit_legend(hc))
	bv.legend_open = false
	_check("收起状态下整块区域都不命中原面板",
		not bv._hit_legend(rect.get_center()))
	bv.legend_open = true

	# 面板罩住的那块区域里确实有棋盘点 —— 所以"面板吃点击"不是空谈，
	# 光靠"左上角离棋盘远"是拦不住这种误落子的（面板底部已经探进棋盘范围）。
	var covered := 0
	for v in bv.topo.vertices.size():
		if rect.has_point(bv._p(bv.topo.vertices[v])):
			covered += 1
	print("  [note] 面板罩住的棋盘点：%d 个（面板底缘 %.0f）" % [covered, rect.end.y])

	bv.free()
	print("通过 %d · 失败 %d" % [_pass, fails])
	print("图例回归：%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

## 六边形和面板矩形是否真的相交。
## 只判"顶点落在矩形里"不够 —— 一条边可能横穿矩形而两个端点都在外面。
func _hex_hits_rect(poly: PackedVector2Array, rect: Rect2) -> bool:
	for p in poly:
		if rect.has_point(p):
			return true
	var corners := [
		rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y),
	]
	for c in corners:
		if Geometry2D.is_point_in_polygon(c, poly):
			return true
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for j in 4:
			var hit = Geometry2D.segment_intersects_segment(
				a, b, corners[j], corners[(j + 1) % 4])
			if hit != null:
				return true
	return false

func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		fails += 1
		print("  [FAIL] %s" % what)
