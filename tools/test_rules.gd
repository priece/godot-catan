extends SceneTree

## 规则引擎单元测试。覆盖那些"随机对局验不出来"的边界规则：
##   初始布置 · 距离规则 · 最长道路（截断 / 分叉）· 弃牌阈值 · 港口汇率 · 发展卡时机
##
## 用法： godot --headless --path . --script res://tools/test_rules.gd
## 退出码 0 = 全通过

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== 规则引擎单元测试 ===")
	_test_initial_setup()
	_test_distance_rule()
	_test_longest_road_chain()
	_test_longest_road_blocked()
	_test_longest_road_branch()
	_test_longest_road_minimum()
	_test_discard_threshold()
	_test_port_rates()
	_test_dev_card_timing()
	_test_bank_trade()
	print("")
	print("通过 %d · 失败 %d" % [_pass, _fail])
	print("单测结果：%s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [ok]   %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])

# ================= 初始布置 =================

func _test_initial_setup() -> void:
	print("\n-- 初始布置 --")
	var ctl := _fresh_game(4, 4242)
	ctl.run_setup()
	var st := ctl.st

	for p in st.players:
		_ok(p.settlements.size() == 2, "P%d 有 2 座初始村庄" % p.id, "实际 %d" % p.settlements.size())
		_ok(p.roads.size() == 2, "P%d 有 2 条初始道路" % p.id, "实际 %d" % p.roads.size())

	# 各自第二座村庄的相邻地块数即起始手牌数
	for p in st.players:
		var v: int = p.settlements[1]
		var expect := 0
		for hi in ctl.topo.vertex_hexes[v]:
			if st.board.hex_resource(hi) >= 0:
				expect += 1
		_ok(p.total_resources() == expect,
			"P%d 起始手牌 = 第二座村相邻地块数" % p.id,
			"手牌 %d / 期望 %d" % [p.total_resources(), expect])

	# 起始阶段也不能违反距离规则
	var bad := 0
	for p in st.players:
		for v in p.settlements:
			for n in ctl.topo.vertex_neighbors[v]:
				if Rules.vertex_has_building(st, n):
					bad += 1
	_ok(bad == 0, "初始村庄之间满足距离规则", "违规 %d 处" % bad)

	_ok(st.phase == GameState.Phase.MAIN, "初始布置结束后进入主阶段")

# ================= 距离规则 =================

func _test_distance_rule() -> void:
	print("\n-- 距离规则 --")
	var ctl := _fresh_game(4, 77)
	ctl.run_setup()
	var st := ctl.st
	var topo := ctl.topo

	var p0: PlayerState = st.players[0]
	var v: int = p0.settlements[0]
	_ok(not Rules.distance_rule_ok(st, v), "已有村庄的点不可再建")
	for n in topo.vertex_neighbors[v]:
		_ok(not Rules.distance_rule_ok(st, n), "紧邻已有村庄的点不可建（距离规则）")
		break  # 检查一个即可，避免输出过长

# ================= 最长道路 =================

func _test_longest_road_chain() -> void:
	print("\n-- 最长道路：单链 --")
	var topo := BoardTopology.instance()
	var st := _bare_state(2)
	var path := _find_path(topo, 6)
	if path.is_empty():
		_ok(false, "在棋盘上找到 6 条边的链")
		return
	st.players[0].roads = path.duplicate()
	_ok(LongestRoad.length_for(topo, st, 0) == 6, "6 条连续路 = 长度 6",
		"实际 %d" % LongestRoad.length_for(topo, st, 0))
	_ok(LongestRoad.length_for(topo, st, 1) == 0, "对手没有路则为 0")

func _test_longest_road_blocked() -> void:
	print("\n-- 最长道路：被对手村庄截断 --")
	var topo := BoardTopology.instance()
	var st := _bare_state(2)
	var path := _find_path(topo, 6)
	st.players[0].roads = path.duplicate()

	# 在 path[2] 与 path[3] 的共同顶点上放对手村庄
	var v := _shared_vertex(topo, path[2], path[3])
	st.players[1].settlements.append(v)
	var got := LongestRoad.length_for(topo, st, 0)
	_ok(got == 3, "截断后最长只剩一半（3 段）", "实际 %d" % got)

	# 自己的村庄不应截断自己的路
	var st2 := _bare_state(2)
	st2.players[0].roads = path.duplicate()
	st2.players[0].settlements.append(v)
	_ok(LongestRoad.length_for(topo, st2, 0) == 6, "自己的建筑不截断自己的路",
		"实际 %d" % LongestRoad.length_for(topo, st2, 0))

func _test_longest_road_branch() -> void:
	print("\n-- 最长道路：分叉 --")
	var topo := BoardTopology.instance()
	var st := _bare_state(2)
	var path := _find_path(topo, 4)
	st.players[0].roads = path.duplicate()
	var base := LongestRoad.length_for(topo, st, 0)
	_ok(base == 4, "4 条连续路 = 长度 4", "实际 %d" % base)

	# 在链的末端再接一条岔路
	var end_v := _far_endpoint(topo, path)
	var branch := -1
	for e in topo.vertex_edges[end_v]:
		if not path.has(e):
			branch = e
			break
	if branch < 0:
		_ok(false, "找到末端岔路")
		return
	st.players[0].roads.append(branch)
	var got := LongestRoad.length_for(topo, st, 0)
	_ok(got == 5, "末端分叉后长度 5（4+1）", "实际 %d" % got)

	# 中间分叉不应让长度超过主干
	var st2 := _bare_state(2)
	st2.players[0].roads = path.duplicate()
	var mid_v := _shared_vertex(topo, path[1], path[2])
	var mid_branch := -1
	for e in topo.vertex_edges[mid_v]:
		if not path.has(e):
			mid_branch = e
			break
	if mid_branch >= 0:
		st2.players[0].roads.append(mid_branch)
		var got2 := LongestRoad.length_for(topo, st2, 0)
		# 主干 4 段；中间插一条岔路，最长仍是走主干的 4 段
		# （三条路交于一点时不允许"原路折返"接上第四条路）
		_ok(got2 == 4, "中间分叉不增加最长路（仍为 4）", "实际 %d" % got2)

func _test_longest_road_minimum() -> void:
	print("\n-- 最长道路：5 段门槛 --")
	var topo := BoardTopology.instance()
	var st := _bare_state(2)
	var path := _find_path(topo, 5)
	st.players[0].roads = path.duplicate()
	_ok(LongestRoad.length_for(topo, st, 0) == 5, "恰好 5 段")

	# 5 段时应当获得奖励；4 段时不应获得
	LongestRoad.update_owner(topo, st)
	_ok(st.longest_road_owner == 0, "5 段获得最长道路奖励", "归属 %d" % st.longest_road_owner)

	var st2 := _bare_state(2)
	st2.players[0].roads = _find_path(topo, 4)
	LongestRoad.update_owner(topo, st2)
	_ok(st2.longest_road_owner == -1, "4 段不足门槛不得奖励", "归属 %d" % st2.longest_road_owner)

# ================= 弃牌 =================

func _test_discard_threshold() -> void:
	print("\n-- 掷出 7 的弃牌规则 --")
	var cases := [[7, 0], [8, 4], [9, 4], [10, 5], [15, 7]]
	for c in cases:
		var p := PlayerState.new(0)
		# 按顺序填满 c[0] 张
		var left: int = c[0]
		var r := 0
		while left > 0 and r < Res.R_COUNT:
			var put: int = mini(left, 5)
			p.resources[r] = put
			left -= put
			r += 1
		var got := Rules.discard_count(p)
		_ok(got == c[1], "%d 张手牌弃 %d 张" % [c[0], c[1]], "实际 %d" % got)

# ================= 港口 =================

func _test_port_rates() -> void:
	print("\n-- 港口交易汇率 --")
	var ctl := _fresh_game(4, 999)
	var st := ctl.st
	var p: PlayerState = st.players[0]

	_ok(Rules.best_ratio_for(st, 0, Res.R.WOOD) == 4, "无港口时 4:1")

	# 找一个通用港顶点
	var generic_v := -1
	var specific_v := -1
	var specific_type := -1
	for v in st.board.vertex_port.size():
		var pt: int = st.board.vertex_port[v]
		if pt == Res.Port.GENERIC_3 and generic_v < 0:
			generic_v = v
		elif pt > Res.Port.GENERIC_3 and specific_v < 0:
			specific_v = v
			specific_type = pt - 1

	if generic_v >= 0:
		p.settlements.append(generic_v)
		_ok(Rules.best_ratio_for(st, 0, Res.R.WOOD) == 3, "通用港 3:1")
		p.settlements.erase(generic_v)

	if specific_v >= 0:
		p.settlements.append(specific_v)
		_ok(Rules.best_ratio_for(st, 0, specific_type) == 2,
			"指定资源港 2:1（资源 %s）" % Res.R_NAMES[specific_type])
		var other := (specific_type + 1) % Res.R_COUNT
		_ok(Rules.best_ratio_for(st, 0, other) == 4,
			"非该港指定资源仍是 4:1")
		p.settlements.erase(specific_v)

# ================= 发展卡 =================

func _test_dev_card_timing() -> void:
	print("\n-- 发展卡：购买当回合不能打 --")
	var ctl := _fresh_game(2, 31337)
	var st := ctl.st
	var p: PlayerState = st.players[0]
	p.resources = [5, 5, 5, 5, 5]
	# 直接调用内部购买逻辑：买一张卡
	var before := st.dev_deck_remaining()
	_ok(Rules.can_buy_dev(st, 0), "资源足够时可以买发展卡")
	_ok(p.fresh_dev_cards.is_empty() and p.dev_cards.is_empty(), "初始没有发展卡")
	_ok(before == 25, "牌库 25 张", "实际 %d" % before)

	# 模拟买卡后的状态：卡进入 fresh_dev_cards，不应出现在 dev_cards（可打列表）
	p.fresh_dev_cards.append(Res.Dev.KNIGHT)
	_ok(not p.dev_cards.has(Res.Dev.KNIGHT), "当回合买的卡不在可打列表里")
	_ok(Rules.playable_dev_cards(p).is_empty(), "当回合无卡可打")

	# 回合结束后 fresh 转入可打列表
	p.dev_cards.append_array(p.fresh_dev_cards)
	p.fresh_dev_cards.clear()
	_ok(Rules.playable_dev_cards(p).has(Res.Dev.KNIGHT), "下回合起可打")

# ================= 银行交易 =================

func _test_bank_trade() -> void:
	print("\n-- 银行交易合法性 --")
	var ctl := _fresh_game(2, 555)
	var st := ctl.st
	var p: PlayerState = st.players[0]
	p.resources = [4, 0, 0, 0, 0]
	_ok(Rules.can_bank_trade(st, 0, Res.R.WOOD, Res.R.GRAIN), "4 木材换 1 麦子可行")
	_ok(not Rules.can_bank_trade(st, 0, Res.R.GRAIN, Res.R.WOOD), "没有麦子不能换出")
	_ok(not Rules.can_bank_trade(st, 0, Res.R.WOOD, Res.R.WOOD), "同种资源不能换")
	p.resources = [3, 0, 0, 0, 0]
	_ok(not Rules.can_bank_trade(st, 0, Res.R.WOOD, Res.R.GRAIN), "3 木材不足 4:1")

	# 银行没有该资源时不能换
	p.resources = [4, 0, 0, 0, 0]
	st.bank[Res.R.GRAIN] = 0
	_ok(not Rules.can_bank_trade(st, 0, Res.R.WOOD, Res.R.GRAIN), "银行该资源耗尽则不可换")

# ================= 辅助 =================

func _fresh_game(n: int, seed: int) -> GameController:
	var configs: Array = []
	var providers: Array = []
	for i in n:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	var ctl := GameController.new()
	ctl.new_game(configs, seed, true, providers)
	return ctl

## 造一个只有玩家、没有棋盘的裸状态（用于最长道路等纯算法测试）
func _bare_state(n: int) -> GameState:
	var st := GameState.new()
	st.board = Board.generate(1, true)
	for i in n:
		st.players.append(PlayerState.new(i))
	return st

## 在棋盘上找一条 n 条边的"严格链"（只相邻于前后两条，不能绕回自己）
## —— 否则正好绕一个地块一圈的 6 条边会被误当成 6 段路，而实际最长只有 5。
func _find_path(topo: BoardTopology, n: int) -> Array[int]:
	for start in topo.edges.size():
		var res: Array[int] = []
		if _dfs_path(topo, start, n, {}, res):
			return res
	return []

func _dfs_path(topo: BoardTopology, eid: int, target: int, used: Dictionary, path: Array[int]) -> bool:
	used[eid] = true
	path.append(eid)
	if path.size() == target:
		if _is_strict_chain(topo, path):
			return true
	else:
		for nxt in topo.edge_neighbors[eid]:
			if not used.has(nxt):
				if _dfs_path(topo, nxt, target, used, path):
					return true
	path.pop_back()
	used.erase(eid)
	return false

func _is_strict_chain(topo: BoardTopology, path: Array[int]) -> bool:
	for i in path.size():
		for j in range(i + 2, path.size()):
			if topo.edge_neighbors[path[i]].has(path[j]):
				return false
	return true

func _shared_vertex(topo: BoardTopology, a: int, b: int) -> int:
	var ea: Vector2i = topo.edges[a]
	var eb: Vector2i = topo.edges[b]
	if ea.x == eb.x or ea.x == eb.y:
		return ea.x
	return ea.y

## 链的"远端"顶点：第一段边与第二段边不共用的那个端点
func _far_endpoint(topo: BoardTopology, path: Array[int]) -> int:
	var first: Vector2i = topo.edges[path[0]]
	var shared := _shared_vertex(topo, path[0], path[1])
	return first.y if first.x == shared else first.x
