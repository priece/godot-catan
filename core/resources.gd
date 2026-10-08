class_name Res
extends RefCounted

## 卡坦岛基础版的全部常量：资源、地形、发展卡、港口、建造花费、上限。
## 全部走常量表，方便后续把数值导出到 .tres 做数据驱动。

# ---------------- 资源 ----------------
enum R { WOOD, BRICK, WOOL, GRAIN, ORE }
const R_COUNT := 5
const R_NAMES := ["wood", "brick", "wool", "grain", "ore"]
const R_NAMES_CN := ["木材", "砖块", "羊毛", "麦子", "矿石"]

# ---------------- 地形 ----------------
enum Terrain { FOREST, HILLS, PASTURE, FIELDS, MOUNTAINS, DESERT }
const TERRAIN_NAMES := ["forest", "hills", "pasture", "fields", "mountains", "desert"]
const TERRAIN_CN := ["森林", "丘陵", "牧场", "麦田", "山脉", "沙漠"]

## 地形 -> 产出的资源；沙漠为 -1
const TERRAIN_RES := {
	Terrain.FOREST: R.WOOD,
	Terrain.HILLS: R.BRICK,
	Terrain.PASTURE: R.WOOL,
	Terrain.FIELDS: R.GRAIN,
	Terrain.MOUNTAINS: R.ORE,
	Terrain.DESERT: -1,
}

## 地形张数，合计 19
const TERRAIN_COUNTS := {
	Terrain.FOREST: 4,
	Terrain.PASTURE: 4,
	Terrain.FIELDS: 4,
	Terrain.HILLS: 3,
	Terrain.MOUNTAINS: 3,
	Terrain.DESERT: 1,
}

# ---------------- 数字 token ----------------
## 18 个数字（沙漠不放），2 和 12 各一个
const NUMBER_TOKENS := [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]

## 两骰掷出某总和的组合数（共 36 种）
const PIPS := {2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3, 11: 2, 12: 1}

# ---------------- 发展卡 ----------------
enum Dev { KNIGHT, VICTORY, ROAD_BUILDING, YEAR_OF_PLENTY, MONOPOLY }
const DEV_NAMES := ["knight", "victory", "road_building", "year_of_plenty", "monopoly"]
## 牌库构成，合计 25 张
const DEV_COUNTS := {
	Dev.KNIGHT: 14,
	Dev.VICTORY: 5,
	Dev.ROAD_BUILDING: 2,
	Dev.YEAR_OF_PLENTY: 2,
	Dev.MONOPOLY: 2,
}

# ---------------- 港口 ----------------
## GENERIC_3 = 通用 3:1；其余为指定资源 2:1
enum Port { GENERIC_3, WOOD_2, BRICK_2, WOOL_2, GRAIN_2, ORE_2 }
const PORT_COUNT := 9

# ---------------- 建造花费 ----------------
const COST_ROAD := {R.WOOD: 1, R.BRICK: 1}
const COST_SETTLEMENT := {R.WOOD: 1, R.BRICK: 1, R.WOOL: 1, R.GRAIN: 1}
const COST_CITY := {R.GRAIN: 2, R.ORE: 3}
const COST_DEV := {R.WOOL: 1, R.GRAIN: 1, R.ORE: 1}

# ---------------- 数量上限 ----------------
const LIMIT_ROAD := 15
const LIMIT_SETTLEMENT := 5
const LIMIT_CITY := 4

# ---------------- 胜利条件 ----------------
const WIN_VP := 10
const LONGEST_ROAD_MIN := 5
const LARGEST_ARMY_MIN := 3

# ---------------- 动作类型 ----------------
const A_SKIP := "skip"
const A_PLACE_SETTLEMENT := "place_settlement"
const A_PLACE_ROAD := "place_road"
const A_UPGRADE_CITY := "upgrade_city"
const A_BUY_DEV := "buy_dev"
const A_PLAY_DEV := "play_dev"
const A_MOVE_ROBBER := "move_robber"
const A_DISCARD := "discard"
const A_BANK_TRADE := "bank_trade"
const A_OFFER_TRADE := "offer_trade"
const A_END_TURN := "end_turn"

# ---------------- 工具函数 ----------------

## 港口 -> [需要付出的同种资源张数, 指定资源(通用港为 -1)]
static func port_ratio(port: int) -> Array:
	if port == Port.GENERIC_3:
		return [3, -1]
	return [2, port - 1]

## 从花费字典算出总张数
static func cost_total(cost: Dictionary) -> int:
	var t := 0
	for k in cost:
		t += cost[k]
	return t
