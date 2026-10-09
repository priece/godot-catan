extends SceneTree

## M2 验收：模拟人类点击，把一局从头打到尾。
##
## 关键点：不是绕过界面直接调控制器，而是**发棋盘和面板的信号**——
## 与真实鼠标点击走完全相同的代码路径（BoardView._handle_click 也是发这些信号）。
## 所以这个测试能真正验证"人类能不能玩"。
##
## 用法：
##   Godot --path . --resolution 1280x720 --script res://tools/test_interaction.gd -- [最大帧数] [截图路径]

var director: GameDirector
var board: BoardView
var hud: HUD

var frames := 0
var max_frames := 6000
var clicks := 0
var human_builds := 0
var invalid_tested := false
var turn_shot_taken := false
var done := false
var shot_path := ""

## 掷骰前窗口（HUMAN_PREROLL）的统计
var preroll_turns := 0        ## 出现次数
var preroll_dev := 0          ## 在其中打出的发展卡数
var preroll_knight := 0       ## 其中打出骑士的次数
var preroll_robber := 0       ## 掷骰前打骑士后放强盗的次数
var dice_ok := true           ## 主阶段时骰子必须已经掷过

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		max_frames = int(args[0])
	if args.size() > 1:
		shot_path = args[1]

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("!! 无法加载主场景")
		quit(1)
		return
	root.add_child(packed.instantiate())
	RenderingServer.frame_post_draw.connect(_on_frame)

# ================= 主循环 =================

func _on_frame() -> void:
	if done:
		return
	frames += 1
	if director == null:
		if not _grab():
			return
		director.ai_delay = 0.01   # 让 AI 快速推进，测试不必等演出
		print("OK 主场景装配完成，开始模拟点击")
	if frames > max_frames:
		_finish()
		return
	if director.state == GameDirector.S.GAME_OVER:
		_finish()
		return
	if frames % 3 == 0:
		_human_step()

func _grab() -> bool:
	var scene := root.get_child(root.get_child_count() - 1)
	director = _find_dir(scene)
	board = _find_board(scene)
	hud = _find_hud(scene)
	return director != null and board != null and hud != null

func _find_dir(n: Node) -> GameDirector:
	if n is GameDirector:
		return n
	for c in n.get_children():
		var r := _find_dir(c)
		if r != null:
			return r
	return null

func _find_board(n: Node) -> BoardView:
	if n is BoardView:
		return n
	for c in n.get_children():
		var r := _find_board(c)
		if r != null:
			return r
	return null

func _find_hud(n: Node) -> HUD:
	if n is HUD:
		return n
	for c in n.get_children():
		var r := _find_hud(c)
		if r != null:
			return r
	return null

# ================= 模拟人类操作 =================

func _human_step() -> void:
	var ctl := director.ctl
	match director.state:
		GameDirector.S.SETUP_HUMAN:
			var spots := ctl.setup_valid_spots()
			if spots.is_empty():
				return
			var pick: int
			if ctl.setup_stage() == 0:
				pick = _planner.choose_initial_settlement(ctl.st, spots)
			else:
				pick = _planner.choose_initial_road(ctl.st, ctl.setup_anchor(), spots)
			if not spots.has(pick):
				pick = spots[0]
			if ctl.setup_stage() == 0:
				board.vertex_clicked.emit(pick)
			else:
				board.edge_clicked.emit(pick)
			clicks += 1
		GameDirector.S.ROBBER_HUMAN:
			var hs := ctl.valid_robber_hexes()
			if hs.is_empty():
				return
			# 没掷骰就要放强盗 = 掷骰前打了骑士。放完必须回到掷骰前继续掷，
			# 这条路走不通的话本回合骰子就永远掷不出来。
			if not ctl.st.dice_rolled:
				preroll_robber += 1
			board.hex_clicked.emit(hs[0])
			clicks += 1
		GameDirector.S.HUMAN_PREROLL:
			# 掷骰前的窗口：抢先打 1 张发展卡（顺便覆盖这条新链路），
			# 没卡可打或已经打过就直接掷骰 —— 少了这一步人类回合会永远停在这里。
			_preroll_step()
		GameDirector.S.HUMAN_TURN:
			# 能进主阶段就说明骰子已经掷过了 —— 掷骰前的窗口不允许建造
			if not ctl.st.dice_rolled:
				dice_ok = false
			if not invalid_tested:
				_test_invalid_click()
				return
			if not turn_shot_taken and shot_path != "":
				turn_shot_taken = true
				var img: Image = root.get_texture().get_image()
				img.save_png(shot_path.get_basename() + "_turn.png")
				print("OK 人类回合截图 -> %s_turn.png" % shot_path.get_basename())
			_try_human_build()
		_:
			pass

