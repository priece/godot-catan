class_name AIController
extends IntentProvider

## 三档 AI 的公共实现。子类只调参数 + 覆写少量钩子就能改变强度。
##
## 参数含义（这是"难度"的真正来源，不是简单调数值）：
##   noise          评分噪声，越大越"糊涂"
##   *_bias         各类建造的倾向倍率
##   savvy          针对性程度：强盗打击/偷牌选择/冲最长路/谈判风险感知
##   trade_risk     接受交易时对"喂养对手"的容忍度，越大越保守
##   random_accept  完全不看条件的随机接受概率
##   pass_chance    无事可做时提前结束回合的概率

var topo: BoardTopology
var rng := RandomNumberGenerator.new()

var noise := 0.0
var dev_bias := 1.0
var road_bias := 1.0
var city_bias := 1.0
var settle_bias := 1.0
var savvy := 1.0
var trade_risk := 1.5
var random_accept := 0.0
var pass_chance := 0.0
var max_offers_per_turn := 0

var _blocked: Array[String] = []
var _offers_made := 0

func _init(p_pid: int = 0) -> void:
	super(p_pid)
	topo = BoardTopology.instance()

func on_game_start(st: GameState) -> void:
	rng.seed = st.rng.seed + pid * 7919

func on_turn_start(_st: GameState) -> void:
	_blocked.clear()
	_offers_made = 0

func on_invalid_action(_st: GameState, action: Dictionary) -> void:
	_blocked.append(_sig(action))

func _sig(a: Dictionary) -> String:
	return "%s|%s|%s|%s" % [a.get("type", ""), a.get("vertex", -1), a.get("edge", -1), a.get("card", -1)]

func _is_blocked(a: Dictionary) -> bool:
	return _blocked.has(_sig(a))

func _noise() -> float:
	if noise <= 0.0:
		return 0.0
	return rng.randf_range(-noise, noise)

# ================= 初始布置 =================

## 初始布置：整个游戏里影响最大的决策，值得单独调。
##
## 除了产出期望值，还叠加三个来自实战/研究的修正：
##   1. 第二座村庄优先补足第一座没覆盖的资源种类（避免单资源依赖）
##   2. 惩罚与第一座村庄"撞数字"——收入过于集中会忽多忽少，还更容易被 7 打崩
##   3. 惩罚两座村庄共用同一地块（等于浪费一个产出位）
func choose_initial_settlement(st: GameState, valid: Array[int]) -> int:
	var p: PlayerState = st.players[pid]
	var weights := Evaluation.weights_for(Evaluation.Phase.EARLY)

	var have_kinds: Array[int] = []
	var owned_numbers := {}
	var owned_hexes := {}
	if p.settlements.size() >= 1:
		for v in p.settlements:
			for r in st.board.vertex_resource_kinds(v):
				if not have_kinds.has(r):
					have_kinds.append(r)
			for hi in topo.vertex_hexes[v]:
				owned_hexes[hi] = true
				var n: int = st.board.hex_number[hi]
				if n > 0:
					owned_numbers[n] = true

	var best: int = valid[0]
	var best_score := -1e18
	for v in valid:
		var s := Evaluation.vertex_score(st, v, weights)

		if p.settlements.size() >= 1:
			# 1) 补足缺失的资源种类
			for r in st.board.vertex_resource_kinds(v):
				if not have_kinds.has(r):
					s += 14.0
			# 2) 撞数字惩罚
			var dup := 0
			var shared_hex := 0
			for hi in topo.vertex_hexes[v]:
				var n2: int = st.board.hex_number[hi]
				if n2 > 0 and owned_numbers.has(n2):
					dup += 1
				if owned_hexes.has(hi):
					shared_hex += 1
			s -= float(dup) * 6.0
			s -= float(shared_hex) * 12.0

		s += _extra_settlement_bonus(st, v, weights)
		s += rng.randf_range(-noise, noise)
		if s > best_score:
			best_score = s
			best = v
	return best

func choose_initial_road(st: GameState, anchor: int, valid: Array[int]) -> int:
	var weights := Evaluation.weights_for(Evaluation.Phase.EARLY)
	var best: int = valid[0]
	var best_score := -1e18
	for eid in valid:
		var e: Vector2i = topo.edges[eid]
		var far: int = e.y if e.x == anchor else e.x
		var s := 0.0
		if Rules.distance_rule_ok(st, far):
			s += Evaluation.vertex_score(st, far, weights)
		for n in topo.vertex_neighbors[far]:
			if Rules.distance_rule_ok(st, n):
				s += Evaluation.vertex_score(st, n, weights) * 0.6
		s += rng.randf_range(-noise, noise) * 0.5
		if s > best_score:
			best_score = s
			best = eid
	return best

# ================= 强盗 =================

