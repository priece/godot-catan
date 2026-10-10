class_name BoardView
extends Node2D

## 棋盘渲染 + 交互（P4 阶段二 / P5）。
##
## 为什么用 _draw() 手绘、而不是给 19 个地块 / 54 个顶点 / 72 条边各建节点：
##   棋盘是静态的，一次性绘制比维护上百个节点的树轻得多。
##   交互命中测试用几何计算即可，不需要碰撞体。
##
## 坐标换算：逻辑层用"地块半径 = 1"的世界单位，这里统一乘 px_per_unit
## 再平移到 board_origin。命中测试做反向换算。

signal vertex_clicked(v: int)
signal edge_clicked(e: int)
signal hex_clicked(h: int)

## 当前允许点选的对象类型（由 GameDirector 设置）
## ANY = 顶点和边同时可选 —— 人类回合需要这种模式，否则只能二选一，
##       想点路就点不到村庄。判定规则是**顶点优先**，不是"谁离得更近谁赢"。
enum Pick { NONE, VERTEX, EDGE, HEX, ANY }

# ---------------- 可调参数 ----------------
@export var seed_value: int = 20261005
## 数字摆放严格程度（见 Board.generate）。地形一律纯随机，官方无"同资源不相邻"限制。
@export var beginner_board: bool = true
@export var px_per_unit: float = 62.0
@export var board_origin: Vector2 = Vector2(510.0, 360.0)
@export var show_vertices: bool = true
@export var show_ports: bool = true
@export var show_legend: bool = true
## 用真实贴图画地块。关掉就回退到纯色块（调试 / 贴图缺失时用）
@export var use_terrain_textures: bool = true

## 设计稿里棋盘刻意右移的量（DESIGN §16.5：给左上角图例腾地方）。
## 保留它，才能让 16:9（视口 1280）下的落点仍是 (510, 360)，与旧版逐像素一致。
const BOARD_X_BIAS := 62.0

# ---------------- 外观常量 ----------------
const COAST_BAND := 0.07
const TOKEN_R := 0.355
const VERTEX_R := 0.05
const ROBBER_R := 0.20
const PORT_OUT := 0.46
const ROAD_W := 0.13
## 顶点命中半径（世界单位）。**要按触摸屏的尺寸定，不能按鼠标定**：
## 手指接触面积约 40~50px，旧值 0.26×62 ≈ 16px 在手机上几乎点不准，
## 于是"想建村"时手指稍一偏移就落进旁边道路的热区里。
## 0.40×62 ≈ 25px。敢给这么大是有依据的：官方规则要求村庄之间相隔 ≥2 条边，
## 所以**同一条边的两端不可能同时是可建村/可升城的顶点**，
## 把顶点热区加大，绝不会把某条道路的两头同时堵死（最坏也留 ~37px 可点中段）。
const PICK_VERTEX_R := 0.40
const PICK_EDGE_R := 0.18        ## 边的命中半径（点到线段距离）

## 左上角地形图例的版式
const LEGEND_X := 14.0
const LEGEND_Y := 58.0
const LEGEND_W := 160.0
const LEGEND_ROW_H := 31.0
const LEGEND_HEX_R := 11.0

## 地块贴图。只采样图片中间一小块：
## 原图是带白边的圆角方形插画（四角还有 AI 水印），六边形按外接矩形取 UV
## 会把四角裁掉，再往里收一点边，白边和水印就都不见了。
const TEX_DIR := "res://assets/terrain/"
const TEX_INSET := 0.05
const TEX_NAMES := ["forest.png", "hills.png", "pasture.png", "fields.png", "mountains.png", "desert.png"]

var _tex_cache: Array = []       ## 地形枚举序号 -> Texture2D（加载失败为 null）

func _terrain_texture(t: int) -> Texture2D:
	if not use_terrain_textures:
		return null
	while _tex_cache.size() <= t:
		_tex_cache.append(null)
	if _tex_cache[t] == null:
		var path: String = TEX_DIR + String(TEX_NAMES[t])
		if ResourceLoader.exists(path):
			_tex_cache[t] = load(path)
	return _tex_cache[t]

## 四个玩家颜色（统一取自 UIPalette，避免与界面面板跑偏）
const PLAYER_COLORS := UIPalette.PLAYER

