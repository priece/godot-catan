extends SceneTree

## 棋盘拾取的几何回归 —— 触屏"点建村落却修了路"的看门狗。
## 跑法：Godot --headless --path . --script res://tools/test_pick.gd
## 退出码 0 = 全通过
##
## 它直接 new 一个 BoardView 调它的私有判定方法，而不是在这里照抄一份逻辑：
## 拾取是纯几何（_p / _pick_* / _nearest_any 都不碰场景树），所以能这么测，
## 而"测的是真代码"正是这条回归的价值 —— 改坏了会立刻红。
##
## 背景（安卓实测暴露）：Pick.ANY 下顶点与边原本按"谁离鼠标更近"竞争，
## 而道路是从顶点发散的线段 —— 手指沿道路方向偏出去时，到线段的距离几乎不增长，
## "离道路更近"永远成立 → 想建村十有八九被判成修路。
## 现在 board_view._nearest_any 改成**顶点优先**，本文件守住这个行为。

var _pass := 0
var fails := 0

func _initialize() -> void:
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	var topo: BoardTopology = bv.topo
	var ppu: float = bv.px_per_unit
	var r_zone: float = BoardView.PICK_VERTEX_R * ppu   # 顶点热区半径（px）

	# ---------- 最坏场景：顶点 v 可建村 + 从它发散的一条边可修路 ----------
	var v := 0
	var e: int = topo.vertex_edges[v][0]
	var pv: Vector2 = bv._p(topo.vertices[v])
	var other: int = topo.other_vertex(e, v)
	var dir: Vector2 = (bv._p(topo.vertices[other]) - pv).normalized()
	var perp := Vector2(-dir.y, dir.x)

	var hv: Array[int] = [v]
	var he: Array[int] = [e]
	var hn: Array[int] = []
	bv.set_highlights(hv, he, hn)

	_check("点顶点正中 → 判建村", bv._nearest_any(pv)[0] == v)

	# 手指沿道路方向偏移 —— 安卓上就是这么误触的
	var bad := 0
	for off in [6.0, 12.0, 18.0, 22.0]:
		if bv._nearest_any(pv + dir * off)[0] != v:
			bad += 1
		if bv._nearest_any(pv - dir * off)[0] != v:
			bad += 1
	_check("沿道路方向偏 6~22px 仍判建村（误判 %d 次）" % bad, bad == 0)

	# 手指横着偏（垂直于道路）
	var bad2 := 0
	for off2 in [6.0, 12.0, 18.0, 22.0]:
		if bv._nearest_any(pv + perp * off2)[0] != v:
			bad2 += 1
		if bv._nearest_any(pv - perp * off2)[0] != v:
			bad2 += 1
	_check("垂直道路方向偏 6~22px 仍判建村（误判 %d 次）" % bad2, bad2 == 0)

	# ---------- 反向：道路不能被顶点热区吃掉，否则变成"修不了路" ----------
	var ea: Vector2i = topo.edges[e]
	var mid: Vector2 = (bv._p(topo.vertices[ea.x]) + bv._p(topo.vertices[ea.y])) * 0.5
	_check("该路中段仍可点 → 判修路", bv._nearest_any(mid)[1] == e)

	# 热区外一点点就该还给道路：保护圈不能无限大
	_check("顶点热区外(+4px) 让位给道路",
		bv._nearest_any(pv + dir * (r_zone + 4.0))[1] == e)

	# 顶点没被高亮时，热区概念不生效 —— 该点路还是点路
	bv.set_highlights(hn, he, hn)
	_check("顶点不可建时同位置 → 判修路（保护区只认已高亮顶点）",
		bv._nearest_any(pv + dir * 10.0)[1] == e)

	# ---------- 全盘扫描 1：任一顶点可建村时，它整个热区内都不得触发道路 ----------
	var leak := 0
	var samples := 0
	for vi in topo.vertices.size():
		var vh: Array[int] = [vi]
		var eh: Array[int] = []
		for ed in topo.vertex_edges[vi]:
			eh.append(ed)
		bv.set_highlights(vh, eh, hn)
		var c: Vector2 = bv._p(topo.vertices[vi])
		for k in 24:
			var ang := TAU * float(k) / 24.0
			for frac in [0.2, 0.5, 0.8, 0.99]:
				samples += 1
				var r: Array = bv._nearest_any(c + Vector2(cos(ang), sin(ang)) * (r_zone * frac))
				if r[0] < 0 and r[1] >= 0:
					leak += 1
	_check("54 顶点热区内全不触发道路（%d 个采样点，泄漏 %d）" % [samples, leak], leak == 0)

	# ---------- 全盘扫描 2：每条路的中点都还点得中（两端都高亮的最坏情况）----------
	var dead := 0
	for eid in topo.edges.size():
		var ee: Vector2i = topo.edges[eid]
		var vh2: Array[int] = [ee.x, ee.y]     # 规则上不会发生，按最坏情况压
		var eh2: Array[int] = [eid]
		bv.set_highlights(vh2, eh2, hn)
		var m: Vector2 = (bv._p(topo.vertices[ee.x]) + bv._p(topo.vertices[ee.y])) * 0.5
		if bv._nearest_any(m)[1] != eid:
			dead += 1
	_check("72 条道路中点均可点（最坏情况下失效 %d 条）" % dead, dead == 0)

	bv.free()
	print("通过 %d · 失败 %d" % [_pass, fails])
	print("拾取回归：%s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)

func _check(what: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		fails += 1
		print("  [FAIL] %s" % what)
