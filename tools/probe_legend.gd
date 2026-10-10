extends SceneTree

## 图例版式探针：打印面板尺寸，以及面板到底压住了棋盘的哪些东西
## （地块 / 顶点 / 港口牌）。改图例文案、行数、字号后随手跑一下，
## 比盯着截图估要准 —— 尤其"隐约露出来的那个港口牌"这种半透明叠加。
## 跑法：Godot --headless --path . --script res://tools/probe_legend.gd

func _initialize() -> void:
	var bv := BoardView.new()
	bv.topo = BoardTopology.instance()
	bv.font = bv._cjk_font()
	bv.board = Board.generate(20261005, true)
	bv.legend_open = true

	var rect := bv.legend_rect()
	print("面板 %s -> %s（%.0f × %.0f）" % [rect.position, rect.end, rect.size.x, rect.size.y])
	var cols := bv._legend_col_widths()
	print("左列宽 %.0f · 右列宽 %.0f" % [cols.x, cols.y])
	for row in bv._legend_cost_rows():
		print("  %-6s %s" % [row[0], bv._legend_cost_text(row[1])])

	var hexes := 0
	var verts := 0
	for hi in bv.topo.hexes.size():
		for p in bv._hex_poly(hi):
			if rect.has_point(p):
				hexes += 1
				break
	for v in bv.topo.vertices.size():
		if rect.has_point(bv._p(bv.topo.vertices[v])):
			verts += 1
	print("落在面板里的：地块顶点 %d 处（涉及地块 %d 个）" % [verts, hexes])

	var ports := 0
	var side := bv.px_per_unit * BoardView.PORT_BOX
	for eid in bv.board.port_edges:
		var pos := bv.port_marker_pos(eid)
		if rect.intersects(Rect2(pos - Vector2(side, side) * 0.5, Vector2(side, side))):
			ports += 1
			print("  港口牌被压：%s" % pos)
	print("被面板压住的港口牌：%d 个" % ports)

	print("视口 1280×720 内：右 %.1f/1280 · 下 %.1f/720" % [rect.end.x, rect.end.y])
	bv.free()
	quit(0)
