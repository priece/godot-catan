extends SceneTree

## 真实渲染截图校验（必须去掉 --headless 运行，headless 下无法截图）。
##
## 用法：
##   Godot --path . --script res://tools/screenshot.gd -- \
##       res://scenes/main.tscn /tmp/catan_board.png [等待帧数]
##
## 做法：加载场景 -> 等若干帧让 _draw() 完成 -> 在 frame_post_draw 里抓图 -> 退出。
## 用 RenderingServer.frame_post_draw 信号而非 _initialize 里 await，
## 是因为脚本式 SceneTree 的 _initialize 返回后引擎才会继续渲染。

var _scene_path := "res://scenes/main.tscn"
var _shot_path := "/tmp/catan_board.png"
var _wait := 25
var _done := false
var _zoom := 0.0        ## >0 时覆盖棋盘缩放（用来放大检查细节）

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_scene_path = args[0]
	if args.size() > 1:
		_shot_path = args[1]
	if args.size() > 2:
		_wait = int(args[2])
	if args.size() > 3:
		_zoom = float(args[3])

	var packed: PackedScene = load(_scene_path)
	if packed == null:
		print("!! 无法加载场景: ", _scene_path)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	print("OK 场景已加载: %s" % _scene_path)
	# 注意：add_child 之后立刻读节点属性拿到的是"未 ready"的值，
	# 所以棋盘自检要放到 _on_frame 里做，不能在这里判。

	RenderingServer.frame_post_draw.connect(_on_frame)

func _report(node: Node) -> void:
	var bv := _find_board_view(node)
	if bv == null:
		print("!! 没找到 BoardView 节点")
		return
	if bv.board == null:
		print("!! BoardView.board 为空（_ready 还没跑或生成失败）")
		return
	print("OK board: 地块 %d · 顶点 %d · 边 %d · 港口 %d · 强盗在地块 %d" % [
		bv.board.hex_terrain.size(),
		bv.topo.vertices.size(),
		bv.topo.edges.size(),
		bv.board.port_edges.size(),
		bv.board.robber_hex,
	])
	var errs: Array = bv.board.self_check(_is_fresh(bv))
	if errs.is_empty():
		print("OK board 自检通过")
	else:
		for e in errs:
			print("!! " + e)

	# 把 9 个港口的类型与位置直接打出来：小尺寸截图靠肉眼分颜色不可靠
	var counts := {}
	for eid in bv.board.port_edges:
		var e: Vector2i = bv.topo.edges[eid]
		var t: int = bv.board.vertex_port[e.x]
		counts[t] = counts.get(t, 0) + 1
		var mid: Vector2 = (bv.topo.vertices[e.x] + bv.topo.vertices[e.y]) * 0.5
		print("   港口牌「%s」 所在边的中点 (%.2f, %.2f) · 牌心屏幕坐标 %s"
			% [bv.port_label(t), mid.x, mid.y, bv.port_marker_pos(eid)])
	print("  港口类型统计: %s" % [counts])

	# 地形贴图加载情况
	var tex_ok := 0
	for t in 6:
		if bv._terrain_texture(t) != null:
			tex_ok += 1
	print("  地形贴图: %d/6 已加载（贴图与纯色块颜色接近，肉眼分不出，必须查这里）" % tex_ok)

func _find_board_view(node: Node) -> Node:
	if "board" in node and "topo" in node:
		return node
	for c in node.get_children():
		var r := _find_board_view(c)
		if r != null:
			return r
	return null

## 是否还处在"刚生成、一步没走"的状态。
## 只有这时强盗才必须待在沙漠上（开局后它会被正常移走）。
func _is_fresh(bv: Node) -> bool:
	if bv.ctl == null:
		return true
	for p in bv.ctl.st.players:
		if not p.roads.is_empty():
			return false
	return true

func _on_frame() -> void:
	if _done:
		return
	if _wait > 0:
		_wait -= 1
		return
	_done = true
	# 等到这里节点已经 ready，属性才是真实值
	_report(root)
	# 贴图是否真的用上了：颜色相近时肉眼看不出，必须查
	var bv := _find_board_view(root)
	if bv != null and _zoom > 0.0:
		bv.px_per_unit = _zoom
		bv.board_origin = root.get_texture().get_image().get_size() * 0.5
		bv.redraw()
		await _after_zoom()
	var img: Image = root.get_texture().get_image()
	img.save_png(_shot_path)
	print("OK 截图已保存 %s -> %s" % [img.get_size(), _shot_path])
	quit(0)

func _after_zoom() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
