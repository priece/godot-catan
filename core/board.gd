class_name Board
extends RefCounted

## 岛屿生成：地形分布、数字 token、港口。
##
## 地形：洗牌后随机摆放（官方做法）。
##       ⚠️ **官方没有"相同地形/资源不能相邻"的限制**，不要再加这条。
## 数字：官方 Almanac 对"数字完全随机摆放"有两条硬要求 ——
##       · 红色数字 6 和 8 不能相邻（两者各 5 pip，挨在一起会变成一次性决定胜负的产区）
##       · 任意两个相邻地块不能是同一个数字
##       本实现两条都守（见 _place_numbers）。
## 同一 seed 必然生成同一张棋盘，可复现。
##
## 港口：9 个（4 个通用 3:1 + 5 个指定资源 2:1），均匀分布在海岸边的 9 条沿海边上，
## 港口所在边的两个端点即为可使用该港口的顶点。

var topo: BoardTopology

var hex_terrain: Array[int] = []
var hex_number: Array[int] = []        ## 0 表示无数字（沙漠）
var robber_hex: int = 0
var vertex_port: Array[int] = []       ## 长度 54，-1 表示无港口
var port_edges: Array[int] = []        ## 9 条港口所在的海岸边

var seed_used: int = 0
var beginner_mode: bool = false

static func generate(p_seed: int, beginner: bool = false) -> Board:
	var b := Board.new()
	b.topo = BoardTopology.instance()
	b.seed_used = p_seed
	b.beginner_mode = beginner
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	b._place_terrain(rng)
	b._place_numbers(rng, beginner)
	b._place_ports(rng)
	return b

# ---------------- 生成 ----------------

## 地形摆放：洗牌后随机铺开 —— 就是官方规则书的做法。
##
## ⚠️ 曾经这里还加了"相同地形不相邻"的拒绝采样（洗牌 + 不行就重试 2000 次）。
## 那条限制**不是官方规则**（同资源相邻在官方可变布局里完全允许），而且
## 随机命中率极低、2000 次里大概率全部失败，失败后还会静默保留非法结果 ——
## 既不符合规则，又是坏实现。已经删掉，别再往回加。
func _place_terrain(rng: RandomNumberGenerator) -> void:
	hex_terrain.clear()
	for t in Res.TERRAIN_COUNTS:
		for i in Res.TERRAIN_COUNTS[t]:
			hex_terrain.append(t)
	_shuffle(hex_terrain, rng)

## 数字摆放。官方 Almanac 对"完全随机摆放数字 token"的两条硬要求：
##   1. 红色数字 6 和 8 不能相邻
##   2. 任意两个相邻地块不能是同一个数字
## beginner=true（均衡布局）两条都守；false（随机布局）只守第 1 条 ——
## 第 1 条是任何摆放方式都不能破的，第 2 条放宽是为了留出"更野"的图。
##
## 用拒绝采样：单次命中率约 2%，3000 次几乎必然成功。
## 真失败必须 push_error 报出来，绝不能像原来那样静默留下非法盘。
func _place_numbers(rng: RandomNumberGenerator, beginner: bool) -> void:
	hex_number.resize(topo.hexes.size())
	hex_number.fill(0)

	var land: Array[int] = []
	for hi in spiral_order(topo):
		if hex_terrain[hi] != Res.Terrain.DESERT:
			land.append(hi)

	var ok := false
	for attempt in 3000:
		var nums := Res.NUMBER_TOKENS.duplicate()
		_shuffle(nums, rng)
		for i in land.size():
			hex_number[land[i]] = nums[i]
		if not _has_number_clash(beginner):
			ok = true
			break
	if not ok:
		push_error("数字摆放失败：没能满足「6/8 不相邻%s」" % "、同数字不相邻" if beginner else "")

	robber_hex = 0
	for hi in topo.hexes.size():
		if hex_terrain[hi] == Res.Terrain.DESERT:
			robber_hex = hi
			break