## 掷骰前窗口：能打就打 1 张，不能打就掷骰。
## 每回合最多 1 张由 dev_played_this_turn 兜住，所以不会陷入死循环。
func _preroll_step() -> void:
	var ctl := director.ctl
	var st := ctl.st
	preroll_turns += 1
	if not st.dev_played_this_turn:
		for card in Rules.playable_dev_cards(st.players[0]):
			if card == Res.Dev.VICTORY:
				continue
			preroll_dev += 1
			if card == Res.Dev.KNIGHT:
				preroll_knight += 1
			match card:
				Res.Dev.MONOPOLY:
					hud.play_dev_pressed.emit(card, _best_monopoly(), -1, -1)
				Res.Dev.YEAR_OF_PLENTY:
					# 挑一种银行里至少有 2 张的资源，两列都选它 ——
					# 顺便验证"丰收年两列可选同一种"这条规则
					var r := _bank_rich(2)
					if r < 0:
						break
					hud.play_dev_pressed.emit(card, -1, r, r)
				_:
					hud.play_dev_pressed.emit(card, -1, -1, -1)
			clicks += 1
			return
	hud.roll_dice_pressed.emit()
	clicks += 1

## 垄断收得最多的那种资源
func _best_monopoly() -> int:
	var st := director.ctl.st
	var best_r := 0
	var best_n := -1
	for r in Res.R_COUNT:
		var n := Rules.monopoly_yield(st, 0, r)
		if n > best_n:
			best_n = n
			best_r = r
	return best_r

## 银行里还剩至少 need 张的资源，找不到返回 -1
func _bank_rich(need: int) -> int:
	var st := director.ctl.st
	for r in Res.R_COUNT:
		if st.bank[r] >= need:
			return r
	return -1

## 验证"点了不该点的地方"不会生效、也不会崩
func _test_invalid_click() -> void:
	invalid_tested = true
	var ctl := director.ctl
	var before: int = ctl.st.players[0].settlements.size()
	var bad := -1
	for v in board.topo.vertices.size():
		if not board.highlight_vertices.has(v):
			bad = v
			break
	if bad < 0:
		return
	board.vertex_clicked.emit(bad)
	if ctl.st.players[0].settlements.size() != before:
		print("!! 非法点击竟然生效了（应被忽略）")
	else:
		print("OK 非法点击被正确忽略")

func _try_human_build() -> void:
	var ctl := director.ctl
	var st := ctl.st
	var p: PlayerState = st.players[0]

	var cities := Rules.valid_city_vertices(st, 0)
	if not cities.is_empty() and p.has(Res.COST_CITY):
		board.vertex_clicked.emit(cities[0])
		human_builds += 1
		return

	var spots := Rules.valid_settlement_vertices(st, 0, false)
	if not spots.is_empty() and p.has(Res.COST_SETTLEMENT):
		board.vertex_clicked.emit(spots[0])
		human_builds += 1
		return

	if Rules.can_buy_dev(st, 0) and not st.dev_played_this_turn:
		hud.buy_dev_pressed.emit()
		human_builds += 1
		return

	var edges := Rules.valid_road_edges(st, 0, false)
	if not edges.is_empty() and (p.has(Res.COST_ROAD) or st.free_roads_remaining > 0):
		board.edge_clicked.emit(edges[0])
		human_builds += 1
		return

	# 什么都建不了时，用银行交易把富余资源换成所缺的
	# （不做这一步，"人类"会握着 6 张麦子干瞪眼到游戏结束）
	for o in Rules.bank_trade_options(st, 0):
		var give_r: int = o[0]
		var take_r: int = o[1]
		var ratio: int = o[2]
		if not _spare(p, give_r, ratio) or not _missing(p, take_r):
			continue
		hud.bank_trade_pressed.emit(give_r, take_r)
		human_builds += 1
		return

	hud.end_turn_pressed.emit()

## 付掉 ratio 张后仍够各类建筑所需
func _spare(p: PlayerState, r: int, ratio: int) -> bool:
	var need := 0
	for cost in [Res.COST_CITY, Res.COST_SETTLEMENT, Res.COST_DEV, Res.COST_ROAD]:
		need = maxi(need, cost.get(r, 0))
	return p.count(r) - ratio >= need

## 该资源还缺
func _missing(p: PlayerState, r: int) -> bool:
	var need := 0
	for cost in [Res.COST_CITY, Res.COST_SETTLEMENT, Res.COST_DEV]:
		need = maxi(need, cost.get(r, 0))
	return p.count(r) < need

## 初始布点直接复用 AI 的决策逻辑（AIController.choose_initial_*）。
## 早期版本自己写了个"取评分最高的点"，结果是两座村庄抢同一片地形、
## 整局拿不到资源，测试数据完全失真。AI 那套评分已经考虑了资源互补、
## 撞数字惩罚、共用地块惩罚，没有理由不复用。
var _planner := AIMedium.new(0)

