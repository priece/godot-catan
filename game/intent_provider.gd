class_name IntentProvider
extends RefCounted

## 决策接口。AI 与人类玩家都实现它，GameController 不区分对面是人是机。
##
## 约定：所有方法只读 GameState，返回"想做什么"，绝不直接改状态。
## 控制器负责校验 + 执行。返回非法值时控制器会兜底（取候选列表第一项或结束回合），
## 因此一个实现再差也不会把游戏跑崩。

var pid: int = 0

func _init(p_pid: int = 0) -> void:
	pid = p_pid

# ---------------- 初始布置 ----------------

func choose_initial_settlement(_st: GameState, valid: Array[int]) -> int:
	return valid[0] if not valid.is_empty() else -1

func choose_initial_road(_st: GameState, _anchor: int, valid: Array[int]) -> int:
	return valid[0] if not valid.is_empty() else -1

# ---------------- 强盗 / 弃牌 ----------------

func choose_discard(st: GameState, count: int) -> Array[int]:
	return _greedy_discard(st.players[pid], count)

func choose_robber_hex(_st: GameState, valid: Array[int]) -> int:
	return valid[0] if not valid.is_empty() else -1

func choose_steal_target(_st: GameState, candidates: Array[int]) -> int:
	return candidates[0] if not candidates.is_empty() else -1

# ---------------- 主阶段 ----------------

## 返回一个动作 Dictionary，或 {"type": "end_turn"} 结束回合
func choose_action(_st: GameState) -> Dictionary:
	return {"type": Res.A_END_TURN}

## 是否接受当前玩家发起的交易（offer 里给的是"发起方"的视角）
func respond_trade(_st: GameState, _offer: Dictionary) -> bool:
	return false

# ---------------- 生命周期钩子（表现层用） ----------------

func on_game_start(_st: GameState) -> void:
	pass

func on_turn_start(_st: GameState) -> void:
	pass

## 控制器发现返回的动作非法时回调，供实现方把该动作拉黑、换个选择继续本回合
func on_invalid_action(_st: GameState, _action: Dictionary) -> void:
	pass

func on_game_end(_st: GameState) -> void:
	pass

# ---------------- 通用工具 ----------------

## 默认弃牌策略：优先弃手上最多的资源（不修改任何状态）
func _greedy_discard(p: PlayerState, count: int) -> Array[int]:
	var out: Array[int] = []
	var remain := count
	var avail := p.resources.duplicate()
	var order: Array[int] = [0, 1, 2, 3, 4]
	order.sort_custom(func(a, b): return avail[a] > avail[b])
	for r in order:
		while remain > 0 and avail[r] > 0:
			out.append(r)
			avail[r] -= 1
			remain -= 1
	return out
