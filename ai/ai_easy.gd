class_name AIEasy
extends AIController

## 简单（新手）：评分噪声极大、交易基本靠猜、强盗随便放，还会时不时提前结束回合。
## 目标不是"弱智"，而是"像刚学会规则的朋友"——能建就建，但不做长远规划。

func _init(p_pid: int = 0) -> void:
	super(p_pid)
	noise = 28.0
	dev_bias = 0.6
	road_bias = 0.8
	city_bias = 0.75
	settle_bias = 0.9
	savvy = 0.2
	trade_risk = 0.6
	random_accept = 0.35
	pass_chance = 0.10
	max_offers_per_turn = 0

func choose_action(st: GameState) -> Dictionary:
	# 偶尔"忘了还能干活"，直接过
	if rng.randf() < 0.06:
		return {"type": Res.A_END_TURN}
	return super(st)