# ---------------- 运行时 ----------------
var topo: BoardTopology
var board: Board
var font: Font
var _port_box: StyleBoxFlat

var ctl: GameController = null        ## 由 GameDirector 注入，用于读取棋子

var pick_mode: int = Pick.NONE
var highlight_vertices: Array[int] = []
var highlight_edges: Array[int] = []
var highlight_hexes: Array[int] = []

var hover_vertex := -1
var hover_edge := -1
var hover_hex := -1

func _ready() -> void:
	topo = BoardTopology.instance()
	font = _cjk_font()
	_port_box = StyleBoxFlat.new()
	_port_box.bg_color = Color(0.969, 0.957, 0.925)
	_port_box.border_color = Color(0.15, 0.15, 0.15, 0.45)
	_port_box.set_border_width_all(1)
	_port_box.set_corner_radius_all(5)
	_rebuild()
	# 跟随视口重排棋盘：手机横屏比 16:9 更宽时，让棋盘在
	# "视口扣掉右侧面板"的区域里居中，而不是死守设计稿坐标。
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()

## 用一个带中文回退的系统字体，保证 _draw_string 里写中文也不会变豆腐块
func _cjk_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Hiragino Sans GB"])
	f.allow_system_fallback = true
	return f

func _rebuild() -> void:
	board = Board.generate(seed_value, beginner_board)
	queue_redraw()

## 按当前视口重排棋盘：水平在"视口扣掉右侧信息面板"的区域里居中，
## 垂直在视口中居中。1280×720 下结果为 (510, 360)，与旧版一致。
func _fit_to_viewport() -> void:
	var vp := get_viewport_rect().size
	board_origin = Vector2((vp.x - HUD.PANEL_W) * 0.5 + BOARD_X_BIAS, vp.y * 0.5)
	queue_redraw()

# ================= 对外接口（GameDirector 调用）=================

func set_board_from(controller: GameController) -> void:
	ctl = controller
	board = ctl.st.board
	queue_redraw()

func set_pick_mode(m: int) -> void:
	pick_mode = m
	hover_vertex = -1
	hover_edge = -1
	hover_hex = -1
	queue_redraw()

func set_highlights(vs: Array[int], es: Array[int], hs: Array[int]) -> void:
	highlight_vertices = vs
	highlight_edges = es
	highlight_hexes = hs
	if not highlight_vertices.has(hover_vertex):
		hover_vertex = -1
	if not highlight_edges.has(hover_edge):
		hover_edge = -1
	if not highlight_hexes.has(hover_hex):
		hover_hex = -1
	queue_redraw()

func clear_highlights() -> void:
	set_highlights([], [], [])

func redraw() -> void:
	queue_redraw()

func player_color(pid: int) -> Color:
	return PLAYER_COLORS[pid % PLAYER_COLORS.size()]

# ================= 输入 =================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position)

func _update_hover(pos: Vector2) -> void:
	var v := -1
	var e := -1
	var h := -1
	match pick_mode:
		Pick.VERTEX:
			v = _pick_vertex(pos)
			if not highlight_vertices.has(v):
				v = -1
		Pick.EDGE:
			e = _pick_edge(pos)
			if not highlight_edges.has(e):
				e = -1
		Pick.HEX:
			h = _pick_hex(pos)
			if not highlight_hexes.has(h):
				h = -1
		Pick.ANY:
			var r := _nearest_any(pos)
			v = r[0]
			e = r[1]
	if v != hover_vertex or e != hover_edge or h != hover_hex:
		hover_vertex = v
		hover_edge = e
		hover_hex = h
		queue_redraw()

## 在"顶点 / 边"里挑一个点选目标 —— **顶点优先**：
## 只要落点在某个**已高亮顶点**的命中圈内，就直接判为该顶点，道路完全不参与竞争。
##
## 为什么不用"谁离得更近谁赢"：那是给鼠标设计的。触屏上手指有面积，
## 而道路是从顶点发散的线段 —— 手指沿道路方向偏出去时，到线段的距离几乎不增长，
## 于是"离道路更近"永远成立，玩家点村落十有八九被判成修路（安卓上就是这么暴露的）。
## 改成顶点独占后，村落热区内不会再触发道路。
##
## 代价（可接受）：可建村顶点两旁各让出一段道路热区。但村庄之间必须隔 ≥2 条边，
## 一条边最多只有一端可建村，所以任何一条道路都还留着 ≥37px 的中间段可点。
func _nearest_any(pos: Vector2) -> Array:
	var v := _pick_highlighted_vertex(pos)
	if v >= 0:
		return [v, -1]
	var e := _pick_edge(pos)
	if e >= 0 and highlight_edges.has(e):
		return [-1, e]
	return [-1, -1]

