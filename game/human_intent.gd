class_name HumanIntent
extends IntentProvider

## 人类玩家的决策占位。
##
## 真正的"我想建什么"由界面直接调用 GameController.apply_action() 提交，
## 所以 choose_action 永远不该被调用。这里只兜底三类"来不及问玩家"的时机：
##   1. 被要求弃牌 —— 按最优方式自动弃（M2 阶段不打断玩家）
##   2. 强盗落点与偷牌对象 —— 界面会覆盖，这里给个合理默认
##   3. 别人向你提议交易 —— 自动拒绝，但把提议内容写进日志，让玩家至少看得见

func choose_action(_st: GameState) -> Dictionary:
	return {"type": Res.A_END_TURN}

func choose_discard(st: GameState, count: int) -> Array[int]:
	return _greedy_discard(st.players[pid], count)

func choose_robber_hex(_st: GameState, valid: Array[int]) -> int:
	return valid[0] if not valid.is_empty() else -1

func choose_steal_target(st: GameState, candidates: Array[int]) -> int:
	var best: int = candidates[0]
	for c in candidates:
		if st.players[c].total_resources() > st.players[best].total_resources():
			best = c
	return best

## M2 阶段自动拒绝，但写进日志
func respond_trade(st: GameState, offer: Dictionary) -> bool:
	var sender: int = offer.get("from", -1)
	var got: Dictionary = offer.get("give", {})
	var paid: Dictionary = offer.get("get", {})
	st.log_line("P%d 向你提议：给你 %s，要你的 %s —— 已自动拒绝（交易 UI 待做）"
		% [sender, _fmt(got), _fmt(paid)])
	return false

func _fmt(bundle: Dictionary) -> String:
	var parts: Array[String] = []
	for r in bundle:
		parts.append("%d %s" % [bundle[r], Res.R_NAMES_CN[r]])
	return "、".join(parts) if not parts.is_empty() else "无"
