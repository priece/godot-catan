extends SceneTree

## 只读探针：打印 9 个港口牌的坐标算式差异。
## 现状 = 沿"棋盘中心 -> 边中点"的径向外推；候选 = 沿该边的外法线外推。
## 两者只有在边恰好垂直于半径时才重合，否则港口牌会从边中线的正上方偏出去。

func _initialize() -> void:
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	bv.font = bv._cjk_font()
	bv.board = Board.generate(bv.seed_value, bv.beginner_board)

	var b := bv.board
	var t := bv.topo
	print("港口边数 %d" % b.port_edges.size())
	print("世界单位下：边半长 = %.3f（= 1 的一半）" % 0.5)

	var max_gap := 0.0
	for eid in b.port_edges:
		var e: Vector2i = t.edges[eid]
		var a: Vector2 = t.vertices[e.x]
		var c: Vector2 = t.vertices[e.y]
		var mid: Vector2 = (a + c) * 0.5
		var dir: Vector2 = (c - a).normalized()

		# 外法线：边的垂线里，背离棋盘中心的那一条
		var n := Vector2(-dir.y, dir.x)
		if n.dot(mid) < 0.0:
			n = -n

		var old_pos: Vector2 = mid + mid.normalized() * BoardView.PORT_OUT
		var new_pos: Vector2 = mid + n * BoardView.PORT_OUT
		var gap: float = old_pos.distance_to(new_pos)
		max_gap = maxf(max_gap, gap)

		# 港口牌中心到"边所在直线"的垂距：理想情况下应当等于 PORT_OUT
		var perp: float = absf((old_pos - mid).dot(n))

		var ptype: int = b.vertex_port[e.x]
		var label := "3:1" if ptype == Res.Port.GENERIC_3 else "%sx2 : 1" % Res.R_NAMES_CN[ptype - 1].left(1)
		print("  %-10s 边#%2d  径向角 %6.1f°  法线角 %6.1f°  夹角 %5.1f°  | 旧->新位移 %.3f (%.0fpx)  旧位置垂距 %.3f"
			% [label, eid, rad_to_deg(mid.angle()), rad_to_deg(n.angle()),
			   rad_to_deg(mid.angle_to(n)), gap, gap * bv.px_per_unit, perp])

	print("最大位移 %.3f（%.0fpx），PORT_OUT = %.2f" % [max_gap, max_gap * bv.px_per_unit, BoardView.PORT_OUT])
	bv.free()
	quit(0)
