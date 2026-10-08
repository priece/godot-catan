extends SceneTree

## M1 验收：在无 UI 环境下批量跑完整对局 + AI 平衡性诊断。
##
## 用法：
##   godot --headless --path . --script res://tools/sim_runner.gd -- 200
##   godot --headless --path . --script res://tools/sim_runner.gd -- 300 h2h   (1 困难 vs 3 标准)
##   godot --headless --path . --script res://tools/sim_runner.gd -- 2 v       (打印单局日志)
##
## 每局座位轮换，避免座位优势污染结论。
##
## 强制校验两条不变量：
##   1. 棋盘：地形/数字/港口分布与官方一致（Board.self_check）
##   2. 资源守恒：银行 + 全部玩家手上，每种资源恒为 19 张
## 任何一条被打破都说明规则引擎有 bug，而不是"AI 打得不好"。

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var games := 100
	if args.size() >= 1:
		games = int(args[0])
	var mode := "std"
	var verbose := false
	for i in range(1, args.size()):
		if args[i] == "v":
			verbose = true
		elif args[i] == "h2h":
			mode = "h2h"

	var topo := BoardTopology.instance()
	var terrs := topo.self_check()
	if not terrs.is_empty():
		print("!! 拓扑自检失败")
		for e in terrs:
			print("   - " + e)
		quit(1)
		return

	var diff_names := ["Easy", "Medium", "Hard"]

	# 每个难度一份统计（按"座位数"平均，而不是按局数）
	var stat := {}
	for d in 3:
		stat[d] = {
			"seats": 0, "wins": 0,
			"vp": 0.0, "blocks": 0.0,
			"settle": 0.0, "city": 0.0, "road": 0.0, "dev": 0.0, "lr": 0.0,
			"cities_built": 0, "settle_built": 0,
		}

	var timeouts := 0
	var draws := 0
	var rounds_sum := 0
	var invariant_bad := 0
	var board_bad := 0
	var integrity_bad := 0
	var max_round_seen := 0

	var t0 := Time.get_ticks_msec()

	for g in games:
		var seed := 1000 + g

		var diffs: Array = []
		if mode == "h2h":
			diffs = [2, 1, 1, 1]           # 1 困难 vs 3 标准
		else:
			diffs = [0, 1, 2, 1]
		var shift := g % 4

		var configs: Array = []
		var providers: Array = []
		for i in 4:
			var d: int = diffs[(i + shift) % 4]
			configs.append({"is_ai": true, "difficulty": d, "label": diff_names[d]})
			match d:
				0:
					providers.append(AIEasy.new(i))
				1:
					providers.append(AIMedium.new(i))
				_:
					providers.append(AIHard.new(i))

		var beginner := (g % 3) != 0
		var ctl := GameController.new()
		ctl.new_game(configs, seed, beginner, providers)
		ctl.st.log_enabled = verbose

		var berrs := ctl.st.board.self_check()
		if not berrs.is_empty():
			board_bad += 1
			if board_bad <= 3:
				print("!! 棋盘自检失败 seed=%d" % seed)
				for e in berrs:
					print("   - " + e)

		var w: int = ctl.run(300)
		rounds_sum += ctl.st.round
		max_round_seen = maxi(max_round_seen, ctl.st.round)
		if ctl.st.timed_out:
			timeouts += 1

		# --- 不变量 1：资源守恒 ---
		for r in Res.R_COUNT:
			var total: int = ctl.st.bank[r]
			for p in ctl.st.players:
				total += p.resources[r]
			if total != 19:
				invariant_bad += 1
				if invariant_bad <= 3:
					print("!! 资源不守恒 seed=%d 资源=%s 实际=%d 期望=19" % [seed, Res.R_NAMES[r], total])
				break

		# --- 不变量 2：状态完整性 ---
		var ierrs := _integrity_check(ctl.st)
		if not ierrs.is_empty():
			integrity_bad += 1
			if integrity_bad <= 3:
				print("!! 状态完整性失败 seed=%d" % seed)
				for e in ierrs:
					print("   - " + e)

		# --- 统计 ---
		for p in ctl.st.players:
			var d: int = configs[p.id]["difficulty"]
			var s: Dictionary = stat[d]
			s.seats += 1
			s.vp += float(ctl.st.victory_points(p.id))
			s.blocks += float(ctl.st.public_victory_points(p.id))
			s.settle += float(p.settlements.size())
			s.city += float(p.cities.size())
			s.road += float(p.roads.size())
			s.dev += float(p.dev_cards.size() + p.fresh_dev_cards.size())
			s.lr += float(LongestRoad.length_for(topo, ctl.st, p.id))
			s.cities_built += p.cities.size()
			s.settle_built += p.settlements.size() + p.cities.size()

		if w < 0:
			draws += 1
		else:
			stat[configs[w]["difficulty"]].wins += 1

		if verbose and g < 2:
			print("-------- seed %d 日志 --------" % seed)
			for line in ctl.st.log_lines:
				print(line)

	var dt := Time.get_ticks_msec() - t0

	print("")
	print("==================================================")
	print("  卡坦岛规则引擎 · 批量对局验收  (模式: %s)" % mode)
	print("==================================================")
	print("对局数            : %d" % games)
	print("总耗时            : %.2f 秒 (%.1f 毫秒/局)" % [dt / 1000.0, float(dt) / float(maxi(1, games))])
	print("平均轮数          : %.1f   (最长 %d 轮)" % [float(rounds_sum) / float(maxi(1, games)), max_round_seen])
	print("超时未分胜负      : %d" % timeouts)
	print("")
	print("难度      座位胜率     平均终局分   平均村/城/路/券   平均最长路   平均建筑数")
	for d in [0, 1, 2]:
		var s: Dictionary = stat[d]
		var seats: int = maxi(1, s.seats)
		var wr: float = 100.0 * float(s.wins) / float(maxi(1, s.seats))
		# 每局有 4 个座位，胜率按"占本难度席位的比例"再折算成"每局占比"更直观
		var share: float = 100.0 * float(s.wins) / float(maxi(1, games))
		print("%-8s  %5.1f%%(席位) %5.1f%%(局)   %5.2f     %4.1f/%4.1f/%4.1f/%4.1f   %5.2f      %4.1f" % [
			diff_names[d], wr, share,
			float(s.vp) / float(seats),
			float(s.settle) / float(seats), float(s.city) / float(seats),
			float(s.road) / float(seats), float(s.dev) / float(seats),
			float(s.lr) / float(seats),
			float(s.settle_built) / float(seats),
		])
	print("")
	print("不变量：棋盘异常 %d · 资源守恒破坏 %d · 状态完整性破坏 %d" % [board_bad, invariant_bad, integrity_bad])

	var ok := board_bad == 0 and invariant_bad == 0 and integrity_bad == 0 and timeouts == 0
	print("")
	print("M1 验收结果：%s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

# ---------------- 状态完整性 ----------------

func _integrity_check(st: GameState) -> Array[String]:
	var errs: Array[String] = []
	var vertex_owner := {}
	var edge_owner := {}

	for p in st.players:
		for v in p.settlements:
			if vertex_owner.has(v):
				errs.append("顶点 %d 被 P%d 和 P%d 同时占据" % [v, vertex_owner[v], p.id])
			vertex_owner[v] = p.id
		for v in p.cities:
			if vertex_owner.has(v):
				errs.append("顶点 %d 被 P%d 和 P%d 同时占据" % [v, vertex_owner[v], p.id])
			vertex_owner[v] = p.id
		for e in p.roads:
			if edge_owner.has(e):
				errs.append("边 %d 被 P%d 和 P%d 同时占据" % [e, edge_owner[e], p.id])
			edge_owner[e] = p.id
		if p.roads.size() > Res.LIMIT_ROAD:
			errs.append("P%d 道路数 %d 超上限" % [p.id, p.roads.size()])
		if p.settlements.size() + p.cities.size() > Res.LIMIT_SETTLEMENT:
			errs.append("P%d 村庄+城市 %d 超上限" % [p.id, p.settlements.size() + p.cities.size()])
		if p.cities.size() > Res.LIMIT_CITY:
			errs.append("P%d 城市数 %d 超上限" % [p.id, p.cities.size()])
		for r in Res.R_COUNT:
			if p.resources[r] < 0:
				errs.append("P%d 的 %s 为负" % [p.id, Res.R_NAMES[r]])

	return errs
