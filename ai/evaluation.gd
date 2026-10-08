class_name Evaluation
extends RefCounted

## AI 共用的评分函数库。三档难度共用这里的"地基"，差异在噪声大小、前瞻、
## 以及是否主动谈判（见 ai_easy / ai_medium / ai_hard）。
##
## 核心思想：把"一个顶点值多少"量化成产出期望值。
##   顶点价值 = Σ(pip值 × 资源权重) + 资源多样性加成 + 港口加成
## 资源权重随游戏阶段变化：
##   开局木材/砖块值钱（铺路），中后期麦子/矿石值钱（升城、买卡）。
##   公开研究显示麦子全程是最关键资源，因此它的权重始终没有低过。

## 资源权重顺序：wood, brick, wool, grain, ore
const WEIGHTS_EARLY := [1.15, 1.15, 0.90, 1.00, 0.80]
const WEIGHTS_MID := [0.95, 0.95, 1.00, 1.15, 1.10]
const WEIGHTS_LATE := [0.85, 0.85, 1.00, 1.20, 1.25]

const DIVERSITY_BONUS := 3.0
const PORT_BONUS_GENERIC := 6.0
const PORT_BONUS_SPECIFIC := 12.0

enum Phase { EARLY, MID, LATE }

# ---------------- 阶段判断 ----------------

## 用公开分数估算场上进度（AI 不该偷看别人的暗牌）
static func phase_of(st: GameState) -> int:
	var total := 0
	for p in st.players:
		total += st.public_victory_points(p.id)
	var avg := float(total) / float(st.players.size())
	if avg < 3.5:
		return Phase.EARLY
	if avg < 6.5:
		return Phase.MID
	return Phase.LATE

static func weights_for(phase: int) -> Array:
	match phase:
		Phase.EARLY:
			return WEIGHTS_EARLY
		Phase.MID:
			return WEIGHTS_MID
	return WEIGHTS_LATE

static func phase_name(phase: int) -> String:
	match phase:
		Phase.EARLY:
			return "early"
		Phase.MID:
			return "mid"
	return "late"

# ---------------- 顶点评分 ----------------

static func vertex_score(st: GameState, v: int, weights: Array = []) -> float:
	if weights.is_empty():
		weights = weights_for(phase_of(st))
	var topo := BoardTopology.instance()
	var score := 0.0
	for hi in topo.vertex_hexes[v]:
		var num: int = st.board.hex_number[hi]
		if num == 0:
			continue
		var r: int = st.board.hex_resource(hi)
		if r < 0:
			continue
		score += float(Res.PIPS.get(num, 0)) * float(weights[r])
	var kinds := st.board.vertex_resource_kinds(v)
	score += float(kinds.size()) * DIVERSITY_BONUS
	var pr: Array = st.board.vertex_port_ratio(v)
	if not pr.is_empty():
		score += PORT_BONUS_SPECIFIC if pr[0] == 2 else PORT_BONUS_GENERIC
	return score

## 顶点被强盗封锁时的产出损失
static func vertex_blocked_penalty(st: GameState, v: int, weights: Array = []) -> float:
	if weights.is_empty():
		weights = weights_for(phase_of(st))
	var topo := BoardTopology.instance()
	var loss := 0.0
	for hi in topo.vertex_hexes[v]:
		if hi != st.board.robber_hex:
			continue
		var num: int = st.board.hex_number[hi]
		if num == 0:
			continue
		var r: int = st.board.hex_resource(hi)
		if r >= 0:
			loss += float(Res.PIPS.get(num, 0)) * float(weights[r])
	return loss

# ---------------- 建造进度 ----------------

## 把"手上资源"折算成一个进度分：越接近能建出高价值建筑分越高。
## 用 frac^2 让"差一张就能建"的边际价值远高于"刚开始攒"。
static func build_progress(res: Array[int]) -> float:
	var targets := [
		[Res.COST_CITY, 12.0],
		[Res.COST_SETTLEMENT, 10.0],
		[Res.COST_DEV, 6.0],
		[Res.COST_ROAD, 4.0],
	]
	var best := 0.0
	for t in targets:
		var cost: Dictionary = t[0]
		var total := 0
		var missing := 0
		for r in cost:
			total += cost[r]
			missing += maxi(0, cost[r] - res[r])
		var frac := 1.0 - float(missing) / float(total)
		best = maxf(best, float(t[1]) * frac * frac)
	return best

## 是否"差 1 张"就能建出某样东西
static func one_away(res: Array[int], cost: Dictionary) -> bool:
	var missing := 0
	for r in cost:
		missing += maxi(0, cost[r] - res[r])
	return missing == 1

static func affordable(res: Array[int], cost: Dictionary) -> bool:
	for r in cost:
		if res[r] < cost[r]:
			return false
	return true

# ---------------- 对手威胁 ----------------

## 某个玩家距离胜利还差多少分（越小越危险）
static func threat_level(st: GameState, pid: int) -> int:
	return Res.WIN_VP - st.public_victory_points(pid)
