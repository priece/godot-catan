class_name GameDirector
extends Node

## 交互式回合驱动：把 GameController 的分步 API 串成一局能玩的游戏。
##
## 职责边界：
##   - 它知道"现在该谁、该干什么"，并据此决定用哪种交互（人类点击 / AI 定时自动）
##   - 它不实现任何规则判断——合法性一律交给 GameController.apply_action 校验
##   - 棋盘和面板都是"哑"的：棋盘负责画和报点，面板负责显示和发信号
##
## 人类玩家的所有"想做什么"都直接调用 apply_action() 提交，
## 不经过 IntentProvider（那个接口只用于 AI 决策和交易应答）。

enum S {
	SETUP_HUMAN,
	SETUP_AI,
	ROBBER_HUMAN,
	ROBBER_AI,
	## 人类回合的"掷骰前"窗口：官方规则允许在掷骰前打出功能卡（骑士/修路/丰收/垄断）。
	## 这个状态下**不能建造、不能交易、不能结束回合**，只能掷骰或打 1 张发展卡。
	HUMAN_PREROLL,
	HUMAN_TURN,
	AI_TURN,
	GAME_OVER,
}

const HUMAN := 0

## 电脑玩家用小红 / 小橙 / 小绿 编号（颜色见 UIPalette.PLAYER，pid 1/2/3）。
## 之前按难度命名（"电脑·简单"），三个电脑里有两个同难度时标签完全一样，
## 玩家根本分不清刚才是谁动的、面板上哪一行是谁。编号才能唯一对应。
const AI_LABELS := ["小红", "小橙", "小绿"]
const DIFF_NAMES := ["简单", "标准", "困难"]

@export var seed_value: int = 20261005
## 数字摆放的严格程度。
##   true  均衡布局：6/8 不相邻 **且** 相邻不同数字（官方 Almanac 对完全随机摆放的两条要求）
##   false 随机布局：只要求 6/8 不相邻（这条任何模式都不能破），数字允许挨着相同的
## 注意：地形在所有模式下都是纯随机 —— **官方没有"相同资源不能相邻"这条限制**。
@export var beginner_board: bool = true
## 三个电脑的难度：0 简单 / 1 标准 / 2 困难。
## 默认给 1 个简单 + 2 个标准，比清一色简单更有来有回；想全简单就改成 [0,0,0]。
@export var ai_difficulties: Array[int] = [0, 1, 1]
## AI 每步之间的停顿（秒），让玩家看清它在干什么
@export var ai_delay: float = 0.5
## 调试用：连"人类"座位也交给 AI，整局自动跑完（截图校验 / 回归测试用）
@export var auto_play: bool = false

var ctl: GameController
var board: BoardView
var hud: HUD
var state: int = S.SETUP_HUMAN

var _timer := 0.0
var _fails := 0
## 跨局保留的日志。重开一局不该把之前的记录清掉——
## 和"日志不做截断"是同一个原则。
var _session_log: Array[String] = []

# ================= 装配 =================

## 场景里自带 BoardView / HUD 时自动接线。
## 用 call_deferred 而不是直接调：兄弟节点的 _ready 是深度优先执行的，
## HUD 的控件在它自己的 _ready 里才建出来，director 若在 _ready 里立刻刷新会拿到空引用。
func _ready() -> void:
	# 随机种子用的 RNG：别用全局 randomize()，那会污染 AI 的随机流，
	# 这里单独一个实例，且不 seed()（构造时已自动随机化）。
	# 命令行带 "auto" 就开自动演示（截图/回归用）
	if OS.get_cmdline_user_args().has("auto"):
		auto_play = true
		ai_delay = 0.01   # 演示模式下不用等，尽快推进到中局
	if board == null or hud == null:
		var b := get_parent().get_node_or_null("BoardView")
		var h := get_parent().get_node_or_null("HUD")
		if b == null or h == null:
			push_error("GameDirector 找不到 BoardView / HUD 节点")
			return
		bind(b, h)

