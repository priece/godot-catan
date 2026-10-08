class_name AIHard
extends AIController

## 困难（老手）：零噪声、主动阻断对手扩张、优先冲最长道路、
## 会主动发起对自己有利的交易，并且对"喂养领先者"极度警惕。
##
## 设计依据来自公开的卡坦岛对局仿真结论：
##   - 最长道路是最常见的制胜路径（占 56~61% 的胜局），所以冲刺阈值一到位就加权重
##   - 第 3 座村庄的建成时间与胜负相关性最强，所以村庄优先级略高于发展卡
##   - 绝不把对手送到 10 分，所以 trade_risk 随对手分数逼近而急剧上升

func _init(p_pid: int = 0) -> void:
	super(p_pid)
	noise = 0.0
	dev_bias = 1.15
	road_bias = 1.10
	city_bias = 1.30
	settle_bias = 1.15
	savvy = 1.0
	trade_risk = 2.6
	random_accept = 0.0
	pass_chance = 0.0
	max_offers_per_turn = 1

## 选村庄位置：额外抢对手道路端点 / 领先者旁边的地
func _extra_settlement_bonus(st: GameState, v: int, weights: Array) -> float:
	var bonus := 0.0
	for o in st.players:
		if o.id == pid:
			continue
		for eid in o.roads:
			var e: Vector2i = topo.edges[eid]
			if e.x == v or e.y == v:
				bonus += 6.0
				break
	var lead := st.leader()
	if lead >= 0 and lead != pid:
		for eid in st.players[lead].roads:
			var e2: Vector2i = topo.edges[eid]
			if e2.x == v or e2.y == v:
				bonus += 4.0
				break
	return bonus

## 修路：优先贴着对手的路修，卡住他的扩展方向（权重刻意压低，避免路修太多）
func _extra_road_bonus(st: GameState, eid: int, weights: Array) -> float:
	var bonus := 0.0
	for o in st.players:
		if o.id == pid:
			continue
		for oe in o.roads:
			if topo.edge_neighbors[eid].has(oe):
				bonus += 3.0
				return bonus
	return bonus

## 主动发起交易：只在"自己卡住了"时才求人，避免把好牌白白换出去
func _try_offer_trade(st: GameState) -> Dictionary:
	var p: PlayerState = st.players[pid]
	if p.has(Res.COST_SETTLEMENT) or p.has(Res.COST_CITY):
		return {}

	var need := _two_most_needed(p)
	var want_r: int = need[0]
	if want_r < 0:
		return {}

	# 找一张自己明显富余、又愿意割舍的资源
	var surplus_r := -1
	for r in Res.R_COUNT:
		if r == want_r or p.resources[r] < 2:
			continue
		if surplus_r < 0 or p.resources[r] > p.resources[surplus_r]:
			surplus_r = r
	if surplus_r < 0:
		return {}

	for o in st.players:
		if o.id == pid:
			continue
		if o.resources[want_r] <= 0:
			continue
		if o.resources[surplus_r] >= 3:
			continue   # 他也不缺，换了没意义
		return {
			"type": Res.A_OFFER_TRADE,
			"give": {surplus_r: 1},
			"get": {want_r: 1},
			"target": o.id,
			"score": 56.0,
		}
	return {}