func choose_robber_hex(st: GameState, valid: Array[int]) -> int:
	var occ := Rules.occupancy_map(st)
	var best: int = valid[0]
	var best_score := -1e18
	for h in valid:
		var num: int = st.board.hex_number[h]
		var score := 0.0
		for v in topo.hex_vertices[h]:
			var owner: int = occ.get(v, -1)
			if owner < 0 or owner == pid:
				continue
			var amt := 2 if st.players[owner].cities.has(v) else 1
			var dmg := float(Res.PIPS.get(num, 0)) * float(amt)
			# 越接近胜利的对手越值得打击
			dmg *= 1.0 + float(st.public_victory_points(owner)) * 0.12 * savvy
			score += dmg
		# 别挡住自己的产出
		for v in topo.hex_vertices[h]:
			if occ.get(v, -1) == pid:
				score -= 8.0
		score += _noise()
		if score > best_score:
			best_score = score
			best = h
	return best

func choose_steal_target(st: GameState, candidates: Array[int]) -> int:
	var best: int = candidates[0]
	var best_score := -1e18
	for c in candidates:
		var s := float(st.players[c].total_resources()) + float(st.public_victory_points(c)) * 1.5 * savvy
		s += _noise()
		if s > best_score:
			best_score = s
			best = c
	return best

# ================= 主阶段 =================