func bind(board_view: BoardView, hud_node: HUD) -> void:
	board = board_view
	hud = hud_node

	hud.end_turn_pressed.connect(_on_end_turn)
	hud.buy_dev_pressed.connect(_on_buy_dev)
	hud.play_dev_pressed.connect(_on_play_dev)
	hud.bank_trade_pressed.connect(_on_bank_trade)
	hud.roll_dice_pressed.connect(_on_roll_dice)
	hud.restart_pressed.connect(_on_restart)

	board.vertex_clicked.connect(_on_vertex_clicked)
	board.edge_clicked.connect(_on_edge_clicked)
	board.hex_clicked.connect(_on_hex_clicked)

	_start_new_game.call_deferred()

func _start_new_game() -> void:
	# 把上一局的日志接过来（日志只增不减，见 _session_log 的注释）
	if ctl != null and ctl.st != null:
		_session_log = ctl.st.log_lines.duplicate()
		if _session_log.size() > GameState.LOG_CAP:
			_session_log = _session_log.slice(_session_log.size() - GameState.LOG_CAP, _session_log.size())

	var human_is_ai := auto_play
	var configs: Array = [{"is_ai": human_is_ai, "difficulty": 1, "label": "你"}]
	var providers: Array = [AIMedium.new(HUMAN) if human_is_ai else HumanIntent.new(HUMAN)]
	var roster: Array[String] = []
	for i in ai_difficulties.size():
		var d: int = ai_difficulties[i]
		var nm: String = AI_LABELS[i % AI_LABELS.size()]
		configs.append({"is_ai": true, "difficulty": d, "label": nm})
		roster.append("%s=%s" % [nm, diff_name(d)])
		match d:
			0:
				providers.append(AIEasy.new(i + 1))
			1:
				providers.append(AIMedium.new(i + 1))
			_:
				providers.append(AIHard.new(i + 1))

	ctl = GameController.new()
	ctl.new_game(configs, seed_value, beginner_board, providers)
	ctl.st.log_enabled = true
	ctl.st.log_lines = _session_log.duplicate()
	ctl.st.log_line("")
	ctl.st.log_line("[color=#8a8378]━━━━━━━━  新开一局  ━━━━━━━━[/color]")
	ctl.st.log_line("棋盘种子 %d · %s · 对手：%s" % [
		seed_value, "均衡布局" if beginner_board else "随机布局", "，".join(roster)])
	hud.on_new_game(seed_value)
	board.set_board_from(ctl)
	board.redraw()
	_fails = 0
	_enter_setup()

## 重新开始。seed_text 为空表示"沿用上一局种子"（同一张棋盘，方便复盘）；
## 界面上点"随机"时传 "r"，会在这里换成一个新的随机种子。
func _on_restart(seed_text: String) -> void:
	var t := seed_text.strip_edges()
	if t == "r" or t == "随机":
		seed_value = _roll_seed()
	elif t.is_valid_int():
		seed_value = int(t)
	elif not t.is_empty():
		# 输入框已经标红提示过了，这里兜底不改种子，
		# 免得玩家打错一个字符就丢掉当前这局的进度。
		push_warning("种子 %s 不是整数，沿用上一局种子 %d" % [t, seed_value])
	_start_new_game()

## 随机种子。用独立 RNG 而不是 Time.get_ticks_msec()：
## 时间戳是毫秒精度，玩家连续点两次"随机"很容易落在同一毫秒里，
## 拿到同一张地图还以为没生效。上面 + 一个自增计数兜底，撞种子就不可能了。
var _roll_rng := RandomNumberGenerator.new()
var _roll_count := 0

func _roll_seed() -> int:
	_roll_count += 1
	return _roll_rng.randi() + _roll_count

static func diff_name(d: int) -> String:
	return DIFF_NAMES[clampi(d, 0, DIFF_NAMES.size() - 1)]

# ================= 主循环 =================

func _process(delta: float) -> void:
	if ctl == null or state == S.GAME_OVER:
		return
	match state:
		S.SETUP_AI, S.ROBBER_AI, S.AI_TURN:
			_timer -= delta
			if _timer > 0.0:
				return
			_timer = 0.0
			match state:
				S.SETUP_AI:
					_setup_ai_step()
				S.ROBBER_AI:
					_robber_ai_step()
				S.AI_TURN:
					_ai_step()
		_:
			pass   # 人类状态：等点击

# ================= 阶段流转 =================