func _handle_click(pos: Vector2) -> void:
	match pick_mode:
		Pick.VERTEX:
			var v := _pick_vertex(pos)
			if v >= 0 and highlight_vertices.has(v):
				vertex_clicked.emit(v)
		Pick.EDGE:
			var e := _pick_edge(pos)
			if e >= 0 and highlight_edges.has(e):
				edge_clicked.emit(e)
		Pick.HEX:
			var h := _pick_hex(pos)
			if h >= 0 and highlight_hexes.has(h):
				hex_clicked.emit(h)
		Pick.ANY:
			var r := _nearest_any(pos)
			if r[0] >= 0:
				vertex_clicked.emit(r[0])
			elif r[1] >= 0:
				edge_clicked.emit(r[1])

func _pick_vertex(pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_VERTEX_R * px_per_unit
	for v in topo.vertices.size():
		var d := _p(topo.vertices[v]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = v
	return best

## 在**已高亮的顶点**里找离 pos 最近的一个（超出命中半径返回 -1）。
## 与 _pick_vertex 的区别：只在可点的顶点里找。它专门服务于 Pick.ANY 的
## "顶点优先"判定 —— 没高亮的顶点周围，道路该能点还是能点。
func _pick_highlighted_vertex(pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_VERTEX_R * px_per_unit
	for v in highlight_vertices:
		var d := _p(topo.vertices[v]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = v
	return best

func _pick_edge(pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_EDGE_R * px_per_unit
	for eid in topo.edges.size():
		var e: Vector2i = topo.edges[eid]
		var d := _dist_to_segment(pos, _p(topo.vertices[e.x]), _p(topo.vertices[e.y]))
		if d < best_d:
			best_d = d
			best = eid
	return best

func _pick_hex(pos: Vector2) -> int:
	var world := (pos - board_origin) / px_per_unit
	var best := -1
	var best_d := 1.05
	for hi in topo.hexes.size():
		var d := topo.hex_center[hi].distance_to(world)
		if d < best_d:
			best_d = d
			best = hi
	return best

func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.0001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ================= 绘制 =================

func _draw() -> void:
	if board == null:
		return
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), _sea_color(), true)
	_draw_coast()
	_draw_hexes()
	_draw_hex_highlights()
	if show_ports:
		_draw_ports()
	if show_vertices:
		_draw_vertices()
	_draw_spot_highlights()
	_draw_tokens()
	_draw_robber()
	_draw_pieces()
	_draw_hover()
	if show_legend:
		_draw_legend()

# ---------------- 地形图例 ----------------

## 左上角的图例：六种地形色卡 + 地形名 + 对应的资源。
## 色卡用小六边形而不是方块 —— 和棋盘上地块的形状一致，一眼能把颜色对上。
func _draw_legend() -> void:
	var terrains := [
		Res.Terrain.FOREST, Res.Terrain.HILLS, Res.Terrain.PASTURE,
		Res.Terrain.FIELDS, Res.Terrain.MOUNTAINS, Res.Terrain.DESERT,
	]
	var total_h := 36.0 + float(terrains.size()) * LEGEND_ROW_H

	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.90)
	box.border_color = Color(0.15, 0.15, 0.15, 0.22)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	draw_style_box(box, Rect2(LEGEND_X, LEGEND_Y, LEGEND_W, total_h))

	draw_string(font, Vector2(LEGEND_X + 12.0, LEGEND_Y + 21.0), "地形图例",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.11, 0.11, 0.11))

	for i in terrains.size():
		var t: int = terrains[i]
		var cy := LEGEND_Y + 38.0 + float(i) * LEGEND_ROW_H + LEGEND_ROW_H * 0.5
		var cx := LEGEND_X + 24.0
		_draw_legend_hex(Vector2(cx, cy), LEGEND_HEX_R, _terrain_color(t), _terrain_texture(t))

		var r: int = Res.TERRAIN_RES.get(t, -1)
		var label: String = Res.TERRAIN_CN[t] + (" · " + Res.R_NAMES_CN[r] if r >= 0 else " · 无产出")
		draw_string(font, Vector2(cx + 20.0, cy + 4.5), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.13, 0.13, 0.13))

