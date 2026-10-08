class_name Rules
extends RefCounted

## 规则校验层。所有合法性判断集中在这里，GameController 只负责调用。
## 校验函数全部是纯函数（不修改状态），便于 AI 做"假设性推演"。

# ---------------- 占位查询 ----------------

static func building_owner(st: GameState, v: int) -> int:
	for p in st.players:
		if p.settlements.has(v) or p.cities.has(v):
			return p.id
	return -1

static func vertex_has_building(st: GameState, v: int) -> bool:
	return building_owner(st, v) >= 0

static func is_city(st: GameState, v: int) -> bool:
	for p in st.players:
		if p.cities.has(v):
			return true
	return false

static func road_owner(st: GameState, eid: int) -> int:
	for p in st.players:
		if p.roads.has(eid):
			return p.id
	return -1

static func edge_has_road(st: GameState, eid: int) -> bool:
	return road_owner(st, eid) >= 0

## 顶点 -> 拥有者 的完整映射（批量计算时用，避免重复遍历）
static func occupancy_map(st: GameState) -> Dictionary:
	var m := {}
	for p in st.players:
		for v in p.settlements:
			m[v] = p.id
		for v in p.cities:
			m[v] = p.id
	return m

static func road_map(st: GameState) -> Dictionary:
	var m := {}
	for p in st.players:
		for e in p.roads:
			m[e] = p.id
	return m

# ---------------- 建造校验 ----------------

## 距离规则：该顶点及所有相邻顶点都不能有建筑
static func distance_rule_ok(st: GameState, v: int) -> bool:
	if vertex_has_building(st, v):
		return false
	for n in BoardTopology.instance().vertex_neighbors[v]:
		if vertex_has_building(st, n):
			return false
	return true

## 该顶点是否连通到玩家的建筑/道路网络
static func vertex_connected_to_network(st: GameState, pid: int, v: int) -> bool:
	var p: PlayerState = st.players[pid]
	if p.has_building_at(v):
		return true
	for eid in BoardTopology.instance().vertex_edges[v]:
		if p.roads.has(eid):
			return true
	return false

static func settlement_piece_left(p: PlayerState) -> bool:
	return p.settlements.size() + p.cities.size() < Res.LIMIT_SETTLEMENT

static func road_piece_left(p: PlayerState) -> bool:
	return p.roads.size() < Res.LIMIT_ROAD

static func city_piece_left(p: PlayerState) -> bool:
	return p.cities.size() < Res.LIMIT_CITY

## 可放村庄的顶点。
## setup=true 时只看距离规则；否则还必须连到自己的路网。
static func valid_settlement_vertices(st: GameState, pid: int, is_setup: bool) -> Array[int]:
	var out: Array[int] = []
	var p: PlayerState = st.players[pid]
	if not settlement_piece_left(p):
		return out
	for v in BoardTopology.instance().vertices.size():
		if not distance_rule_ok(st, v):
			continue
		if is_setup or vertex_connected_to_network(st, pid, v):
			out.append(v)
	return out

## 可放道路的边。setup=true 时必须贴着 anchor 顶点。
static func valid_road_edges(st: GameState, pid: int, is_setup: bool, anchor: int = -1) -> Array[int]:
	var out: Array[int] = []
	var p: PlayerState = st.players[pid]
	if not road_piece_left(p):
		return out
	var topo := BoardTopology.instance()
	for eid in topo.edges.size():
		if edge_has_road(st, eid):
			continue
		var e: Vector2i = topo.edges[eid]
		if is_setup:
			if anchor >= 0 and (e.x == anchor or e.y == anchor):
				out.append(eid)
		else:
			if vertex_connected_to_network(st, pid, e.x) or vertex_connected_to_network(st, pid, e.y):
				out.append(eid)
	return out

## 可升级为城市的顶点（自己的村庄）
static func valid_city_vertices(st: GameState, pid: int) -> Array[int]:
	var p: PlayerState = st.players[pid]
	if not city_piece_left(p):
		return []
	return p.settlements.duplicate()

static func can_buy_dev(st: GameState, pid: int) -> bool:
	return st.dev_deck_remaining() > 0 and st.players[pid].has(Res.COST_DEV)

## 本回合可打出的发展卡（不含当回合买入的）
static func playable_dev_cards(p: PlayerState) -> Array[int]:
	return p.dev_cards.duplicate()

# ---------------- 资源 ----------------

static func can_afford(p: PlayerState, cost: Dictionary) -> bool:
	return p.has(cost)

## 该玩家用资源 r 与银行兑换时能拿到的最好比例（2 / 3 / 4）
static func best_ratio_for(st: GameState, pid: int, r: int) -> int:
	var p: PlayerState = st.players[pid]
	var best := 4
	for v in p.all_vertices():
		var pr: Array = st.board.vertex_port_ratio(v)
		if pr.is_empty():
			continue
		var give: int = pr[0]
		var specific: int = pr[1]
		if specific < 0:
			best = mini(best, 3)
		elif specific == r:
			best = mini(best, 2)
	return best

static func can_bank_trade(st: GameState, pid: int, give_r: int, take_r: int) -> bool:
	if give_r == take_r:
		return false
	if take_r < 0 or take_r >= Res.R_COUNT:
		return false
	if st.bank[take_r] <= 0:
		return false
	return st.players[pid].count(give_r) >= best_ratio_for(st, pid, give_r)

## 列出该玩家所有可行的银行交易 [give_r, take_r, ratio]
static func bank_trade_options(st: GameState, pid: int) -> Array:
	var out: Array = []
	for give_r in Res.R_COUNT:
		var ratio: int = best_ratio_for(st, pid, give_r)
		if st.players[pid].count(give_r) < ratio:
			continue
		for take_r in Res.R_COUNT:
			if take_r == give_r or st.bank[take_r] <= 0:
				continue
			out.append([give_r, take_r, ratio])
	return out

# ---------------- 强盗 ----------------

static func valid_robber_hexes(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for hi in st.board.topo.hexes.size():
		if hi != st.board.robber_hex:
			out.append(hi)
	return out

## 移到 new_hex 后可以偷谁（相邻有建筑且手上有牌的其他玩家）
static func steal_candidates(st: GameState, new_hex: int, self_pid: int) -> Array[int]:
	var out: Array[int] = []
	var occ: Dictionary = occupancy_map(st)
	for v in BoardTopology.instance().hex_vertices[new_hex]:
		var owner: int = occ.get(v, -1)
		if owner >= 0 and owner != self_pid and st.players[owner].total_resources() > 0:
			if not out.has(owner):
				out.append(owner)
	return out

## 掷出 7 时需要弃掉的张数（手牌 >= 8 弃一半，向下取整）
static func discard_count(p: PlayerState) -> int:
	var t: int = p.total_resources()
	if t < 8:
		return 0
	return t / 2