func _enter_setup() -> void:
	if ctl.setup_is_over():
		ctl.st.current = 0
		_begin_next_turn()
		return
	var pid := ctl.setup_pid()
	ctl.st.current = pid
	if ctl.is_ai(pid):
		_set_state(S.SETUP_AI, ai_delay)
	else:
		_set_state(S.SETUP_HUMAN, 0.0)

## 回合起点分两步：先 start_turn（重置标记），再看要不要把"掷骰前"这一拍交给人类。
##
## 只有人类、且手上真有能打的功能卡时才停——否则直接替他掷掉，
## 免得每回合都多一次无意义的点击（这是需求里"没有骑士卡则自动掷骰"的推广：
## 一张能打的卡都没有就自动掷）。
func _begin_next_turn() -> void:
	if ctl.check_win():
		_enter_game_over()
		return
	ctl.start_turn()
	if not ctl.is_ai(ctl.st.current) and _human_can_play_dev():
		_set_state(S.HUMAN_PREROLL, 0.0)
		return
	_roll_and_branch()

## 掷骰并按结果分流（AI 与"人类无需选择"时共用）
func _roll_and_branch() -> void:
	ctl.roll_dice()
	if ctl.has_pending_robber():
		_enter_robber_phase()
		return
	_enter_main_phase()

## 人类现在有没有"能打的发展卡"：本回合还没打过，且手上有非胜利点的旧卡。
## 本回合刚买的卡在 fresh_dev_cards 里，finish_turn 才并入，天然不满足。
func _human_can_play_dev() -> bool:
	if ctl.st.dev_played_this_turn:
		return false
	var p: PlayerState = ctl.st.players[HUMAN]
	for card in Rules.playable_dev_cards(p):
		if card != Res.Dev.VICTORY:
			return true
	return false

func _enter_robber_phase() -> void:
	if ctl.is_ai(ctl.st.current):
		_set_state(S.ROBBER_AI, ai_delay)
	else:
		_set_state(S.ROBBER_HUMAN, 0.0)

func _enter_main_phase() -> void:
	if ctl.is_ai(ctl.st.current):
		_set_state(S.AI_TURN, ai_delay)
	else:
		_set_state(S.HUMAN_TURN, 0.0)

func _enter_game_over() -> void:
	_set_state(S.GAME_OVER, 0.0)
	board.clear_highlights()
	board.set_pick_mode(BoardView.Pick.NONE)

func _end_turn() -> void:
	ctl.finish_turn()
	ctl.advance_player()
	_begin_next_turn()

func _set_state(s: int, delay: float) -> void:
	state = s
	_timer = delay
	_refresh()

# ================= AI 步骤 =================

func _setup_ai_step() -> void:
	var pid := ctl.setup_pid()
	if pid < 0:
		_enter_setup()
		return
	var valid := ctl.setup_valid_spots()
	if valid.is_empty():
		push_error("AI 初始布置没有合法位置")
		return
	var choice: int
	if ctl.setup_stage() == 0:
		choice = ctl.providers[pid].choose_initial_settlement(ctl.st, valid)
	else:
		choice = ctl.providers[pid].choose_initial_road(ctl.st, ctl.setup_anchor(), valid)
	if not valid.has(choice):
		choice = valid[0]
	ctl.setup_apply(choice)
	board.redraw()
	_enter_setup()

func _robber_ai_step() -> void:
	ctl.auto_resolve_robber(ctl.st.current)
	board.redraw()
	_enter_main_phase()

func _ai_step() -> void:
	var pid := ctl.st.current
	var a := ctl.ai_action(pid)
	var t: String = a.get("type", Res.A_END_TURN)
	if t == Res.A_END_TURN or t == "":
		_end_turn()
		return
	if not ctl.apply_action(pid, a):
		# 非法动作：拉黑后重试，避免一次失误废掉整个回合
		ctl.notify_invalid(pid, a)
		_fails += 1
		if _fails >= 4:
			_end_turn()
		else:
			_set_state(S.AI_TURN, 0.05)
		return
	_fails = 0
	board.redraw()
	if ctl.check_win():
		_enter_game_over()
		return
	if ctl.has_pending_robber():
		_set_state(S.ROBBER_AI, ai_delay)
		return
	_set_state(S.AI_TURN, ai_delay)

# ================= 人类操作 =================