func _draw_legend_hex(c: Vector2, r: float, col: Color, tex: Texture2D = null) -> void:
	var pts := PackedVector2Array()
	for k in 6:
		var ang := deg_to_rad(60.0 * float(k) + 30.0)
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	if tex != null:
		draw_polygon(pts, _white_colors(6), _hex_uvs(pts, r), tex)
	else:
		draw_colored_polygon(pts, col)
	var o := pts.duplicate()
	o.append(pts[0])
	draw_polyline(o, Color(0.15, 0.15, 0.15, 0.45), 1.2, true)

func _draw_coast() -> void:
	var k := 1.0 + COAST_BAND
	for hi in topo.hexes.size():
		draw_colored_polygon(_hex_poly(hi, k), _coast_color())

func _draw_hexes() -> void:
	var stroke := Color(0.15, 0.15, 0.15, 0.45)
	for hi in topo.hexes.size():
		var t: int = board.hex_terrain[hi]
		var poly := _hex_poly(hi)
		var tex := _terrain_texture(t)
		if tex != null:
			# draw_polygon 带 UV：贴图被裁成六边形，
			# 原图白底的四个角自然落在六边形之外，不用给图加透明通道。
			draw_polygon(poly, _white_colors(6), _hex_uvs(poly, px_per_unit), tex)
		else:
			draw_colored_polygon(poly, _terrain_color(t))
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, stroke, 1.5, true)

func _white_colors(n: int) -> PackedColorArray:
	var c := PackedColorArray()
	for i in n:
		c.append(Color.WHITE)
	return c

## 六边形各顶点对应的贴图 UV。
## 六边形（pointy-top）外接矩形宽 sqrt(3)*R、高 2R，把它映到贴图中间
## (1 - 2*TEX_INSET) 的区域，即往里收边裁掉白边与水印。
## radius 单独传：棋盘地块和图例小色卡的半径不一样。
##
## 圆心必须自己从多边形算，不能让调用方传 ——
## 多边形顶点是**像素坐标**，而 BoardTopology.hex_center 是**世界坐标**，
## 两者混用会得到离谱的 UV，采样全落在贴图白边上（渲染出来一片发白的纯色）。
func _hex_uvs(pts: PackedVector2Array, radius: float) -> PackedVector2Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in pts:
		mn.x = minf(mn.x, p.x)
		mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x)
		mx.y = maxf(mx.y, p.y)
	var c := (mn + mx) * 0.5
	var w := sqrt(3.0) * radius
	var h := 2.0 * radius
	var span := 1.0 - 2.0 * TEX_INSET
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(Vector2(
			(p.x - c.x) / w * span + 0.5,
			(p.y - c.y) / h * span + 0.5))
	return uvs

func _draw_tokens() -> void:
	for hi in topo.hexes.size():
		var n: int = board.hex_number[hi]
		if n == 0:
			continue
		var c := _p(topo.hex_center[hi])
		var r := TOKEN_R * px_per_unit
		var hot := (n == 6 or n == 8)
		var ink := Color(0.753, 0.224, 0.169) if hot else Color(0.10, 0.10, 0.10)

		draw_circle(c, r, Color(0.969, 0.957, 0.925))
		draw_arc(c, r, 0.0, TAU, 48, Color(0.15, 0.15, 0.15, 0.35), 1.5, true)

		var fs := int(r * 1.05)
		var txt := str(n)
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.30),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

		var k: int = Res.PIPS.get(n, 0)
		if k > 0:
			var rr := r * 0.085
			var gap := r * 0.30
			var x0 := c.x - (k - 1) * gap * 0.5
			for i in k:
				draw_circle(Vector2(x0 + i * gap, c.y + r * 0.50), rr, ink)