func _place_ports(rng: RandomNumberGenerator) -> void:
	vertex_port.resize(topo.vertices.size())
	vertex_port.fill(-1)

	var cycle := boundary_cycle(topo)
	if cycle.size() != 30:
		push_error("海岸边数量异常: %d (期望 30)" % cycle.size())
		return

	var picks: Array[int] = []
	for i in Res.PORT_COUNT:
		picks.append(int(round(float(i) * float(cycle.size()) / float(Res.PORT_COUNT))) % cycle.size())

	var types: Array[int] = [
		Res.Port.GENERIC_3, Res.Port.GENERIC_3, Res.Port.GENERIC_3, Res.Port.GENERIC_3,
		Res.Port.WOOD_2, Res.Port.BRICK_2, Res.Port.WOOL_2, Res.Port.GRAIN_2, Res.Port.ORE_2,
	]
	_shuffle(types, rng)

	port_edges = []
	for i in picks.size():
		var eid: int = cycle[picks[i]]
		port_edges.append(eid)
		var e: Vector2i = topo.edges[eid]
		vertex_port[e.x] = types[i]
		vertex_port[e.y] = types[i]

# ---------------- 查询 ----------------

## 掷出该点数时产出的地块（排除被强盗封锁的）
func producing_hexes(number: int) -> Array[int]:
	var out: Array[int] = []
	for hi in topo.hexes.size():
		if hex_number[hi] == number and hi != robber_hex:
			out.append(hi)
	return out

func hex_resource(hi: int) -> int:
	return Res.TERRAIN_RES.get(hex_terrain[hi], -1)

## 某顶点能产出的资源种类
func vertex_resource_kinds(v: int) -> Array[int]:
	var out: Array[int] = []
	for hi in topo.vertex_hexes[v]:
		var r: int = hex_resource(hi)
		if r >= 0 and not out.has(r):
			out.append(r)
	return out

## 某顶点连通港口的交易比例：[付出张数, 指定资源(-1 为通用)]
func vertex_port_ratio(v: int) -> Array:
	var p: int = vertex_port[v]
	if p < 0:
		return []
	return Res.port_ratio(p)

# ---------------- 自检 ----------------

## 自检。
## check_robber 只在"刚生成、还没开局"时为 true —— 一旦开局，
## 强盗会被玩家正常移走，再要求它在沙漠上就成了误报。
func self_check(check_robber: bool = true) -> Array[String]:
	var errs: Array[String] = []
	if hex_terrain.size() != topo.hexes.size():
		errs.append("terrain array size mismatch")

	var tc := {}
	for t in hex_terrain:
		tc[t] = tc.get(t, 0) + 1
	for t in Res.TERRAIN_COUNTS:
		if tc.get(t, 0) != Res.TERRAIN_COUNTS[t]:
			errs.append("terrain %s count = %d, expected %d" % [Res.TERRAIN_NAMES[t], tc.get(t, 0), Res.TERRAIN_COUNTS[t]])

	var nc := {}
	for hi in topo.hexes.size():
		if hex_terrain[hi] == Res.Terrain.DESERT:
			if hex_number[hi] != 0:
				errs.append("desert hex %d has number %d" % [hi, hex_number[hi]])
			continue
		var n: int = hex_number[hi]
		if n == 0:
			errs.append("non-desert hex %d has no number" % hi)
		nc[n] = nc.get(n, 0) + 1
	var expected_nc := {}
	for n in Res.NUMBER_TOKENS:
		expected_nc[n] = expected_nc.get(n, 0) + 1
	for n in expected_nc:
		if nc.get(n, 0) != expected_nc[n]:
			errs.append("number %d count = %d, expected %d" % [n, nc.get(n, 0), expected_nc[n]])

	if check_robber and hex_terrain[robber_hex] != Res.Terrain.DESERT:
		errs.append("robber not on desert")

	# 官方硬规则：6 / 8 不能相邻（均衡模式下还要求相邻不同数字）。
	# 放进自检是为了"万一坏了能被发现"，而不是像以前那样静默出坏图。
	var strict := beginner_mode
	for hi in topo.hexes.size():
		var num: int = hex_number[hi]
		if num == 0:
			continue
		for d in HexGrid.DIRS:
			var n: Vector2i = topo.hexes[hi] + d
			if not topo.hex_index.has(n):
				continue
			var nj: int = topo.hex_index[n]
			var other: int = hex_number[nj]
			if other == 0 or nj < hi:
				continue
			if (num == 6 and other == 8) or (num == 8 and other == 6):
				errs.append("红色数字相邻：地块 %d(6) 与 %d(8)" % [hi, nj] if num == 6 else "红色数字相邻：地块 %d(8) 与 %d(6)" % [hi, nj])
			elif strict and other == num:
				errs.append("相邻地块同数字：%d 与 %d 都是 %d" % [hi, nj, num])

	if port_edges.size() != Res.PORT_COUNT:
		errs.append("port count = %d, expected %d" % [port_edges.size(), Res.PORT_COUNT])

	# 每个港口占 2 个顶点：4 个通用港 -> 8 个顶点；5 个指定港 -> 每种 2 个顶点
	var ported := 0
	var counts := {}
	for v in vertex_port:
		if v >= 0:
			ported += 1
			counts[v] = counts.get(v, 0) + 1
	if ported != Res.PORT_COUNT * 2:
		errs.append("vertices with port = %d, expected %d" % [ported, Res.PORT_COUNT * 2])
	if counts.get(Res.Port.GENERIC_3, 0) != 8:
		errs.append("generic 3:1 port vertices = %d, expected 8" % counts.get(Res.Port.GENERIC_3, 0))
	for pr in [Res.Port.WOOD_2, Res.Port.BRICK_2, Res.Port.WOOL_2, Res.Port.GRAIN_2, Res.Port.ORE_2]:
		if counts.get(pr, 0) != 2:
			errs.append("specific port %d vertices = %d, expected 2" % [pr, counts.get(pr, 0)])

	return errs

