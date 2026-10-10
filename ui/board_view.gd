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
## 左上角是否提供"?"图例按钮
@export var show_legend: bool = true
## 图例当前是否展开。**默认收起**：那块地方在手机上很金贵，
## 但新玩家确实需要它认地形，所以收进一个一按就开的按钮里。
@export var legend_open: bool = false
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
## 港口牌：牌心到**这条边的外法线方向**上 PORT_OUT 处的距离；牌子是边长 PORT_BOX 的方牌。
## 牌面只有一个字（"?" 或资源短名），所以比早先"木x2 : 1"那种长条牌小得多。
const PORT_OUT := 0.46
const PORT_BOX := 0.32
const ROAD_W := 0.13
## 顶点命中半径（世界单位）。**要按触摸屏的尺寸定，不能按鼠标定**：
## 手指接触面积约 40~50px，旧值 0.26×62 ≈ 16px 在手机上几乎点不准，
## 于是"想建村"时手指稍一偏移就落进旁边道路的热区里。
## 0.40×62 ≈ 25px。敢给这么大是有依据的：官方规则要求村庄之间相隔 ≥2 条边，
## 所以**同一条边的两端不可能同时是可建村/可升城的顶点**，
## 把顶点热区加大，绝不会把某条道路的两头同时堵死（最坏也留 ~37px 可点中段）。
const PICK_VERTEX_R := 0.40
const PICK_EDGE_R := 0.18        ## 边的命中半径（点到线段距离）

## 左上角"?"按钮与展开后图例面板的版式。
## 位置**不写死坐标**：先让开安全区（圆角 / 挖孔），再按按钮外缘对齐 ——
## 手机横屏时挖孔常落在左侧，写死 14px 会让按钮正好被摄像头压住。
const HELP_R := 17.0        ## 按钮半径
const HELP_PAD := 10.0      ## 按钮外缘到安全区内侧的间距
const LEGEND_GAP := 8.0     ## 按钮下缘到图例面板的间距

## 图例面板内部版式。**宽度不写死**：由两列文字的实测宽度算出来
## （见 legend_size()）—— 换字体或改文案时写死的宽度会把文字悄悄挤出面板，
## 算出来测试才断言得住"面板不跑出视口"。
const LEGEND_PAD := 12.0        ## 面板四周内边距
const LEGEND_ROW_H := 31.0      ## 行高（两列共用，保证两列横线对齐）
const LEGEND_HEX_R := 11.0      ## 地形色卡半径
const LEGEND_COL_GAP := 18.0    ## 两列之间的空隙
const LEGEND_HEX_GAP := 8.0     ## 色卡右缘 -> 地形名的间距
const LEGEND_NAME_GAP := 10.0   ## 卡名右缘 -> 花费的间距
const LEGEND_HEAD := 38.0       ## 面板上缘 -> 第一行行心的距离（含栏目名）
const LEGEND_HDR_DY := 22.0     ## 栏目名基线相对面板上缘的下移量
const LEGEND_FS := 12           ## 行文字号

## 两列的栏目名
const LEGEND_HDR_TERRAIN := "地形图例"
const LEGEND_HDR_COST := "建造花费"
## 地形色卡的排列顺序（与棋盘上常见度无关，按资源种类走，方便和下面一列对照）
const LEGEND_TERRAINS := [
	Res.Terrain.FOREST, Res.Terrain.HILLS, Res.Terrain.PASTURE,
	Res.Terrain.FIELDS, Res.Terrain.MOUNTAINS, Res.Terrain.DESERT,
]

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
var _help_hover := false        ## 鼠标/手指是否悬在左上角"?"按钮上
## 缓存的安全区。`_draw()` 每帧都要用（画"?"按钮），而 SafeArea.insets() 内部会
## 调 DisplayServer —— 那是系统调用，不能每帧问一次。只在 ready 和视口变化时刷新。
var _ins := Vector4.ZERO

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
	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()

## 用一个带中文回退的系统字体，保证 _draw_string 里写中文也不会变豆腐块
func _cjk_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Hiragino Sans GB"])
	f.allow_system_fallback = true
	return f

func _rebuild() -> void:
	board = Board.generate(seed_value, beginner_board)
	queue_redraw()

## 视口变了就重算安全区 + 重排棋盘（手机转屏、窗口拉大都会走这里）
func _on_viewport_changed() -> void:
	_ins = SafeArea.insets()
	_fit_to_viewport()