func _on_end_turn() -> void:
	if state != S.HUMAN_TURN:
		return
	_end_turn()

func _on_buy_dev() -> void:
	if state != S.HUMAN_TURN:
		return
	if ctl.apply_action(HUMAN, {"type": Res.A_BUY_DEV}):
		_after_human_action()

## 打发展卡：掷骰前（HUMAN_PREROLL）和主阶段（HUMAN_TURN）都能打。
## r / r1 / r2 由弹窗里玩家自己选（垄断选 1 种资源、丰收选 2 张，可相同）；
## 不需要参数的卡片传 -1。合法性仍由 apply_action 兜底 —— 每回合 1 张、
## 当回合买的不能打，都是规则层的事，Director 不重复判断。
func _on_play_dev(card: int, r: int, r1: int, r2: int) -> void:
	if state != S.HUMAN_TURN and state != S.HUMAN_PREROLL:
		return
	var action := {"type": Res.A_PLAY_DEV, "card": card}
	match card:
		Res.Dev.MONOPOLY:
			action["r"] = r
		Res.Dev.YEAR_OF_PLENTY:
			action["r1"] = r1
			action["r2"] = r2
	if ctl.apply_action(HUMAN, action):
		_after_human_action()

## 「掷骰子」按钮：只在掷骰前的窗口里有效
func _on_roll_dice() -> void:
	if state != S.HUMAN_PREROLL:
		return
	_roll_and_branch()

func _on_bank_trade(give_r: int, take_r: int) -> void:
	if state != S.HUMAN_TURN:
		return
	if ctl.apply_action(HUMAN, {"type": Res.A_BANK_TRADE, "give_r": give_r, "take_r": take_r}):
		_after_human_action()

func _on_vertex_clicked(v: int) -> void:
	match state:
		S.SETUP_HUMAN:
			if ctl.setup_apply(v):
				board.redraw()
				_enter_setup()
		S.HUMAN_TURN:
			if Rules.valid_city_vertices(ctl.st, HUMAN).has(v):
				if ctl.apply_action(HUMAN, {"type": Res.A_UPGRADE_CITY, "vertex": v}):
					_after_human_action()
					return
			if Rules.valid_settlement_vertices(ctl.st, HUMAN, false).has(v):
				if ctl.apply_action(HUMAN, {"type": Res.A_PLACE_SETTLEMENT, "vertex": v}):
					_after_human_action()

func _on_edge_clicked(e: int) -> void:
	match state:
		S.SETUP_HUMAN:
			if ctl.setup_apply(e):
				board.redraw()
				_enter_setup()
		S.HUMAN_TURN:
			if ctl.apply_action(HUMAN, {"type": Res.A_PLACE_ROAD, "edge": e}):
				_after_human_action()

## 放下强盗后去哪，取决于**骰子掷没掷**：
##   · 掷出 7 触发的 → 进主阶段；
##   · 掷骰前打骑士触发的 → 回 HUMAN_PREROLL 继续掷骰，
##     否则这回合的骰子就永远掷不出来（最容易漏的一步）。
func _on_hex_clicked(h: int) -> void:
	if state != S.ROBBER_HUMAN:
		return
	ctl.place_robber(HUMAN, h)
	board.redraw()
	if ctl.st.dice_rolled:
		_enter_main_phase()
	else:
		_set_state(S.HUMAN_PREROLL, 0.0)

func _after_human_action() -> void:
	board.redraw()
	if ctl.check_win():
		_enter_game_over()
		return
	if ctl.has_pending_robber():
		_enter_robber_phase()
		return
	_refresh()

# ================= 刷新 =================

func _refresh() -> void:
	if ctl == null:
		return
	# can_act = 人类现在能操作；main_phase = 是否已经掷过骰、能建造和交易。
	# 掷骰前的窗口里"能操作"但"不能建造"，两件事必须分开传，
	# 否则玩家能在产出之前先偷建。
	hud.refresh(ctl.st, _status_text(),
		state == S.HUMAN_TURN or state == S.HUMAN_PREROLL or state == S.SETUP_HUMAN or state == S.ROBBER_HUMAN,
		state == S.HUMAN_TURN, state == S.HUMAN_PREROLL)
	# 没掷骰时不显示骰子：st.dice 还留着上回合的值，显示出来会被误读
	hud.set_turn_info(ctl.st.round, ctl.st.dice if ctl.st.dice_rolled else 0)
	hud.set_log(ctl.st.log_lines)
	_update_highlights()

