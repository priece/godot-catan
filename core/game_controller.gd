class_name GameController
extends RefCounted

## 回合调度器：把规则跑成"一局完整的游戏"。
##
## 对外两条用法，共用同一套逻辑：
##
##   1) 无人值守批量跑（headless 验收用）
##        new_game(...) -> run() -> 读 st.winner
##
##   2) 交互式逐帧驱动（界面用）
##        new_game(...)
##        while 初始布置未完成:  setup_pid / setup_valid_* / setup_apply_*
##        while 未结束:          begin_turn() -> 反复 apply_action() -> finish_turn() -> advance_player()
##
## 所有决策都通过 IntentProvider 拿，控制器不区分人机；
## 人类玩家的"想做什么"由界面直接调用 apply_action() 提交。

var st: GameState
var providers: Array = []      ## pid -> IntentProvider
var topo: BoardTopology

# ---------------- 开局 ----------------

## configs: [{is_ai, difficulty, label}, ...]；provider_list 与 configs 一一对应
func new_game(configs: Array, seed: int, beginner: bool, provider_list: Array) -> void:
	topo = BoardTopology.instance()
	st = GameState.new()
	st.rng = RandomNumberGenerator.new()
	st.rng.seed = seed
	st.board = Board.generate(seed, beginner)
	providers = provider_list

	for i in configs.size():
		var p := PlayerState.new(i)
		p.is_ai = configs[i].get("is_ai", true)
		p.difficulty = configs[i].get("difficulty", 1)
		p.label = configs[i].get("label", "P%d" % i)
		st.players.append(p)

	var deck: Array[int] = []
	for d in Res.DEV_COUNTS:
		for i in Res.DEV_COUNTS[d]:
			deck.append(d)
	_shuffle(deck, st.rng)
	st.dev_deck = deck

	# 蛇形初始顺序：0 1 2 3 3 2 1 0
	var order: Array[int] = []
	for i in st.players.size():
		order.append(i)
	for i in range(st.players.size() - 1, -1, -1):
		order.append(i)
	st.setup_order = order
	st.setup_index = 0
	st.setup_stage = 0
	st.phase = GameState.Phase.SETUP
	st.current = order[0]

func is_ai(pid: int) -> bool:
	return st.players[pid].is_ai

## 日志里用的玩家称呼（"你" / "电脑·标准"）。用 label 而不是 P0/P1，
## 这样日志读起来像游戏而不是调试输出。
func _pn(pid: int) -> String:
	if pid >= 0 and pid < st.players.size():
		return st.players[pid].label
	return "P%d" % pid

# ================= 初始布置 =================

func setup_is_over() -> bool:
	return st.setup_index >= st.setup_order.size()

## 当前该谁来放；已结束返回 -1
func setup_pid() -> int:
	if setup_is_over():
		return -1
	return st.setup_order[st.setup_index]

func setup_stage() -> int:
	return st.setup_stage

func setup_anchor() -> int:
	return st.setup_anchor

## 该玩家此阶段能放的位置（村庄阶段返回顶点，道路阶段返回边）
func setup_valid_spots() -> Array[int]:
	var pid := setup_pid()
	if pid < 0:
		return []
	if st.setup_stage == 0:
		return Rules.valid_settlement_vertices(st, pid, true)
	return Rules.valid_road_edges(st, pid, true, st.setup_anchor)

## 提交一次初始放置。成功返回 true（界面点错位置不会崩）。
func setup_apply(spot: int) -> bool:
	var pid := setup_pid()
	if pid < 0:
		return false
	if st.setup_stage == 0:
		if not Rules.valid_settlement_vertices(st, pid, true).has(spot):
			return false
		_place_settlement_raw(pid, spot)
		st.setup_anchor = spot
		st.setup_stage = 1
		# 第二座村庄立刻领起始资源
		if st.setup_index >= st.num_players():
			_grant_starting_resources(pid, spot)
		return true
	else:
		if not Rules.valid_road_edges(st, pid, true, st.setup_anchor).has(spot):
			return false
		_place_road_raw(pid, spot)
		st.setup_stage = 0
		st.setup_index += 1
		if setup_is_over():
			st.phase = GameState.Phase.MAIN
			st.current = 0
			st.log_line("初始布置完成")
			_begin_round(1)
		return true

