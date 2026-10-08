class_name LongestRoad
extends RefCounted

## 最长道路计算。
##
## 正确模型：把棋盘顶点当作图的节点、玩家的路当作边，
## 求该图上的**最长简单路径**（顶点不重复），长度以"道路段数"计。
##
## 为什么必须用顶点简单路径、而不能用"两条路共享顶点就算连通"：
##   考虑三条路 4、5、16 交于同一个顶点 v。若按"共享顶点"建图，
##   会得到 0-5-16-4-3 这样一条 5 段的"路"，但走完 16 号路后必须原路
##   返回才能接上 4 号路——16 号路被重复走了，几何上不成立。
##   用顶点简单路径则天然排除这种折返，也顺带正确处理了两种官方裁决：
##     · 绕一个地块一整圈 = 5 段（不是 6，因为起点顶点会被重复）
##     · 对手村庄所在顶点不可穿过，但可以作为路的终点
##
## 实现：从每个有路的顶点出发做 DFS，访问过的顶点不再进入。
## 对手建筑所在顶点：可以走到它（路到此为止），但不能从它继续往外走。

static func length_for(topo: BoardTopology, st: GameState, pid: int) -> int:
	var me: PlayerState = st.players[pid]
	if me.roads.is_empty():
		return 0

	# 对手建筑所在顶点：不可穿过
	var blocked := {}
	for p in st.players:
		if p.id == pid:
			continue
		for v in p.settlements:
			blocked[v] = true
		for v in p.cities:
			blocked[v] = true

	# 顶点 -> 该玩家连在此点的路
	var at := {}
	for eid in me.roads:
		var e: Vector2i = topo.edges[eid]
		for v in [e.x, e.y]:
			if not at.has(v):
				at[v] = []
			at[v].append(eid)

	var best := [0]
	var visited := {}

	for start in at:
		visited.clear()
		visited[start] = true
		# 起点即使是"被阻断的顶点"，也可以从它出发（路以它为终点）
		for eid in at[start]:
			var v: int = topo.other_vertex(eid, start)
			if not visited.has(v):
				_expand(v, 1, at, topo, blocked, visited, best)
	return best[0]

## 走到顶点 u，已走过 depth 段路
static func _expand(u: int, depth: int, at: Dictionary, topo: BoardTopology,
		blocked: Dictionary, visited: Dictionary, best: Array) -> void:
	visited[u] = true
	if depth > best[0]:
		best[0] = depth
	if not blocked.has(u):
		for eid in at[u]:
			var v: int = topo.other_vertex(eid, u)
			if not visited.has(v):
				_expand(v, depth + 1, at, topo, blocked, visited, best)
	visited.erase(u)

## 重新裁定最长道路归属，返回是否发生变化
static func update_owner(topo: BoardTopology, st: GameState) -> bool:
	var lengths := {}
	var best_len := 0
	for p in st.players:
		var l: int = length_for(topo, st, p.id)
		lengths[p.id] = l
		if l > best_len:
			best_len = l

	var new_owner := -1
	if best_len >= Res.LONGEST_ROAD_MIN:
		var candidates: Array[int] = []
		for pid in lengths:
			if lengths[pid] == best_len:
				candidates.append(pid)
		if candidates.size() == 1:
			new_owner = candidates[0]
		elif st.longest_road_owner in candidates:
			new_owner = st.longest_road_owner   # 并列时当前持有者保留
		else:
			new_owner = candidates[0]

	if new_owner != st.longest_road_owner:
		st.longest_road_owner = new_owner
		return true
	return false

static func lengths_of_all(topo: BoardTopology, st: GameState) -> Dictionary:
	var out := {}
	for p in st.players:
		out[p.id] = length_for(topo, st, p.id)
	return out