## 按当前视口重排棋盘：水平在"视口扣掉右侧信息面板"的区域里居中，
## 垂直在视口中居中。1280×720 桌面下结果为 (510, 360)，与旧版一致。
func _fit_to_viewport() -> void:
	board_origin = board_origin_for(get_viewport_rect().size, _ins)
	queue_redraw()

## 棋盘原点 = 「视口扣掉右侧面板、再扣掉四周安全区」这块区域的正中，
## 再加上设计稿刻意右移的量（给左上角按钮腾地方）。
##
## 抽成静态纯函数是为了能 headless 单测：真机上视口 / 挖孔都不可控，
## 只有把算式拆出来，才守得住"1280×720 桌面下仍必须是 (510, 360)"。
static func board_origin_for(vp: Vector2, ins: Vector4) -> Vector2:
	var left := ins.x
	var right := vp.x - HUD.PANEL_W
	return Vector2((left + right) * 0.5 + BOARD_X_BIAS, (ins.y + vp.y - ins.w) * 0.5)

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
		if _hit_legend(event.position):
			# 光标在图例面板上：面板是不透明的，底下的地块没必要跟着亮
			_set_help_hover(false)
			_clear_hover()
			return
		_set_help_hover(_hit_help(event.position))
		_update_hover(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hit_help(event.position):
			# 先吃掉这次点击再 return：否则按当前 pick 模式它还会被当成一次落子。
			# （左上角离棋盘很远，出事概率低，但"点帮助却建了座村庄"这种 bug 一次就够呛。）
			legend_open = not legend_open
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		if _hit_legend(event.position):
			# 面板比原来的图例宽，会盖住棋盘最左边一点点。既然视觉上盖住了，
			# 就必须在交互上也盖住 —— 否则点在图例文字上，底下那块地照样响应，
			# 又变成"点帮助却建了座村庄"（这次是点了图例本体）。
			get_viewport().set_input_as_handled()
			return
		_handle_click(event.position)

## 清掉棋盘上的 hover 高亮（光标移到浮层上时用）
func _clear_hover() -> void:
	if hover_vertex != -1 or hover_edge != -1 or hover_hex != -1:
		hover_vertex = -1
		hover_edge = -1
		hover_hex = -1
		queue_redraw()

func _set_help_hover(v: bool) -> void:
	if v != _help_hover:
		_help_hover = v
		queue_redraw()

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
		_draw_help_button()
		if legend_open:
			_draw_legend()

# ---------------- 左上角"?"按钮 ----------------

## 折叠态是一个"?"圆钮（问号 = 这里能点开说明），展开后变成"×"（再点收起）。
## 位置跟着安全区走，手机上不会被圆角或挖孔压住。
func help_center() -> Vector2:
	return Vector2(_ins.x + HELP_PAD + HELP_R, _ins.y + HELP_PAD + HELP_R)

## 命中圈比视觉半径大一圈：手指是一块面，按视觉尺寸判会"看着点中了却没反应"
func _hit_help(pos: Vector2) -> bool:
	if not show_legend:
		return false
	return pos.distance_to(help_center()) <= HELP_R + 7.0

func _draw_help_button() -> void:
	var c := help_center()
	draw_circle(c + Vector2(0.0, 1.5), HELP_R, Color(0.0, 0.0, 0.0, 0.16))
	draw_circle(c, HELP_R,
		Color(0.878, 0.918, 0.973) if _help_hover else Color(1, 1, 1, 0.94))
	draw_arc(c, HELP_R, 0.0, TAU, 40, Color(0.15, 0.15, 0.15, 0.45), 1.5, true)
	var glyph := "×" if legend_open else "?"
	var fs := 21
	var ts := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.34), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.11, 0.11, 0.11))

# ---------------- 图例 ----------------

## 左上角展开的面板，两列并排：
##   左列「地形图例」—— 六种地形的小六边形色卡 + 地形名 + 产出的资源；
##   右列「建造花费」—— 修路 / 村落 / 城市 / 发展卡，各自要花哪些资源。
##
## 色卡用小六边形而不是方块 —— 和棋盘上地块的形状一致，一眼能把颜色对上。
## 花费**直接从 Res.COST_* 读**，不手抄一遍：规则改了图例会跟着改，
## 不会留下一份"看着像真的"的过期说明书（test_legend.gd 会核对这一点）。

