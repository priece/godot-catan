class_name BoardTopology
extends RefCounted

## 卡坦岛棋盘拓扑（全局唯一，构建一次后缓存）。
##
## 提供地块 / 顶点 / 边 三层的完整邻接关系，是本项目的地基。
## 期望规模：19 地块 · 54 顶点 · 72 边。
##
## 邻接约定：
##   - vertex_hexes[v]  顶点 v 相邻的地块（1~3 个）
##   - vertex_edges[v]  顶点 v 相连的边（2~3 条）
##   - edge_hexes[e]    边 e 相邻的地块（1~2 个；1 表示在岛屿外边界）
##   - edge_neighbors[e] 与边 e 共顶点的其他边（用于最长道路搜索）

const HEX_COUNT := 19
const VERTEX_COUNT := 54
const EDGE_COUNT := 72

## 地块
var hexes: Array[Vector2i] = []
var hex_center: Array[Vector2] = []
var hex_index: Dictionary = {}          ## Vector2i -> hex id

## 顶点
var vertices: Array[Vector2] = []
var vertex_hexes: Array = []
var vertex_edges: Array = []
var vertex_neighbors: Array = []

## 边
var edges: Array[Vector2i] = []         ## 每项 (a, b)，保证 a < b
var edge_index: Dictionary = {}         ## Vector2i(a,b) -> edge id
var edge_hexes: Array = []
var edge_neighbors: Array = []

## 地块 -> 其 6 个顶点 / 6 条边（按顺时针）
var hex_vertices: Array = []
var hex_edges: Array = []

static var _inst: BoardTopology = null

static func instance() -> BoardTopology:
	if _inst == null:
		_inst = BoardTopology.new()
		_inst.build()
	return _inst

## 从边 id 取出"另一个"顶点
func other_vertex(edge_id: int, v: int) -> int:
	var e: Vector2i = edges[edge_id]
	return e.y if e.x == v else e.x

func build() -> void:
	hexes = HexGrid.generate_hex_coords()
	for i in hexes.size():
		hex_index[hexes[i]] = i
		hex_center.append(HexGrid.hex_to_pixel(hexes[i]))

	# --- 顶点：算像素角点并按坐标合并 ---
	var key_to_vid: Dictionary = {}
	for hi in hexes.size():
		var vids: Array = []
		for c in 6:
			var p: Vector2 = HexGrid.hex_corner_pixel(hexes[hi], c)
			var k: Vector2i = HexGrid.pixel_key(p)
			if not key_to_vid.has(k):
				key_to_vid[k] = vertices.size()
				vertices.append(p)
				vertex_hexes.append([])
				vertex_edges.append([])
				vertex_neighbors.append([])
			var vid: int = key_to_vid[k]
			vids.append(vid)
			var vh: Array = vertex_hexes[vid]
			if not vh.has(hi):
				vh.append(hi)
		hex_vertices.append(vids)

	# --- 边：每个地块的相邻角组成一条边，全局去重 ---
	for hi in hexes.size():
		var eids: Array = []
		var vids: Array = hex_vertices[hi]
		for c in 6:
			var a: int = vids[c]
			var b: int = vids[(c + 1) % 6]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edge_index.has(key):
				edge_index[key] = edges.size()
				edges.append(key)
				edge_hexes.append([])
				edge_neighbors.append([])
			var eid: int = edge_index[key]
			eids.append(eid)
			var eh: Array = edge_hexes[eid]
			if not eh.has(hi):
				eh.append(hi)
		hex_edges.append(eids)

	# --- 顶点 <-> 边 反向索引 ---
	for eid in edges.size():
		var e: Vector2i = edges[eid]
		for vid in [e.x, e.y]:
			var ve: Array = vertex_edges[vid]
			if not ve.has(eid):
				ve.append(eid)

	# --- 顶点邻居 ---
	for vid in vertices.size():
		var nb: Array = vertex_neighbors[vid]
		for eid in vertex_edges[vid]:
			var other: int = other_vertex(eid, vid)
			if not nb.has(other):
				nb.append(other)

	# --- 边邻居（共顶点）---
	for eid in edges.size():
		var e: Vector2i = edges[eid]
		var nb: Array = edge_neighbors[eid]
		for vid in [e.x, e.y]:
			for e2 in vertex_edges[vid]:
				if e2 != eid and not nb.has(e2):
					nb.append(e2)

## 自检：规模 + 度数分布。任何一项不符立即报错，防止几何算错静默污染全局。
## 返回空数组表示通过，否则返回错误描述列表。
func self_check() -> Array[String]:
	var errs: Array[String] = []
	if hexes.size() != HEX_COUNT:
		errs.append("hex count = %d, expected %d" % [hexes.size(), HEX_COUNT])
	if vertices.size() != VERTEX_COUNT:
		errs.append("vertex count = %d, expected %d" % [vertices.size(), VERTEX_COUNT])
	if edges.size() != EDGE_COUNT:
		errs.append("edge count = %d, expected %d" % [edges.size(), EDGE_COUNT])

	# 顶点按相邻地块数分布：18 处只挨 1 个地块（棋盘外边界上的凸角）
	# · 12 处挨 2 个 · 24 处挨 3 个（内部顶点）。
	# 该分布由欧拉公式约束：总和 = 6*19 = 114 = n1 + 2*n2 + 3*n3，
	# 且 n1 + n2 + n3 = 54，联立得 n3 - n1 = 6*HEX - 2*VERTEX = 6，实测 24-18=6 ✓。
	var deg := [0, 0, 0, 0]
	for vh in vertex_hexes:
		if vh.size() > 3:
			errs.append("vertex shares %d hexes (>3)" % vh.size())
		else:
			deg[vh.size()] += 1
	if deg[1] != 18 or deg[2] != 12 or deg[3] != 24:
		errs.append("vertex hex-degree dist = %s, expected [_,18,12,24]" % [deg])

	# 边按相邻地块数分布：外边界 30 条 · 内部 42 条
	var e1 := 0
	var e2 := 0
	for eh in edge_hexes:
		if eh.size() == 1:
			e1 += 1
		elif eh.size() == 2:
			e2 += 1
		else:
			errs.append("edge shares %d hexes (expect 1~2)" % eh.size())
	if e1 != 30 or e2 != 42:
		errs.append("edge hex-degree dist = (%d, %d), expected (30, 42)" % [e1, e2])

	# 每个地块恰有 6 顶点 / 6 边
	for hi in hexes.size():
		if hex_vertices[hi].size() != 6:
			errs.append("hex %d has %d vertices" % [hi, hex_vertices[hi].size()])
		if hex_edges[hi].size() != 6:
			errs.append("hex %d has %d edges" % [hi, hex_edges[hi].size()])

	return errs
