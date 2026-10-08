class_name AIMedium
extends AIController

## 标准：纯启发式最优。会算产出期望、按建造效率排序、交易看等价性、
## 强盗打高产出地块。没有前瞻，也没有谈判技巧。

func _init(p_pid: int = 0) -> void:
	super(p_pid)
	noise = 7.0
	dev_bias = 1.0
	road_bias = 1.0
	city_bias = 1.05
	settle_bias = 1.0
	savvy = 0.55
	trade_risk = 1.6
	random_accept = 0.0
	pass_chance = 0.0
	max_offers_per_turn = 0