## 面板矩形。抽出来是为了三处共用：绘制、命中判定（吃点击）、单测。
func legend_rect() -> Rect2:
	var c := help_center()
	return Rect2(Vector2(c.x - HELP_R, c.y + HELP_R + LEGEND_GAP), legend_size())

## 光标 / 手指是否落在展开的面板上。面板浮在棋盘之上，落在它上面的点击
## 必须由面板自己吃掉，否则底下那块地、那条路照样会响应。
func _hit_legend(pos: Vector2) -> bool:
	return show_legend and legend_open and legend_rect().has_point(pos)

## 一行"修路 / 村落 / 城市 / 发展卡 -> 花费"的数据。
func _legend_cost_rows() -> Array:
	return [
		["修路", Res.COST_ROAD],
		["村落", Res.COST_SETTLEMENT],
		["城市", Res.COST_CITY],
		["发展卡", Res.COST_DEV],
	]

func _legend_terrain_label(t: int) -> String:
	var r: int = Res.TERRAIN_RES.get(t, -1)
	return Res.TERRAIN_CN[t] + (" · " + Res.R_NAMES_CN[r] if r >= 0 else " · 无产出")

## 花费字典 -> "木1 砖1 羊1 麦1"。资源按 R 枚举顺序排，图例与 HUD 用同一套短名。
func _legend_cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for r in Res.R_COUNT:
		if cost.has(r):
			parts.append("%s%d" % [UIPalette.RES_SHORT[r], cost[r]])
	return " ".join(parts)