func _grant_starting_resources(pid: int, v: int) -> void:
	var p: PlayerState = st.players[pid]
	for hi in topo.vertex_hexes[v]:
		var r: int = st.board.hex_resource(hi)
		if r >= 0:
			p.gain(r, st.bank_take(r, 1))

## 让 AI 走完整个初始布置（headless 用）
func run_setup() -> void:
	if st.phase != GameState.Phase.SETUP:
		return
	for p in st.players:
		providers[p.id].on_game_start(st)
	while not setup_is_over():
		var pid := setup_pid()
		st.current = pid
		var valid := setup_valid_spots()
		if valid.is_empty():
			push_error("初始布置失败：P%d 无合法位置" % pid)
			return
		var choice: int = providers[pid].choose_initial_settlement(st, valid) if st.setup_stage == 0 \
			else providers[pid].choose_initial_road(st, st.setup_anchor, valid)
		if not valid.has(choice):
			choice = valid[0]
		setup_apply(choice)

# ================= 回合 =================

## 开始当前玩家的回合：重置标记 + 掷骰 + 产出（或触发强盗）
func begin_turn(pid: int = -1) -> void:
	if pid < 0:
		pid = st.current
	st.current = pid
	st.dev_played_this_turn = false
	st.free_roads_remaining = 0
	st.turn_actions_done = 0

	providers[pid].on_turn_start(st)

	var d1 := st.rng.randi_range(1, 6)
	var d2 := st.rng.randi_range(1, 6)
	st.dice = d1 + d2
	# 用【名字】开头，让"每个玩家的回合从哪开始"一眼可见 —— 掷骰是每回合第一件事，
	# 拿它当回合分隔比再插一条横线更省地方，也不会把日志撑得太空。
	st.log_line("【%s】掷出 %d（%d+%d）" % [_pn(pid), st.dice, d1, d2])

	if st.dice == 7:
		_handle_seven_discards(pid)
		st.pending_robber = true
	else:
		_produce(st.dice)

func finish_turn(pid: int = -1) -> void:
	if pid < 0:
		pid = st.current
	var p: PlayerState = st.players[pid]
	p.dev_cards.append_array(p.fresh_dev_cards)
	p.fresh_dev_cards.clear()
	st.dev_played_this_turn = false
	st.free_roads_remaining = 0

func advance_player() -> void:
	st.current = (st.current + 1) % st.num_players()
	if st.current == 0:
		_begin_round(st.round + 1)

## 开新一轮：写一条醒目的分隔，方便在长日志里定位。
## st.round 是 1 起算的"当前第几轮"。
func _begin_round(n: int) -> void:
	st.round = n
	st.log_line("")
	st.log_line("[color=#8a8378]━━━━━━━  第 %d 轮  ━━━━━━━[/color]" % n)

# ---------------- 资源产出 ----------------

func _produce(number: int) -> void:
	var occ := Rules.occupancy_map(st)
	var claims: Array = []
	for hi in st.board.producing_hexes(number):
		var r: int = st.board.hex_resource(hi)
		if r < 0:
			continue
		for v in topo.hex_vertices[hi]:
			var owner: int = occ.get(v, -1)
			if owner < 0:
				continue
			var amt := 2 if st.players[owner].cities.has(v) else 1
			claims.append([owner, r, amt])
	# 银行不足时按顺序发放（官方规则：牌库耗尽则该资源不再产出）
	for c in claims:
		var got := st.bank_take(c[1], c[2])
		if got > 0:
			st.players[c[0]].gain(c[1], got)

# ---------------- 强盗 ----------------