func choose_action(st: GameState) -> Dictionary:
	var p: PlayerState = st.players[pid]
	var weights := Evaluation.weights_for(Evaluation.phase_of(st))
	var options: Array = []

	# 打发展卡
	var dev_action := _choose_dev_play(st)
	if not dev_action.is_empty() and not _is_blocked(dev_action):
		options.append(dev_action)

	# 免费道路（修路卡）优先用掉，别浪费
	if st.free_roads_remaining > 0:
		var free_edges := Rules.valid_road_edges(st, pid, false)
		if not free_edges.is_empty():
			options.append({
				"type": Res.A_PLACE_ROAD,
				"edge": _best_road_edge(st, free_edges, weights),
				"score": 500.0,
			})

	# 升城
	if p.has(Res.COST_CITY):
		var city_spots := Rules.valid_city_vertices(st, pid)
		if not city_spots.is_empty():
			options.append({
				"type": Res.A_UPGRADE_CITY,
				"vertex": _best_city_vertex(st, city_spots, weights),
				"score": 100.0 * city_bias + _noise(),
			})

	# 建村庄
	if p.has(Res.COST_SETTLEMENT):
		var spots := Rules.valid_settlement_vertices(st, pid, false)
		if not spots.is_empty():
			var v := _best_settlement_vertex(st, spots, weights)
			options.append({
				"type": Res.A_PLACE_SETTLEMENT,
				"vertex": v,
				"score": 99.0 * settle_bias + Evaluation.vertex_score(st, v, weights) * 0.25 + _noise(),
			})

	# 买发展卡
	if Rules.can_buy_dev(st, pid):
		options.append({"type": Res.A_BUY_DEV, "score": 72.0 * dev_bias + _noise()})

	# 修路
	if p.has(Res.COST_ROAD):
		var edges := Rules.valid_road_edges(st, pid, false)
		if not edges.is_empty():
			var e := _best_road_edge(st, edges, weights)
			options.append({
				"type": Res.A_PLACE_ROAD,
				"edge": e,
				"score": _edge_score(st, e, weights) * road_bias + _noise(),
			})

	# 银行交易：只差一张就能建出高价值建筑时，优先把资源换到手
	# （必须作为"有分数的选项"参与比较，而不是无事可做时的兜底——
	#   否则 AI 永远有便宜的路可修，这个分支就永远轮不到。）
	var bt := _try_bank_trade(st)
	if not bt.is_empty() and not _is_blocked(bt):
		bt["score"] = 130.0
		options.append(bt)

	# 主动发起交易（仅高难度开启）
	if _offers_made < max_offers_per_turn:
		var offer := _try_offer_trade(st)
		if not offer.is_empty() and not _is_blocked(offer):
			options.append(offer)

	if options.is_empty():
		if rng.randf() < pass_chance:
			return {"type": Res.A_END_TURN}
		return {"type": Res.A_END_TURN}

	options.sort_custom(func(a, b): return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	var best: Dictionary = options[0]
	if best.get("type", "") == Res.A_OFFER_TRADE:
		_offers_made += 1
	best.erase("score")
	return best

# ---------------- 选择具体位置 ----------------

func _best_settlement_vertex(st: GameState, spots: Array[int], weights: Array) -> int:
	var best: int = spots[0]
	var best_score := -1e18
	for v in spots:
		var s := Evaluation.vertex_score(st, v, weights)
		s += _extra_settlement_bonus(st, v, weights)
		s += rng.randf_range(-noise, noise) * 0.5
		if s > best_score:
			best_score = s
			best = v
	return best

func _best_city_vertex(st: GameState, spots: Array[int], weights: Array) -> int:
	var best: int = spots[0]
	var best_score := -1e18
	for v in spots:
		var s := Evaluation.vertex_score(st, v, weights)
		s += rng.randf_range(-noise, noise) * 0.5
		if s > best_score:
			best_score = s
			best = v
	return best

func _best_road_edge(st: GameState, edges: Array[int], weights: Array) -> int:
	var best: int = edges[0]
	var best_score := -1e18
	for e in edges:
		var s := _edge_score(st, e, weights)
		s += rng.randf_range(-noise, noise) * 0.5
		if s > best_score:
			best_score = s
			best = e
	return best

## 一条路的长期价值。
##
## 关键点：一条路的价值 = 它"新打通"的那个顶点值多少。
## 如果两端本来就连在我的路网里，这条路不带来任何新机会，价值应当很低。
## （早期版本按"沿线顶点产出"打分，导致路分虚高、和城市抢资源，
##   实测每局修 12.5 条路却只建 0.9 座城，就是这里出的问题。）
func _edge_score(st: GameState, eid: int, weights: Array) -> float:
	var e: Vector2i = topo.edges[eid]
	var best := 0.0
	var has_target := false
	for v in [e.x, e.y]:
		if Rules.vertex_connected_to_network(st, pid, v):
			continue   # 本来就连着，这条路没开辟新点
		if Rules.distance_rule_ok(st, v):
			has_target = true
			best = maxf(best, Evaluation.vertex_score(st, v, weights))
		else:
			# 该点被占或被距离规则挡住，但它仍是未来继续扩张的中转
			best = maxf(best, 7.0)
	if not has_target:
		best *= 0.35   # 没有明确目标的路，价值大打折扣

	var s := 18.0 + best * 0.9
	# 快到 5 段了，冲刺最长道路
	if LongestRoad.length_for(topo, st, pid) >= Res.LONGEST_ROAD_MIN - 1:
		s += 20.0 * savvy
	s += _extra_road_bonus(st, eid, weights)
	return s

# ---------------- 发展卡 ----------------

func _choose_dev_play(st: GameState) -> Dictionary:
	var p: PlayerState = st.players[pid]
	if st.dev_played_this_turn or p.dev_cards.is_empty():
		return {}

	# 骑士：能拿下 / 保住最大军队时必打
	if p.dev_cards.has(Res.Dev.KNIGHT):
		var would_be := p.played_knights + 1
		var others_max := 0
		for o in st.players:
			if o.id != pid:
				others_max = maxi(others_max, o.played_knights)
		if would_be >= Res.LARGEST_ARMY_MIN and would_be > others_max:
			return {"type": Res.A_PLAY_DEV, "card": Res.Dev.KNIGHT, "score": 320.0}
		if rng.randf() < 0.25 * savvy:
			return {"type": Res.A_PLAY_DEV, "card": Res.Dev.KNIGHT, "score": 60.0}

	# 修路卡：手上还有路可放才值得打
	if p.dev_cards.has(Res.Dev.ROAD_BUILDING):
		if st.free_roads_remaining > 0 or Rules.valid_road_edges(st, pid, false).size() >= 2:
			return {"type": Res.A_PLAY_DEV, "card": Res.Dev.ROAD_BUILDING, "score": 160.0}

	# 垄断：挑对手手上最多的资源
	if p.dev_cards.has(Res.Dev.MONOPOLY):
		var r := _best_monopoly_resource(st)
		if r >= 0:
			return {"type": Res.A_PLAY_DEV, "card": Res.Dev.MONOPOLY, "r": r, "score": 95.0 * dev_bias}

	# 丰收年：补最缺的两张
	if p.dev_cards.has(Res.Dev.YEAR_OF_PLENTY):
		var need := _two_most_needed(p)
		if need[0] >= 0:
			return {
				"type": Res.A_PLAY_DEV, "card": Res.Dev.YEAR_OF_PLENTY,
				"r1": need[0], "r2": need[1], "score": 90.0 * dev_bias,
			}

	return {}

func _best_monopoly_resource(st: GameState) -> int:
	var best := -1
	var best_n := 0
	for r in Res.R_COUNT:
		var n := 0
		for o in st.players:
			if o.id != pid:
				n += o.resources[r]
		if n > best_n:
			best_n = n
			best = r
	return best if best_n >= 2 else -1

func _two_most_needed(p: PlayerState) -> Array:
	var need: Array = []
	for r in Res.R_COUNT:
		var n := 0
		for cost in [Res.COST_CITY, Res.COST_SETTLEMENT, Res.COST_DEV]:
			n = maxi(n, maxi(0, cost.get(r, 0) - p.resources[r]))
		need.append([r, n])
	need.sort_custom(func(a, b): return a[1] > b[1])
	if need[0][1] <= 0:
		return [-1, -1]
	var second: int = need[1][0] if need.size() > 1 else need[0][0]
	return [need[0][0], second]

# ---------------- 银行交易 ----------------

## 银行交易。两种情形才会换：
##   A) 这一换立刻就能建出高价值建筑（精确补齐）
##   B) 手上某资源严重富余，且换进来的正是所缺的（富余转化）
##
## 为什么需要 B：只做 A 的话，攒了十几张同种资源的 AI 会彻底卡死——
## 因为单次交易永远无法让它"立刻可建"，于是一张张白白烂在手里。
## 实测就出现过白方手握 16 张木材、其余四种全 0 的情况。
##
## 注意不把"修路"算作交易目标：为一条 2 张资源的路付 4:1 汇率是亏的。
func _try_bank_trade(st: GameState) -> Dictionary:
	var p: PlayerState = st.players[pid]
	var before := p.resources.duplicate()
	var best := {}
	var best_gain := 0.0
	for o in Rules.bank_trade_options(st, pid):
		var give_r: int = o[0]
		var take_r: int = o[1]
		var ratio: int = o[2]
		var after := before.duplicate()
		after[give_r] -= ratio
		after[take_r] += 1

		var gain := _newly_affordable_gain(before, after)
		if gain <= 0.0 and _can_spare(before, give_r, ratio) and _is_needed(before, take_r):
			gain = 0.35   # 富余转化：不立刻见效，但朝目标推进
		if gain > best_gain:
			best_gain = gain
			best = {"type": Res.A_BANK_TRADE, "give_r": give_r, "take_r": take_r}
	return best

## 该资源在各类建筑里最多被需要几张
func _max_need(r: int) -> int:
	var need := 0
	for cost in [Res.COST_CITY, Res.COST_SETTLEMENT, Res.COST_DEV, Res.COST_ROAD]:
		need = maxi(need, cost.get(r, 0))
	return need

## 付掉 ratio 张之后，手里还留得住各建筑所需的最大量吗
func _can_spare(res: Array[int], r: int, ratio: int) -> bool:
	return res[r] - ratio >= _max_need(r)

## 该资源是否还缺（少于任一建筑所需的最大量）
func _is_needed(res: Array[int], r: int) -> bool:
	return res[r] < _max_need(r)

func _newly_affordable_gain(before: Array[int], after: Array[int]) -> float:
	var gain := 0.0
	if Evaluation.affordable(after, Res.COST_CITY) and not Evaluation.affordable(before, Res.COST_CITY):
		gain = maxf(gain, 2.0)
	if Evaluation.affordable(after, Res.COST_SETTLEMENT) and not Evaluation.affordable(before, Res.COST_SETTLEMENT):
		gain = maxf(gain, 1.6)
	if Evaluation.affordable(after, Res.COST_DEV) and not Evaluation.affordable(before, Res.COST_DEV):
		gain = maxf(gain, 0.9)
	return gain

# ---------------- 交易应答 ----------------

func respond_trade(st: GameState, offer: Dictionary) -> bool:
	if random_accept > 0.0 and rng.randf() < random_accept:
		return rng.randf() < 0.5

	var me: PlayerState = st.players[pid]
	var got: Dictionary = offer.get("give", {})   # 我能拿到
	var paid: Dictionary = offer.get("get", {})   # 我要付出
	if got.is_empty() or paid.is_empty():
		return false
	if not me.has(paid):
		return false

	var before := me.resources.duplicate()
	var after := me.resources.duplicate()
	for r in paid:
		after[r] -= paid[r]
	for r in got:
		after[r] += got[r]
	var gain := Evaluation.build_progress(after) - Evaluation.build_progress(before)
	if gain <= 0.0:
		return false

	# 发起方能从中拿到多少
	var sender: PlayerState = st.players[offer.get("from", -1)]
	var sb := sender.resources.duplicate()
	var sa := sender.resources.duplicate()
	for r in got:
		sa[r] -= got[r]
	for r in paid:
		sa[r] += paid[r]
	var sgain := Evaluation.build_progress(sa) - Evaluation.build_progress(sb)

	# 对手越接近胜利，越不能喂养他
	var closeness := maxi(0, 6 - Evaluation.threat_level(st, sender.id))
	var risk := trade_risk + float(closeness) * 0.8 * savvy
	return gain > sgain * risk

# ---------------- 可覆写钩子 ----------------

## 选村庄位置的额外加成（困难难度用它来阻断对手）
func _extra_settlement_bonus(_st: GameState, _v: int, _weights: Array) -> float:
	return 0.0

## 选道路的额外加成
func _extra_road_bonus(_st: GameState, _eid: int, _weights: Array) -> float:
	return 0.0

## 主动发起交易（默认不做）
func _try_offer_trade(_st: GameState) -> Dictionary:
	return {}
