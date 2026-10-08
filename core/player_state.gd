class_name PlayerState
extends RefCounted

## 单个玩家的全部状态。纯数据 + 资源增减工具。

var id: int = 0
var is_ai: bool = true
var difficulty: int = 1          ## 0 简单 / 1 标准 / 2 困难
var label: String = ""

var resources: Array[int] = [0, 0, 0, 0, 0]

var dev_cards: Array[int] = []        ## 可打的发展卡（已过购买回合）
var fresh_dev_cards: Array[int] = []  ## 本回合刚买的，当回合不能打
var played_knights: int = 0

var settlements: Array[int] = []      ## 顶点 id
var cities: Array[int] = []           ## 顶点 id
var roads: Array[int] = []            ## 边 id

func _init(p_id: int = 0) -> void:
	id = p_id
	label = "P%d" % p_id

# ---------------- 资源 ----------------

func total_resources() -> int:
	var t := 0
	for v in resources:
		t += v
	return t

func count(r: int) -> int:
	return resources[r]

func gain(r: int, n: int = 1) -> void:
	if r >= 0 and r < Res.R_COUNT:
		resources[r] += n

func lose(r: int, n: int = 1) -> void:
	if r >= 0 and r < Res.R_COUNT:
		resources[r] = maxi(0, resources[r] - n)

func has(cost: Dictionary) -> bool:
	for k in cost:
		if resources[k] < cost[k]:
			return false
	return true

func pay(cost: Dictionary) -> void:
	for k in cost:
		resources[k] -= cost[k]

func gain_bundle(bundle: Array[int]) -> void:
	for i in mini(bundle.size(), Res.R_COUNT):
		resources[i] += bundle[i]

## 把 [r,count,r,count,...] 之类的稀疏描述转成完整数组
func resource_bundle() -> Array[int]:
	return resources.duplicate()

# ---------------- 建筑 ----------------

func piece_road_count() -> int:
	return roads.size()

func piece_settlement_count() -> int:
	return settlements.size()

func piece_city_count() -> int:
	return cities.size()

func all_vertices() -> Array[int]:
	var out: Array[int] = []
	out.append_array(settlements)
	out.append_array(cities)
	return out

func has_building_at(v: int) -> bool:
	return settlements.has(v) or cities.has(v)

# ---------------- 发展卡 ----------------

func total_victory_cards() -> int:
	return dev_cards.count(Res.Dev.VICTORY) + fresh_dev_cards.count(Res.Dev.VICTORY)

## 不含最长道路 / 最大军队奖励的分数
func base_vp() -> int:
	return settlements.size() + cities.size() * 2 + total_victory_cards()

func hand_dev_count() -> int:
	return dev_cards.size() + fresh_dev_cards.size()

func describe_resources() -> String:
	var parts: Array[String] = []
	for i in Res.R_COUNT:
		if resources[i] > 0:
			parts.append("%s%d" % [Res.R_NAMES[i], resources[i]])
	return " ".join(parts) if not parts.is_empty() else "-"