func _best_setup_spot(spots: Array[int], stage: int) -> int:
	var st := director.ctl.st
	if stage == 0:
		return _planner.choose_initial_settlement(st, spots)
	return _planner.choose_initial_road(st, director.ctl.setup_anchor(), spots)

# ================= 收尾 =================

func _finish() -> void:
	done = true
	if shot_path != "":
		var img: Image = root.get_texture().get_image()
		img.save_png(shot_path)
		print("OK 截图 -> %s" % shot_path)

	var st := director.ctl.st
	print("")
	print("========================================")
	print("  M2 交互验收（模拟人类点击打完整局）")
	print("========================================")
	print("模拟点击次数   : %d" % clicks)
	print("人类成功建造次数: %d" % human_builds)
	print("掷骰前窗口     : 出现 %d 次 · 打出发展卡 %d 次（骑士 %d 次，其后放强盗 %d 次）"
		% [preroll_turns, preroll_dev, preroll_knight, preroll_robber])
	if not dice_ok:
		print("!! 出现未掷骰就进入主阶段的回合")
	if preroll_knight > 0 and preroll_robber < preroll_knight:
		print("!! 掷骰前打出的骑士没能走完放强盗流程")
	print("帧数 / 轮数    : %d / %d" % [frames, st.round])
	print("强盗最终位置   : 地块 %d（初始在 %d）" % [st.board.robber_hex, _desert_hex()])
	if st.winner >= 0:
		print("胜者           : %s（%d 分）" % [st.players[st.winner].label, st.victory_points(st.winner)])
	else:
		print("胜者           : 无（平局或超时）")

	# 不变量
	var errs := _integrity(st)
	for r in Res.R_COUNT:
		var total: int = st.bank[r]
		for p in st.players:
			total += p.resources[r]
		if total != 19:
			errs.append("资源不守恒：%s 共 %d 张（应 19）" % [Res.R_NAMES_CN[r], total])

	var ok := errs.is_empty() and st.winner >= 0 and human_builds > 0 and dice_ok \
		and preroll_robber >= preroll_knight

	# 日志必须是全量的：最早那条（"新开一局…"）不能被截掉
	var log_text: String = hud._log.text
	var first_line: String = st.log_lines[0] if not st.log_lines.is_empty() else ""
	if first_line != "" and not log_text.begins_with(first_line):
		ok = false
		print("!! 日志被截断：首条已丢失（当前显示 %d 行）" % hud._log.get_line_count())
	else:
		print("OK 日志全量保留：共 %d 条，最早那条仍在" % st.log_lines.size())

	# "重开一局"：状态要真的重置，且日志要延续而不是清空。
	# ⚠️ restart_pressed 现在带一个参数（种子输入框的文本）。
	# 传 "" = 沿用上一局种子，这样测试仍是确定性的；漏传参数会直接报
	# "Method expected 1 argument(s), but called with 0"。
	var log_before: int = st.log_lines.size()
	hud.restart_pressed.emit("")
	var st2 := director.ctl.st
	var fresh := st2.round <= 1
	for p in st2.players:
		if not p.roads.is_empty() or not p.settlements.is_empty() or p.total_resources() > 0:
			fresh = false
	if st2.log_lines.size() < log_before:
		fresh = false
		print("!! 重开后日志被清空了（%d < %d）" % [st2.log_lines.size(), log_before])
	if fresh:
		print("OK 重开一局：棋盘/建筑/资源已重置，第 %d 轮，日志延续到 %d 条"
			% [st2.round, st2.log_lines.size()])
	else:
		ok = false

	if not errs.is_empty():
		for e in errs:
			print("!! " + e)
	print("")
	print("M2 验收结果：%s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

func _desert_hex() -> int:
	for hi in director.ctl.st.board.hex_terrain.size():
		if director.ctl.st.board.hex_terrain[hi] == Res.Terrain.DESERT:
			return hi
	return -1

func _integrity(st: GameState) -> Array[String]:
	var errs: Array[String] = []
	var vertex_owner := {}
	var edge_owner := {}
	for p in st.players:
		for v in p.settlements:
			if vertex_owner.has(v):
				errs.append("顶点 %d 被两人同时占据" % v)
			vertex_owner[v] = p.id
		for v in p.cities:
			if vertex_owner.has(v):
				errs.append("顶点 %d 被两人同时占据" % v)
			vertex_owner[v] = p.id
		for e in p.roads:
			if edge_owner.has(e):
				errs.append("边 %d 被两人同时占据" % e)
			edge_owner[e] = p.id
		for r in Res.R_COUNT:
			if p.resources[r] < 0:
				errs.append("%s 的 %s 为负" % [p.label, Res.R_NAMES_CN[r]])
	return errs
