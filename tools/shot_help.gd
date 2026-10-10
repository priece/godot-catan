extends SceneTree

## "?"图例按钮的渲染验证 —— **必须去掉 --headless**（否则拿不到 frame_post_draw，
## 主循环会空转不退出，最后被 kill 成 exit 137）。
##
## 用法：
##   Godot --path . --resolution 1280x720 --script res://tools/shot_help.gd -- [截图前缀]
##
## 它干四件事：
##   1. 截"收起 / 展开"两张图，人工确认"?"按钮与图例面板（两列：地形 + 建造花费）的位置和配色；
##   2. 用 root.push_input 发**真实鼠标点击**给按钮，确认能翻转展开状态
##      （直接调 legend_open 不算数 —— 那测不到命中判定和输入通路）；
##   3. 在 Pick.ANY + 顶点已高亮的情况下点按钮，确认**没有误落子**；
##   4. 把棋盘上移，让棋盘点真的落进面板里，再点它 —— 确认**点面板本体也不落子**
##      （面板是浮层，视觉上盖住的区域必须交互上也盖住）。

var _scene: Node
var _bv: BoardView
var _hud: HUD
var _prefix := "/tmp/catan_help"
var _step := 0
var _wait := 20
var _clicks := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("!! 无法加载主场景")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame() -> void:
	if _step > 4:
		return
	if _wait > 0:
		_wait -= 1
		return
	match _step:
		0:
			_bv = _find_board(_scene)
			_hud = _find_hud(_scene)
			if _bv == null or _hud == null:
				print("!! 没找到 BoardView / HUD")
				quit(1)
				return
			_bv.vertex_clicked.connect(func(_v: int): _clicks += 1)
			_bv.edge_clicked.connect(func(_e: int): _clicks += 1)
			print("按钮中心 %s · 棋盘原点 %s · 棋盘缩放 %.0f" % [
				_bv.help_center(), _bv.board_origin, _bv.px_per_unit])
			print("收起态截图 -> %s_closed.png" % _prefix)
			_shot(_prefix + "_closed.png")
			_next(1)
		1:
			# 真实点击：先把棋盘设成"随便点哪都能落子"的最宽松模式，再点问号
			_bv.set_pick_mode(BoardView.Pick.ANY)
			_bv.set_highlights(_some_vertices(), _some_edges(), [])
			_click(_bv.help_center())
			print("点按钮后 legend_open=%s · 误落子 %d 次" % [_bv.legend_open, _clicks])
			if not _bv.legend_open:
				print("!! 点击没有展开图例（命中判定 / 输入通路有问题）")
			if _clicks > 0:
				print("!! 点问号竟然触发了棋盘落子")
			_bv.redraw()
			_next(2)
		2:
			print("展开态截图 -> %s_open.png" % _prefix)
			_shot(_prefix + "_open.png")
			# 图例面板比按钮大得多，会浮在棋盘左上角那块海域上。1280×720 下它
			# 正好差 10px 够不到最左边那个地块（见 test_legend.gd），于是这里
			# **故意把棋盘往上挪**，让棋盘点真的落进面板里 —— 否则"面板吃点击"
			# 这段代码在测试分辨率下永远走不到，只能等上了矮屏手机才暴露。
			var keep := _bv.board_origin
			_bv.board_origin = keep - Vector2(0.0, 165.0)
			_bv.redraw()
			var under := _vertex_under_panel()
			if under >= 0:
				var vs := _some_vertices()
				if not vs.has(under):
					vs.append(under)
				_bv.set_highlights(vs, _some_edges(), [])
				var p := _bv._p(_bv.topo.vertices[under])
				var before := _clicks
				print("棋盘上移 165px 后，棋盘点 #%d %s 落进面板（命中判定 %s）"
					% [under, p, _bv._hit_legend(p)])
				_click(p)
				print("点面板上这个棋盘点：误落子 %d 次（应为 0）" % (_clicks - before))
				if _clicks != before:
					print("!! 点在图例面板上竟然落子了 —— 面板没有吃掉点击")
			else:
				print("!! 挪了棋盘还是没有棋盘点落进面板 —— 面板尺寸 / 命中判定有问题")
			_bv.board_origin = keep
			_bv.redraw()
			_click(_bv.help_center())
			print("再点一次 legend_open=%s（应为 false）· 误落子 %d 次" % [_bv.legend_open, _clicks])
			_next(3)
		3:
			# 安全区那段代码在桌面上永远走不到（真实 insets 恒为 0），
			# 于是这里注入一组"手机横屏"的值强行跑一遍：左挖孔 44 + 右挖孔 44 + 底部手势条 18。
			# 不这么做，"避让"就只能等上真机才发现写错。
			SafeArea.set_override(Vector4(44, 0, 44, 18))
			_bv._on_viewport_changed()
			_hud._apply_layout()
			_bv.legend_open = true
			_bv.redraw()
			print("模拟安全区 左44/右44/下18：按钮中心 %s · 棋盘原点 %s" % [
				_bv.help_center(), _bv.board_origin])
			print("模拟安全区截图 -> %s_safe.png" % _prefix)
			_next(4)
		_:
			_step = 5          # 先置位再截图：quit() 要等本帧结束才生效，不然会重复跑一次
			_shot(_prefix + "_safe.png")
			SafeArea.set_override(null)
			print("安全区已复位（后续运行不再受影响）")
			quit(0)

func _next(step: int) -> void:
	_step = step
	_wait = 5

## 发一次真实左键点击（走完整的输入通路：Viewport -> GUI -> _unhandled_input）
func _click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	root.push_input(ev)

## 存整图，另外再存一张左上角的 2 倍放大图 ——
## "?"按钮和图例都挤在那一小块里，整图缩着看会漏掉 1px 级的错位。
func _shot(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	var region := Rect2i(Vector2i.ZERO, Vector2i(290, 310)).intersection(
		Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(region)
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(path.get_basename() + "_zoom.png")
	print("   局部放大 -> %s_zoom.png" % path.get_basename())

func _some_vertices() -> Array[int]:
	var out: Array[int] = []
	for i in mini(6, _bv.topo.vertices.size()):
		out.append(i)
	return out

## 找第一个被图例面板罩住的棋盘点（面板罩住 0 个的话返回 -1，说明面板偏小、验证无效）
func _vertex_under_panel() -> int:
	var rect := _bv.legend_rect()
	for v in _bv.topo.vertices.size():
		if rect.has_point(_bv._p(_bv.topo.vertices[v])):
			return v
	return -1

func _some_edges() -> Array[int]:
	var out: Array[int] = []
	for i in mini(6, _bv.topo.edges.size()):
		out.append(i)
	return out

func _find_board(n: Node) -> BoardView:
	if n is BoardView:
		return n
	for c in n.get_children():
		var r := _find_board(c)
		if r != null:
			return r
	return null

func _find_hud(n: Node) -> HUD:
	if n is HUD:
		return n
	for c in n.get_children():
		var r := _find_hud(c)
		if r != null:
			return r
	return null