func _draw_ports() -> void:
	for eid in board.port_edges:
		var e: Vector2i = topo.edges[eid]
		var mid: Vector2 = (topo.vertices[e.x] + topo.vertices[e.y]) * 0.5
		var pos := _p(mid + mid.normalized() * PORT_OUT)
		var ptype: int = board.vertex_port[e.x]

		var label := "3:1"
		var ink := Color(0.10, 0.10, 0.10)
		var box := _port_box.duplicate() as StyleBoxFlat
		if ptype != Res.Port.GENERIC_3:
			# 仅靠底色区分 2:1 港口的资源不明显，直接写明资源：木x2 : 1
			label = "%sx2 : 1" % Res.R_NAMES_CN[ptype - 1].left(1)
			var rc := _res_color(ptype - 1).darkened(0.35)
			box.bg_color = rc
			box.border_color = Color(1, 1, 1, 0.75)
			ink = Color(1, 1, 1)
		var fs := int(px_per_unit * 0.28 * 0.60)
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var h := px_per_unit * 0.28
		var w := maxf(px_per_unit * 0.54, ts.x + h * 0.55)
		var rect := Rect2(pos - Vector2(w, h) * 0.5, Vector2(w, h))
		draw_style_box(box, rect)

		draw_string(font, pos + Vector2(-ts.x * 0.5, fs * 0.34),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)

func _draw_vertices() -> void:
	var r := VERTEX_R * px_per_unit
	for v in topo.vertices.size():
		var c := _p(topo.vertices[v])
		draw_circle(c, r, Color(1, 1, 1, 0.85))
		draw_arc(c, r, 0.0, TAU, 12, Color(0.15, 0.15, 0.15, 0.45), 1.0, true)

func _draw_robber() -> void:
	var c := _p(topo.hex_center[board.robber_hex])
	var r := ROBBER_R * px_per_unit
	draw_circle(c + Vector2(0, 2), r * 1.06, Color(0, 0, 0, 0.22))
	draw_circle(c, r, Color(0.227, 0.227, 0.227))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.45), 1.5, true)

# ---------------- 高亮 ----------------

## 可落子位置的提示色。
## 用青色而不是绿色 / 白色，原因是实测踩出来的：
##   · 绿色：地形里森林、牧场本身就是绿的，高亮几乎看不见
##   · 白色：白色高亮压在浅色地块（沙漠 / 麦田）上几乎消失
## 现在四个玩家色是蓝 / 红 / 橙 / 绿，青色在六种地形色和四个玩家色里都不出现，
## 配深色描边后对比度最高。
const HL_COLOR := Color(0.0, 0.83, 1.0, 0.96)
const HL_SHADOW := Color(0.02, 0.10, 0.14, 0.60)

func _draw_hex_highlights() -> void:
	if highlight_hexes.is_empty():
		return
	for h in highlight_hexes:
		var poly := _hex_poly(h, 0.97)
		var o := poly.duplicate()
		o.append(poly[0])
		draw_polyline(o, HL_SHADOW, 7.0, true)
		draw_polyline(o, HL_COLOR, 4.0, true)

func _draw_spot_highlights() -> void:
	for eid in highlight_edges:
		var e: Vector2i = topo.edges[eid]
		var a := _p(topo.vertices[e.x])
		var b := _p(topo.vertices[e.y])
		draw_line(a, b, HL_SHADOW, ROAD_W * px_per_unit + 9.0, true)
		draw_line(a, b, HL_COLOR, ROAD_W * px_per_unit + 5.0, true)
	# 顶点高亮画大一点：它就是"可建村按钮"的视觉提示。
	# 画得比热区小太多，玩家会以为自己没点中，进而在旁边乱戳（触屏上尤其明显）。
	for v in highlight_vertices:
		var c := _p(topo.vertices[v])
		var r := 0.20 * px_per_unit
		draw_circle(c, r + 3.0, HL_SHADOW)
		draw_circle(c, r, HL_COLOR)
		draw_circle(c, r * 0.45, Color(1, 1, 1, 0.85))