func _handle_seven_discards(pid: int) -> void:
	for p in st.players:
		var n := Rules.discard_count(p)
		if n <= 0:
			continue
		var picks: Array[int] = providers[p.id].choose_discard(st, n)
		var applied := 0
		for r in picks:
			if applied >= n:
				break
			if p.resources[r] > 0:
				p.resources[r] -= 1
				st.bank_give(r, 1)
				applied += 1
		while applied < n:
			var r := _most_abundant(p)
			if r < 0:
				break
			p.resources[r] -= 1
			st.bank_give(r, 1)
			applied += 1
	st.log_line("掷出 7：强盗发动")

func has_pending_robber() -> bool:
	return st.pending_robber

func valid_robber_hexes() -> Array[int]:
	return Rules.valid_robber_hexes(st)

## 把强盗放到指定地块并偷牌（人类点地块 / AI 决策后都走这里）
func place_robber(pid: int, hex: int) -> void:
	st.board.robber_hex = hex
	st.pending_robber = false
	var cands := Rules.steal_candidates(st, hex, pid)
	if cands.is_empty():
		st.log_line("%s 移动了强盗（周围无人可偷）" % _pn(pid))
		return
	var target: int = providers[pid].choose_steal_target(st, cands)
	if not cands.has(target):
		target = cands[0]
	_steal(pid, target)

func _steal(pid: int, target: int) -> void:
	var tp: PlayerState = st.players[target]
	var pool: Array[int] = []
	for r in Res.R_COUNT:
		for i in tp.resources[r]:
			pool.append(r)
	if pool.is_empty():
		return
	var pick: int = pool[st.rng.randi_range(0, pool.size() - 1)]
	tp.lose(pick, 1)
	st.players[pid].gain(pick, 1)
	st.log_line("%s 从 %s 手里偷走 1 张 %s" % [_pn(pid), _pn(target), Res.R_NAMES_CN[pick]])

## 让当前玩家自己决定强盗位置（AI 用）
func auto_resolve_robber(pid: int) -> void:
	if not st.pending_robber:
		return
	var valid := valid_robber_hexes()
	if valid.is_empty():
		st.pending_robber = false
		return
	var h: int = providers[pid].choose_robber_hex(st, valid)
	if not valid.has(h):
		h = valid[0]
	place_robber(pid, h)

func _most_abundant(p: PlayerState) -> int:
	var best := -1
	var best_n := 0
	for r in Res.R_COUNT:
		if p.resources[r] > best_n:
			best_n = p.resources[r]
			best = r
	return best

# ================= 动作 =================

## 问 AI 想做什么
func ai_action(pid: int) -> Dictionary:
	return providers[pid].choose_action(st)

## 通知决策方某个动作非法，请换一个
func notify_invalid(pid: int, action: Dictionary) -> void:
	providers[pid].on_invalid_action(st, action)

