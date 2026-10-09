class_name GameState
extends RefCounted

## 一局游戏的完整状态。纯数据，不含任何规则判断（规则在 Rules / GameController）。

enum Phase { SETUP, MAIN, GAME_OVER }

var board: Board
var players: Array = []                ## Array[PlayerState]

var current: int = 0                   ## 当前行动玩家 id
var phase: int = Phase.SETUP
var round: int = 0                     ## 完整轮数
var dice: int = 0
## 本回合骰子是否已掷出。
## ⚠️ 不能用 dice == 0 判断"还没掷"——上一回合的值会残留到下一回合，
## 骑士在掷骰前打出时必须靠这个标记才能知道"放完强盗该回掷骰还是进主阶段"。
var dice_rolled: bool = false
var turn_actions_done: int = 0         ## 本回合已执行的动作数（保险丝）
var dev_played_this_turn: bool = false ## 每回合最多打 1 张发展卡
var free_roads_remaining: int = 0      ## 修路卡剩余的免费道路数
var pending_robber: bool = false       ## 强盗待放置（掷出 7 或打出骑士后）
var timed_out: bool = false            ## 超过回合上限被强制结束

## 发展卡牌库
var dev_deck: Array[int] = []
var dev_deck_pos: int = 0

## 银行资源（每种 19 张，耗尽后不再产出）
var bank: Array[int] = [19, 19, 19, 19, 19]

## 奖励归属
var longest_road_owner: int = -1
var largest_army_owner: int = -1

## 初始布置阶段
var setup_order: Array[int] = []       ## 蛇形顺序
var setup_index: int = 0
var setup_stage: int = 0               ## 0 放村庄 / 1 放道路
var setup_anchor: int = -1             ## 刚放下的村庄顶点（用于放路）
var setup_placed_count: int = 0

var winner: int = -1

var rng: RandomNumberGenerator
var log_enabled: bool = false
var log_lines: Array[String] = []

func num_players() -> int:
	return players.size()

func player(pid: int) -> PlayerState:
	return players[pid]

func is_over() -> bool:
	return winner >= 0

# ---------------- 分数 ----------------

func victory_points(pid: int) -> int:
	var vp: int = players[pid].base_vp()
	if longest_road_owner == pid:
		vp += 2
	if largest_army_owner == pid:
		vp += 2
	return vp

## 公开分数（不含暗置的胜利点卡）——AI 判断局势时只能用这个
func public_victory_points(pid: int) -> int:
	var p: PlayerState = players[pid]
	var vp: int = p.settlements.size() + p.cities.size() * 2
	if longest_road_owner == pid:
		vp += 2
	if largest_army_owner == pid:
		vp += 2
	return vp

func leader() -> int:
	var best := -1
	var best_vp := -1
	for p in players:
		var v: int = public_victory_points(p.id)
		if v > best_vp:
			best_vp = v
			best = p.id
	return best

# ---------------- 发展卡 ----------------

func dev_deck_remaining() -> int:
	return dev_deck.size() - dev_deck_pos

func draw_dev_card() -> int:
	if dev_deck_pos >= dev_deck.size():
		return -1
	var c: int = dev_deck[dev_deck_pos]
	dev_deck_pos += 1
	return c

# ---------------- 银行 ----------------

func bank_take(r: int, n: int) -> int:
	var got: int = mini(n, bank[r])
	bank[r] -= got
	return got

func bank_give(r: int, n: int) -> void:
	bank[r] += n

func bank_give_bundle(b: Array[int]) -> void:
	for i in mini(b.size(), Res.R_COUNT):
		bank[i] += b[i]

# ---------------- 日志 ----------------

## 日志上限只作内存兜底，不是"只留最近若干条"的意思。
## 单局卡坦岛大约产生几百条事件，正常情况永远触不到这个上限。
const LOG_CAP := 20000

func log_line(s: String) -> void:
	if log_enabled:
		log_lines.append(s)
		if log_lines.size() > LOG_CAP:
			log_lines.pop_front()