func _draw_hover() -> void:
	var hot := Color(1.0, 0.78, 0.15)
	if hover_vertex >= 0:
		var c := _p(topo.vertices[hover_vertex])
		var hr := 0.26 * px_per_unit
		draw_circle(c, hr, Color(hot.r, hot.g, hot.b, 0.85))
		draw_arc(c, hr, 0.0, TAU, 24, Color(0.35, 0.25, 0.0, 0.8), 2.0, true)
	if hover_edge >= 0:
		var e: Vector2i = topo.edges[hover_edge]
		draw_line(_p(topo.vertices[e.x]), _p(topo.vertices[e.y]),
			Color(hot.r, hot.g, hot.b, 0.9), ROAD_W * px_per_unit + 2.0, true)
	if hover_hex >= 0:
		var poly := _hex_poly(hover_hex, 0.96)
		var o := poly.duplicate()
		o.append(poly[0])
		draw_polyline(o, Color(hot.r, hot.g, hot.b, 0.95), 4.0, true)

# ---------------- 棋子 ----------------

func _draw_pieces() -> void:
	if ctl == null:
		return
	var st := ctl.st
	# 路在最下层
	for p in st.players:
		var col := player_color(p.id)
		for eid in p.roads:
			var e: Vector2i = topo.edges[eid]
			var a := _p(topo.vertices[e.x])
			var b := _p(topo.vertices[e.y])
			draw_line(a, b, Color(0.0, 0.0, 0.0, 0.40), ROAD_W * px_per_unit + 3.0, true)
			draw_line(a, b, col, ROAD_W * px_per_unit, true)
	# 村庄，再城市
	for p in st.players:
		for v in p.settlements:
			_draw_house(_p(topo.vertices[v]), player_color(p.id), 0.30)
	for p in st.players:
		for v in p.cities:
			_draw_house(_p(topo.vertices[v]), player_color(p.id), 0.44)

## 一栋小房子：矩形主体 + 三角屋顶，整体以顶点为中心
func _draw_house(c: Vector2, col: Color, s: float) -> void:
	var w := s * px_per_unit
	var body_h := w * 0.46
	var roof_h := w * 0.60
	var total := body_h + roof_h
	var top := -total * 0.5
	var edge := Color(0.0, 0.0, 0.0, 0.55)

	var body := PackedVector2Array([
		c + Vector2(-w * 0.5, top + roof_h),
		c + Vector2(w * 0.5, top + roof_h),
		c + Vector2(w * 0.5, top + total),
		c + Vector2(-w * 0.5, top + total),
	])
	var roof := PackedVector2Array([
		c + Vector2(-w * 0.64, top + roof_h),
		c + Vector2(w * 0.64, top + roof_h),
		c + Vector2(0.0, top),
	])

	draw_colored_polygon(body, col)
	draw_colored_polygon(roof, col.darkened(0.22))
	var bo := body.duplicate(); bo.append(body[0])
	var ro := roof.duplicate(); ro.append(roof[0])
	draw_polyline(bo, edge, 1.5, true)
	draw_polyline(ro, edge, 1.5, true)

# ================= 工具 =================

func _p(v: Vector2) -> Vector2:
	return board_origin + v * px_per_unit

func _hex_poly(hi: int, k: float = 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var c: Vector2 = topo.hex_center[hi]
	for i in 6:
		pts.append(_p(c + HexGrid.hex_corner_offset(i) * k))
	return pts

func _sea_color() -> Color:
	return Color(0.557, 0.792, 0.902)

func _coast_color() -> Color:
	return Color(0.914, 0.863, 0.710)

func _terrain_color(t: int) -> Color:
	match t:
		Res.Terrain.FOREST:
			return Color(0.247, 0.478, 0.310)
		Res.Terrain.HILLS:
			return Color(0.690, 0.416, 0.231)
		Res.Terrain.PASTURE:
			return Color(0.549, 0.757, 0.322)
		Res.Terrain.FIELDS:
			return Color(0.878, 0.725, 0.247)
		Res.Terrain.MOUNTAINS:
			return Color(0.541, 0.561, 0.596)
		_:
			return Color(0.902, 0.843, 0.659)

func _res_color(r: int) -> Color:
	match r:
		Res.R.WOOD:
			return Color(0.247, 0.478, 0.310)
		Res.R.BRICK:
			return Color(0.690, 0.416, 0.231)
		Res.R.WOOL:
			return Color(0.549, 0.757, 0.322)
		Res.R.GRAIN:
			return Color(0.878, 0.725, 0.247)
		_:
			return Color(0.541, 0.561, 0.596)