## 执行一个动作。非法返回 false（不会破坏状态）。
func apply_action(pid: int, action: Dictionary) -> bool:
	var p: PlayerState = st.players[pid]
	match action.get("type", ""):
		Res.A_PLACE_SETTLEMENT:
			var v: int = action.get("vertex", -1)
			if not Rules.valid_settlement_vertices(st, pid, false).has(v):
				return false
			if not p.has(Res.COST_SETTLEMENT):
				return false
			p.pay(Res.COST_SETTLEMENT)
			st.bank_give_bundle(_cost_to_bank(Res.COST_SETTLEMENT))
			_place_settlement_raw(pid, v)
			st.log_line("%s 建了一座村庄" % _pn(pid))
			return true

		Res.A_PLACE_ROAD:
			var e: int = action.get("edge", -1)
			if not Rules.valid_road_edges(st, pid, false).has(e):
				return false
			if st.free_roads_remaining > 0:
				st.free_roads_remaining -= 1
			else:
				if not p.has(Res.COST_ROAD):
					return false
				p.pay(Res.COST_ROAD)
				st.bank_give_bundle(_cost_to_bank(Res.COST_ROAD))
			_place_road_raw(pid, e)
			st.log_line("%s 修了一条路" % _pn(pid))
			return true

		Res.A_UPGRADE_CITY:
			var v: int = action.get("vertex", -1)
			if not Rules.valid_city_vertices(st, pid).has(v):
				return false
			if not p.has(Res.COST_CITY):
				return false
			p.pay(Res.COST_CITY)
			st.bank_give_bundle(_cost_to_bank(Res.COST_CITY))
			p.settlements.erase(v)
			p.cities.append(v)
			st.log_line("%s 把村庄升级成了城市" % _pn(pid))
			return true

		Res.A_BUY_DEV:
			if not Rules.can_buy_dev(st, pid):
				return false
			p.pay(Res.COST_DEV)
			st.bank_give_bundle(_cost_to_bank(Res.COST_DEV))
			var c := st.draw_dev_card()
			if c < 0:
				return false
			p.fresh_dev_cards.append(c)
			st.log_line("%s 买了一张发展卡" % _pn(pid))
			return true

		Res.A_PLAY_DEV:
			return _play_dev_card(pid, action)

		Res.A_BANK_TRADE:
			var gr: int = action.get("give_r", -1)
			var tr: int = action.get("take_r", -1)
			if not Rules.can_bank_trade(st, pid, gr, tr):
				return false
			var ratio := Rules.best_ratio_for(st, pid, gr)
			p.lose(gr, ratio)
			st.bank_give(gr, ratio)
			st.bank_take(tr, 1)
			p.gain(tr, 1)
			st.log_line("%s 向银行兑换：%d %s → 1 %s" % [_pn(pid), ratio, Res.R_NAMES_CN[gr], Res.R_NAMES_CN[tr]])
			return true

		Res.A_OFFER_TRADE:
			return _resolve_offer(pid, action)

	return false

func _play_dev_card(pid: int, action: Dictionary) -> bool:
	var p: PlayerState = st.players[pid]
	if st.dev_played_this_turn:
		return false
	var card: int = action.get("card", -1)
	if card < 0 or not p.dev_cards.has(card):
		return false
	if card == Res.Dev.VICTORY:
		return false   # 胜利点卡自动计分，无需打出

	match card:
		Res.Dev.KNIGHT:
			p.dev_cards.erase(card)
			p.played_knights += 1
			st.dev_played_this_turn = true
			st.pending_robber = true
			_update_largest_army()
			st.log_line("%s 打出骑士" % _pn(pid))
			return true

		Res.Dev.ROAD_BUILDING:
			p.dev_cards.erase(card)
			st.dev_played_this_turn = true
			st.free_roads_remaining += 2
			st.log_line("%s 打出修路卡，可免费放 2 条路" % _pn(pid))
			return true

		Res.Dev.YEAR_OF_PLENTY:
			var r1: int = action.get("r1", -1)
			var r2: int = action.get("r2", -1)
			if r1 < 0 or r2 < 0:
				return false
			p.dev_cards.erase(card)
			st.dev_played_this_turn = true
			p.gain(r1, st.bank_take(r1, 1))
			p.gain(r2, st.bank_take(r2, 1))
			st.log_line("%s 打出丰收年：取得 %s、%s" % [_pn(pid), Res.R_NAMES_CN[r1], Res.R_NAMES_CN[r2]])
			return true

		Res.Dev.MONOPOLY:
			var r: int = action.get("r", -1)
			if r < 0:
				return false
			p.dev_cards.erase(card)
			st.dev_played_this_turn = true
			var taken := 0
			for other in st.players:
				if other.id == pid:
					continue
				taken += other.resources[r]
				other.resources[r] = 0
			p.gain(r, taken)
			st.log_line("%s 打出垄断卡，收走全场 %d 张 %s" % [_pn(pid), taken, Res.R_NAMES_CN[r]])
			return true

	return false