func _update_highlights() -> void:
	var vs: Array[int] = []
	var es: Array[int] = []
	var hs: Array[int] = []
	match state:
		S.SETUP_HUMAN:
			if ctl.setup_stage() == 0:
				vs = ctl.setup_valid_spots()
				board.set_pick_mode(BoardView.Pick.VERTEX)
			else:
				es = ctl.setup_valid_spots()
				board.set_pick_mode(BoardView.Pick.EDGE)
		S.ROBBER_HUMAN:
			hs = ctl.valid_robber_hexes()
			board.set_pick_mode(BoardView.Pick.HEX)
		S.HUMAN_TURN:
			# 只高亮"你买得起"的位置。Rules.valid_* 只判合法性、不判买不买得起，
			# 直接把结果当高亮会让玩家点了一堆没反应的空位（实测踩过）。
			var me: PlayerState = ctl.st.players[HUMAN]
			if me.has(Res.COST_SETTLEMENT):
				vs = Rules.valid_settlement_vertices(ctl.st, HUMAN, false)
			if me.has(Res.COST_CITY):
				vs.append_array(Rules.valid_city_vertices(ctl.st, HUMAN))
			if me.has(Res.COST_ROAD) or ctl.st.free_roads_remaining > 0:
				es = Rules.valid_road_edges(ctl.st, HUMAN, false)
			board.set_pick_mode(BoardView.Pick.ANY)
		S.HUMAN_PREROLL, _:
			# 掷骰前不能点棋盘：建造、交易按官方规则都在产出之后，
			# 这里放开会让玩家在没拿到资源前先偷建。
			board.set_pick_mode(BoardView.Pick.NONE)
	board.set_highlights(vs, es, hs)

func _status_text() -> String:
	match state:
		S.SETUP_HUMAN:
			if ctl.setup_stage() == 0:
				return "初始布置：点青色高亮处，放下你的第 %d 座村庄" % (ctl.st.players[HUMAN].settlements.size() + 1)
			return "初始布置：沿着刚放下的村庄，点一条青色高亮的路"
		S.SETUP_AI:
			return "%s 正在布置初始位置…" % _who(ctl.setup_pid())
		S.ROBBER_HUMAN:
			if ctl.st.dice_rolled:
				return "你掷出了 7：点任意地块放强盗（封产出 + 偷 1 张牌）"
			return "打出骑士：点任意地块放强盗（封产出 + 偷 1 张牌），放完还要掷骰"
		S.ROBBER_AI:
			return "%s 正在移动强盗…" % _who(ctl.st.current)
		S.HUMAN_PREROLL:
			return "轮到你了：先「掷骰子」，或打出 1 张发展卡（本回合只能打 1 张，打出后仍需掷骰）"
		S.HUMAN_TURN:
			var me: PlayerState = ctl.st.players[HUMAN]
			var can_build := me.has(Res.COST_SETTLEMENT) or me.has(Res.COST_CITY) \
				or me.has(Res.COST_ROAD) or ctl.st.free_roads_remaining > 0
			if not can_build:
				return "轮到你了（掷出 %d）：资源不够，先结束回合攒资源，或用右侧银行交易换一换" % ctl.st.dice
			return "轮到你了（掷出 %d）：点青色高亮处建造，或结束回合" % ctl.st.dice
		S.AI_TURN:
			return "%s 行动中…" % _who(ctl.st.current)
		S.GAME_OVER:
			if ctl.st.winner < 0:
				return "游戏结束：平局"
			return "游戏结束：%s 获胜！" % ctl.st.players[ctl.st.winner].label
	return ""

# ================= 小工具 =================

## 状态栏里的玩家称呼。电脑补上难度（面板标签只有小红/小橙/小绿，放不下难度），
## 这样玩家至少在该它行动时知道对面是什么水平。
func _who(pid: int) -> String:
	if pid < 0 or pid >= ctl.st.players.size():
		return "电脑"
	var p: PlayerState = ctl.st.players[pid]
	if p.is_ai:
		return "%s（%s）" % [p.label, diff_name(p.difficulty)]
	return p.label