func _legend_text_w(s: String, fs: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x

## 两列的宽度：左列 = 色卡 + 间距 + 最长地形标签；右列 = 最长的"卡名 + 花费"。
## 这里的间距和 _draw_legend 里用的是同一批常量 —— 量出来多宽就画多宽，
## 不然会出现"算宽时按 8px、画图时按 12px"这种只在边缘显形的错位。
func _legend_col_widths() -> Vector2:
	var terrain_w := 0.0
	for t in LEGEND_TERRAINS:
		terrain_w = maxf(terrain_w, _legend_text_w(_legend_terrain_label(t), LEGEND_FS))
	var col_a := LEGEND_HEX_R * 2.0 + LEGEND_HEX_GAP + terrain_w

	var cost_w := 0.0
	for row in _legend_cost_rows():
		cost_w = maxf(cost_w, _legend_text_w(_legend_cost_text(row[1]), LEGEND_FS))
	var col_b := _legend_name_w() + LEGEND_NAME_GAP + cost_w
	return Vector2(col_a, col_b)

## 右列里最长的卡名（"发展卡"）。花费要从它后面统一对齐开始，逐行才不会参差。
func _legend_name_w() -> float:
	var w := 0.0
	for row in _legend_cost_rows():
		w = maxf(w, _legend_text_w(row[0], LEGEND_FS))
	return w

## 面板尺寸。宽度由内容实测得出（见 _legend_col_widths），
## 高度按行数堆叠，两列取行数多的那列。
func legend_size() -> Vector2:
	var cols := _legend_col_widths()
	var rows: int = maxi(LEGEND_TERRAINS.size(), _legend_cost_rows().size())
	return Vector2(
		LEGEND_PAD * 2.0 + cols.x + LEGEND_COL_GAP + cols.y,
		LEGEND_HEAD + float(rows) * LEGEND_ROW_H + LEGEND_PAD)

func _draw_legend() -> void:
	var rect := legend_rect()
	var cols := _legend_col_widths()
	var lx := rect.position.x
	var ly := rect.position.y
	var ink := Color(0.11, 0.11, 0.11)
	var body := Color(0.13, 0.13, 0.13)

	var box := StyleBoxFlat.new()
	# 面板会浮在棋盘左上角那一小块上（两列比原来一列宽，1280×720 下右缘到 282，
	# 而棋盘最左边那个地块的左缘在 242）。不透明度给到 0.98 —— 0.94 时底下的
	# 港口牌会透出来变成一层"重影"，比直接盖住更难看。
	box.bg_color = Color(1, 1, 1, 0.98)
	box.border_color = Color(0.15, 0.15, 0.15, 0.22)
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	# 展开时才浮在棋盘上，加一点投影把它和底下的海色 / 地块分开
	box.shadow_color = Color(0, 0, 0, 0.20)
	box.shadow_size = 8
	draw_style_box(box, rect)

	var ax := lx + LEGEND_PAD
	var bx := lx + LEGEND_PAD + cols.x + LEGEND_COL_GAP
	draw_string(font, Vector2(ax, ly + LEGEND_HDR_DY), LEGEND_HDR_TERRAIN,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	draw_string(font, Vector2(bx, ly + LEGEND_HDR_DY), LEGEND_HDR_COST,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)

	# ---- 左列：地形 -> 资源 ----
	for i in LEGEND_TERRAINS.size():
		var t: int = LEGEND_TERRAINS[i]
		var cy := _legend_row_y(ly, i)
		var hx := ax + LEGEND_HEX_R
		_draw_legend_hex(Vector2(hx, cy), LEGEND_HEX_R, _terrain_color(t), _terrain_texture(t))
		draw_string(font, Vector2(hx + LEGEND_HEX_R + LEGEND_HEX_GAP, cy + 4.5),
			_legend_terrain_label(t), HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FS, body)

	# ---- 右列：建造花费 ----
	var rows := _legend_cost_rows()
	var cost_x := bx + _legend_name_w() + LEGEND_NAME_GAP
	for i in rows.size():
		var row: Array = rows[i]
		var cy := _legend_row_y(ly, i)
		draw_string(font, Vector2(bx, cy + 4.5), row[0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FS, ink)
		draw_string(font, Vector2(cost_x, cy + 4.5), _legend_cost_text(row[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, LEGEND_FS, body)

## 第 i 行的行心 y。两列共用，保证横向上两列互相看齐。
func _legend_row_y(top: float, i: int) -> float:
	return top + LEGEND_HEAD + float(i) * LEGEND_ROW_H + LEGEND_ROW_H * 0.5

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

## 港口牌中心 = 「这条边的中点」沿**该边的外法线**外推 PORT_OUT。
##
## ⚠️ 不能用"棋盘中心 -> 边中点"的**径向**代替法线。两者只有在边恰好垂直于半径时
## 才重合；岛屿外缘那 9 条港口边的实测夹角是 23.4° 或 49.1°，按径向摆会让牌子
## 从边中线偏出去最多 0.38 世界单位（62px/单位下 ≈ 24px）——
## 看上去就是"港口牌没对准它那条边"。tools/probe_ports.gd 量过这个偏差。
##
## 外法线 = 边的垂线里背离棋盘中心的那一条。港口边全在岛屿外缘，
## 用径向点乘判个正负就够，不必去查每条边归属哪个地块。
func port_marker_pos(eid: int) -> Vector2:
	var e: Vector2i = topo.edges[eid]
	var a: Vector2 = topo.vertices[e.x]
	var b: Vector2 = topo.vertices[e.y]
	var mid: Vector2 = (a + b) * 0.5
	var n := Vector2(-(b.y - a.y), b.x - a.x).normalized()
	if n.dot(mid) < 0.0:
		n = -n
	return _p(mid + n * PORT_OUT)

## 港口牌上写什么：通用 3:1 港只写「?」，指定资源港只写一个字的资源短名。
## 比例（3:1 / 2:1）老玩家都知道，写在牌上又挤又占地方，省掉。
## 短名直接取 HUD / 图例同款的 `UIPalette.RES_SHORT`，不另抄一份。
func port_label(ptype: int) -> String:
	if ptype == Res.Port.GENERIC_3:
		return "?"
	return UIPalette.RES_SHORT[ptype - 1]

func _draw_ports() -> void:
	var side := px_per_unit * PORT_BOX
	for eid in board.port_edges:
		var e: Vector2i = topo.edges[eid]
		var ptype: int = board.vertex_port[e.x]
		var pos := port_marker_pos(eid)

		var ink := Color(0.10, 0.10, 0.10)
		var box := _port_box.duplicate() as StyleBoxFlat
		if ptype != Res.Port.GENERIC_3:
			# 底色仍按资源上色：牌面只有一个字时，底色是最快的识别通道
			box.bg_color = _res_color(ptype - 1).darkened(0.35)
			box.border_color = Color(1, 1, 1, 0.75)
			ink = Color(1, 1, 1)

		var label := port_label(ptype)
		var fs := int(side * 0.66)
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_style_box(box, Rect2(pos - Vector2(side, side) * 0.5, Vector2(side, side)))
		draw_string(font, pos + Vector2(-ts.x * 0.5, fs * 0.36),
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
