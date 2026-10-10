extends SceneTree

## 港口牌渲染回归。
## 跑法：Godot --headless --path . --script res://tools/test_ports.gd
## 退出码 0 = 全通过
##
## 三条容易悄悄写错、又在截图上看不太出来的点：
##   1. **牌面文字**。现在通用港只写「?」、指定港只写一个资源短名，比例不写。
##      短名必须来自 `UIPalette.RES_SHORT`（和图例 / HUD 同一份），
##      不能在这里又写一遍 `R_NAMES_CN[i].left(1)` —— 两处各写一份迟早会不一致。
##   2. **牌心要落在这条边的垂直平分线上**。旧实现沿"棋盘中心 -> 边中点"的
##      **径向**外推，而正确的方向是这条边的**外法线**。岛屿外缘那 9 条边的
##      两者夹角是 23.4° / 49.1°，旧代码的牌心会横向偏离边中线最多 24px ——
##      截图上就是"港口牌歪在一边、没对准它那条边"。这条断言专门拦这个回归。
##   3. 牌子变小了，但**仍然不能压到沙岸 / 地块，也不能和别的牌子或顶点锚点重叠**。

var _pass := 0
var fails := 0

func _initialize() -> void:
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	bv.font = bv._cjk_font()
	bv.board = Board.generate(bv.seed_value, bv.beginner_board)

	# ---------- 一、牌面文字 ----------
	print("-- 牌面文字 --")
	_check("通用港写「?」（实得「%s」）" % bv.port_label(Res.Port.GENERIC_3),
		bv.port_label(Res.Port.GENERIC_3) == "?")
	for r in Res.R_COUNT:
		var ptype: int = r + 1        # WOOD_2 = 1
		var got := bv.port_label(ptype)
		_check("2:1 %s 港写「%s」" % [Res.R_NAMES_CN[r], got], got == UIPalette.RES_SHORT[r])
	# 短名只有一位 —— 牌面就是一个字，这条保证版式算得准
	for ptype in Res.Port.size():
		_check("牌面「%s」是单个字符" % bv.port_label(ptype),
			bv.port_label(ptype).length() == 1)

	# ---------- 二、9 个港口各就各位 ----------
	print("-- 港口构成 --")
	var b := bv.board
	_check("港口 9 个（实得 %d）" % b.port_edges.size(), b.port_edges.size() == Res.PORT_COUNT)

	var by_type := {}
	for eid in b.port_edges:
		var e: Vector2i = bv.topo.edges[eid]
		var t: int = b.vertex_port[e.x]
		by_type[t] = by_type.get(t, 0) + 1
	_check("通用 3:1 港 4 个（实得 %d）" % by_type.get(Res.Port.GENERIC_3, 0),
		by_type.get(Res.Port.GENERIC_3, 0) == 4)
	for r in Res.R_COUNT:
		var t: int = r + 1
		_check("2:1 %s 港 1 个（实得 %d）" % [Res.R_NAMES_CN[r], by_type.get(t, 0)],
			by_type.get(t, 0) == 1)

	# ---------- 三、牌心几何 ----------
	print("-- 牌心几何 --")
	var side := bv.px_per_unit * BoardView.PORT_BOX
	var worst_along := 0.0        # 牌心偏离"边中线"的横向量（世界单位）
	var worst_gap_deg := 0.0      # 径向 vs 外法线的夹角（只为说明为何不用径向）
	var positions: Array[Vector2] = []
	for eid in b.port_edges:
		var e: Vector2i = bv.topo.edges[eid]
		var a: Vector2 = bv.topo.vertices[e.x]
		var c: Vector2 = bv.topo.vertices[e.y]
		var mid: Vector2 = (a + c) * 0.5
		var along := (c - a).normalized()
		var n := Vector2(-along.y, along.x)
		if n.dot(mid) < 0.0:
			n = -n

		var world := (bv.port_marker_pos(eid) - bv.board_origin) / bv.px_per_unit
		var rel := world - mid

		# (a) 横向偏移必须 ≈ 0 —— 这就是"画在边的居中位置"
		var lateral: float = absf(rel.dot(along))
		worst_along = maxf(worst_along, lateral)
		# (b) 垂距必须 ≈ PORT_OUT
		var perp: float = absf(rel.dot(n))
		_check("边#%d 牌心横向偏移 %.4f ≈ 0（落在垂直平分线上）" % [eid, lateral],
			lateral < 0.002)
		_check("边#%d 牌心到边的垂距 %.3f ≈ PORT_OUT %.2f" % [eid, perp, BoardView.PORT_OUT],
			absf(perp - BoardView.PORT_OUT) < 0.002)
		# (c) 必须朝外（比边中点离棋盘中心更远）
		_check("边#%d 牌心在岛外一侧" % eid,
			world.length() > mid.length() and rel.dot(n) > 0.0)

		var gap_deg := rad_to_deg(absf(mid.angle_to(n)))
		worst_gap_deg = maxf(worst_gap_deg, gap_deg)
		positions.append(world)

	print("  [note] 最大横向偏移 %.4f 世界单位（旧径向实现约 0.38）" % worst_along)
	print("  [note] 径向与外法线最大夹角 %.1f°（这就是不能拿径向当法线用的原因）" % worst_gap_deg)
	_check("确实存在「径向 ≠ 外法线」的港口边（否则这次改动无从谈起）", worst_gap_deg > 10.0)

	# ---------- 四、牌子之间 / 与顶点锚点不重叠 ----------
	print("-- 不重叠 --")
	var min_pair := INF
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			# 换算到屏幕像素再比 —— 牌子尺寸（side）是 px
			min_pair = minf(min_pair,
				bv._p(positions[i]).distance_to(bv._p(positions[j])))
	var need_pair := (side + 6.0)      # 两块方牌外带一点缝
	print("  [note] 最近两块牌相距 %.1fpx（需 > %.1f）" % [min_pair, need_pair])
	_check("任意两块港口牌不重叠", min_pair > need_pair)

	var min_vertex := INF
	for eid in b.port_edges:
		var e: Vector2i = bv.topo.edges[eid]
		var p := bv.port_marker_pos(eid)
		for vid in [e.x, e.y]:
			min_vertex = minf(min_vertex, p.distance_to(bv._p(bv.topo.vertices[vid])))
	var need_vertex := side * 0.72 + BoardView.VERTEX_R * bv.px_per_unit
	print("  [note] 牌心离最近顶点 %.1fpx（需 > %.1f）" % [min_vertex, need_vertex])
	_check("港口牌不与顶点锚点重叠（否则挡住可建村的点）", min_vertex > need_vertex)

	# ---------- 五、牌不压沙岸 / 地块 ----------
	print("-- 不压地块 --")
	var k := 1.0 + BoardView.COAST_BAND        # 连沙岸一起算进去
	var box_half := side * 0.5
	var hits := 0
	for eid in b.port_edges:
		var box := Rect2(bv.port_marker_pos(eid) - Vector2(box_half, box_half),
			Vector2(side, side))
		for hi in bv.topo.hexes.size():
			if _poly_hits_rect(bv._hex_poly(hi, k), box):
				hits += 1
				print("   !! 牌 #%d 压到地块 %d" % [eid, hi])
				break
	_check("9 块港口牌都不压沙岸 / 地块（实得 %d 块压住）" % hits, hits == 0)

	# 牌心要落在视口里（1280×720 桌面档）—— 港口是判断交易汇率的关键信息，被裁掉就废了
	var vp := Vector2(1280, 720)
	var outside := 0
	var margin := []
	for p in positions:
		var px := bv._p(p)
		if px.x < side or px.y < side or px.x > vp.x - side or px.y > vp.y - side:
			outside += 1
			margin.append(px)
	_check("9 块港口牌全部落在 1280×720 视口内（实得 %d 块越界）" % outside, outside == 0)
	if outside > 0:
		for m in margin:
			print("   !! 越界牌心 %s" % m)

	bv.free()
	print("通过 %d · 失败 %d" % [_pass, fails])
	print("港口牌回归：%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _poly_hits_rect(poly: PackedVector2Array, rect: Rect2) -> bool:
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
		var bb := poly[(i + 1) % poly.size()]
		for j in 4:
			if Geometry2D.segment_intersects_segment(a, bb, corners[j], corners[(j + 1) % 4]) != null:
				return true
	return false

func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		fails += 1
		print("  [FAIL] %s" % what)