func _resolve_offer(pid: int, action: Dictionary) -> bool:
	var give: Dictionary = action.get("give", {})
	var want: Dictionary = action.get("get", {})
	if give.is_empty() or want.is_empty():
		return false
	var p: PlayerState = st.players[pid]
	if not p.has(give):
		return false
	for other in st.players:
		if other.id == pid:
			continue
		if not other.has(want):
			continue
		var offer := {"from": pid, "to": other.id, "give": give, "get": want}
		if providers[other.id].respond_trade(st, offer):
			for r in give:
				p.lose(r, give[r])
				other.gain(r, give[r])
			for r in want:
				other.lose(r, want[r])
				p.gain(r, want[r])
			st.log_line("%s 用 %s 从 %s 换到 %s" % [
				_pn(pid), _fmt_bundle(give), _pn(other.id), _fmt_bundle(want)])
			return true
	return false

func _fmt_bundle(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	for r in bundle:
		parts.append("%d %s" % [bundle[r], Res.R_NAMES_CN[r]])
	return "、".join(parts) if not parts.is_empty() else "无"

# ---------------- 建筑落子 ----------------

func _place_settlement_raw(pid: int, v: int) -> void:
	st.players[pid].settlements.append(v)
	_update_longest_road()

func _place_road_raw(pid: int, e: int) -> void:
	st.players[pid].roads.append(e)
	_update_longest_road()

# ---------------- 奖励裁定 ----------------

func _update_longest_road() -> void:
	LongestRoad.update_owner(topo, st)

func _update_largest_army() -> void:
	var counts := {}
	var maxn := 0
	for p in st.players:
		counts[p.id] = p.played_knights
		maxn = maxi(maxn, p.played_knights)

	if maxn < Res.LARGEST_ARMY_MIN:
		st.largest_army_owner = -1
		return

	var cands: Array[int] = []
	for pid in counts:
		if counts[pid] == maxn:
			cands.append(pid)

	if cands.size() == 1:
		st.largest_army_owner = cands[0]
	elif st.largest_army_owner in cands:
		pass   # 并列时当前持有者保留
	else:
		st.largest_army_owner = -1

# ---------------- 胜负 ----------------

func check_win() -> bool:
	if st.is_over():
		return true
	for p in st.players:
		if st.victory_points(p.id) >= Res.WIN_VP:
			st.winner = p.id
			st.phase = GameState.Phase.GAME_OVER
			st.log_line("%s 达到 %d 分，获胜！" % [_pn(p.id), st.victory_points(p.id)])
			return true
	return false

func _highest_vp() -> int:
	var best := -1
	var bestv := -1
	var tie := false
	for p in st.players:
		var v := st.victory_points(p.id)
		if v > bestv:
			bestv = v
			best = p.id
			tie = false
		elif v == bestv:
			tie = true
	return best if not tie else -1

# ================= 无人值守跑完整局 =================

func run(max_rounds: int = 300) -> int:
	if st.phase == GameState.Phase.SETUP:
		run_setup()

	var max_turns: int = max_rounds * st.num_players()
	var turns := 0
	while not st.is_over() and turns < max_turns:
		_auto_turn(st.current)
		turns += 1
		if st.is_over():
			break
		advance_player()

	if not st.is_over():
		st.timed_out = true
		st.winner = _highest_vp()
		st.phase = GameState.Phase.GAME_OVER

	for p in st.players:
		providers[p.id].on_game_end(st)
	return st.winner

func _auto_turn(pid: int) -> void:
	begin_turn(pid)
	auto_resolve_robber(pid)

	var guard := 0
	var fails := 0
	while not st.is_over():
		guard += 1
		if guard > 400:
			push_error("回合动作数异常，强制结束 P%d 回合" % pid)
			break
		var action: Dictionary = ai_action(pid)
		var atype: String = action.get("type", Res.A_END_TURN)
		if atype == Res.A_END_TURN or atype == "":
			break
		if not apply_action(pid, action):
			fails += 1
			notify_invalid(pid, action)
			if fails >= 4:
				break
			continue
		fails = 0
		st.turn_actions_done += 1
		if st.pending_robber:
			auto_resolve_robber(pid)
		check_win()

	finish_turn(pid)

# ---------------- 工具 ----------------

func _cost_to_bank(cost: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0, 0]
	for k in cost:
		out[k] = cost[k]
	return out

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