# ---------------- 内部工具 ----------------

## 数字摆放是否违规。官方两条：6/8 不能相邻、相邻不能同数字。
## strict=false 只查第一条 —— 6/8 相邻是任何模式都不允许的硬规则。
func _has_number_clash(strict: bool) -> bool:
	for hi in topo.hexes.size():
		var num: int = hex_number[hi]
		if num == 0:
			continue
		for d in HexGrid.DIRS:
			var n: Vector2i = topo.hexes[hi] + d
			if not topo.hex_index.has(n):
				continue
			var other: int = hex_number[topo.hex_index[n]]
			if other == 0:
				continue
			if strict and other == num:
				return true
			if (num == 6 and other == 8) or (num == 8 and other == 6):
				return true
	return false

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

## 螺旋序：外环（从正上方起顺时针）-> 内环 -> 中心。
## 数字 token 按此顺序摆放，即官方的"螺旋摆放法"。
static func spiral_order(topo: BoardTopology) -> Array[int]:
	var center := Vector2.ZERO
	for p in topo.hex_center:
		center += p
	center /= float(topo.hex_center.size())

	var items: Array = []
	for hi in topo.hexes.size():
		var h: Vector2i = topo.hexes[hi]
		var ring: int = (absi(h.x) + absi(h.y) + absi(h.x + h.y)) / 2
		var d: Vector2 = topo.hex_center[hi] - center
		var ang := atan2(d.x, -d.y)
		if ang < 0.0:
			ang += TAU
		items.append({"hi": hi, "ring": ring, "ang": ang})
	items.sort_custom(func(a, b):
		if a.ring != b.ring:
			return a.ring > b.ring
		return a.ang < b.ang)
	var out: Array[int] = []
	for it in items:
		out.append(it.hi)
	return out

## 海岸边按环序排列（共 30 条），用于均匀布置港口
static func boundary_cycle(topo: BoardTopology) -> Array[int]:
	var is_boundary := {}
	var first := -1
	for eid in topo.edges.size():
		if topo.edge_hexes[eid].size() == 1:
			is_boundary[eid] = true
			if first == -1:
				first = eid
	if first == -1:
		return []

	var cycle: Array[int] = []
	var cur_edge := first
	var cur_vertex: int = topo.edges[first].x
	while true:
		cycle.append(cur_edge)
		var e: Vector2i = topo.edges[cur_edge]
		var nxt_vertex: int = e.y if e.x == cur_vertex else e.x
		var nxt_edge := -1
		for cand in topo.vertex_edges[nxt_vertex]:
			if is_boundary.has(cand) and cand != cur_edge:
				nxt_edge = cand
				break
		if nxt_edge == -1 or nxt_edge == first:
			break
		cur_edge = nxt_edge
		cur_vertex = nxt_vertex
	return cycle
