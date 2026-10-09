extends SceneTree

## 发展卡改造单元测试（headless 可跑，只碰 HUD 与规则层，不碰渲染）。
##
## 覆盖三件事：
##   1. 回合起点拆成 start_turn / roll_dice 后，RNG 流必须与拆分前**逐点一致**
##      （骰子序列比对，这是"拆分没拆坏 sim_runner"的直接证据）
##   2. 掷骰前窗口的规则边界：每回合最多 1 张、本回合买的卡不能打
##   3. 三级弹窗（选卡 → 垄断单列 / 丰收两列）的可用性、参数与复位
##
## 用法： godot --headless --path . --script res://tools/test_dev_dialog.gd
## 退出码 0 = 全通过

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== 发展卡改造单元测试 ===")
	_run_tests.call_deferred()

func _run_tests() -> void:
	_test_turn_split()
	var hud := await _make_hud()
	_test_roll_phase(hud)
	await _test_dev_dialog(hud)
	await _test_mono_dialog(hud)
	await _test_yop_dialog(hud)
	_test_rules()

	print("")
	print("通过 %d · 失败 %d" % [_pass, _fail])
	print("发展卡测试结果：%s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

# ================= 1. 回合拆分：RNG 流不能变 =================

func _test_turn_split() -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st

	ctl.start_turn(0)
	_ok(not st.dice_rolled, "start_turn 后 dice_rolled 为 false（还没掷）")
	_ok(st.dev_played_this_turn == false, "start_turn 重置了每回合打牌标记")

	ctl.roll_dice(0)
	_ok(st.dice_rolled, "roll_dice 后 dice_rolled 为 true")
	_ok(st.dice >= 2 and st.dice <= 12, "骰子在 2..12", "实际 %d" % st.dice)

	# 核心回归：同一颗种子下，拆开调用与合体调用必须掷出**完全相同**的序列。
	# 只要骰子序列一致，就说明拆分没有插入/挪动任何一次 RNG 调用。
	var a := _dice_seq(777, false)
	var b := _dice_seq(777, true)
	_ok(a == b and a.size() == 30,
		"begin_turn 与 start_turn+roll_dice 的骰子序列完全一致（RNG 流未变）",
		"合体 %s / 拆分 %s" % [a.slice(0, 6), b.slice(0, 6)])

## 跑 30 个回合，收集每次掷出的点数。split=true 走拆分写法
func _dice_seq(seed_value: int, split: bool) -> Array[int]:
	var ctl := _fresh_game(4, seed_value)
	ctl.run_setup()
	var out: Array[int] = []
	for i in 30:
		var pid := ctl.st.current
		if split:
			ctl.start_turn(pid)
			ctl.roll_dice(pid)
		else:
			ctl.begin_turn(pid)
		out.append(ctl.st.dice)
		if ctl.has_pending_robber():
			ctl.auto_resolve_robber(pid)
		ctl.finish_turn(pid)
		ctl.advance_player()
	return out

# ================= 2. 掷骰前窗口的按钮可见性 =================

func _test_roll_phase(hud: HUD) -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st

	# 主阶段：掷骰子按钮隐藏，操作行（结束回合/买卡/兑换）可见
	hud.refresh(st, "主阶段", true, true, false)
	_ok(not hud._btn_roll.visible, "主阶段不显示「掷骰子」")
	_ok(hud._act_row.visible, "主阶段显示建造/交易/结束回合一行")

	# 掷骰前：反过来
	hud.refresh(st, "掷骰前", true, false, true)
	_ok(hud._btn_roll.visible, "掷骰前显示「掷骰子」")
	_ok(not hud._act_row.visible, "掷骰前隐藏建造/交易/结束回合一行")
	_ok(hud._btn_end.disabled, "掷骰前「结束回合」置灰（必须先掷骰）")
	_ok(hud._btn_buy.disabled, "掷骰前「买发展卡」置灰")
	_ok(hud._btn_trade.disabled, "掷骰前「兑换」置灰")

# ================= 3. 选卡弹窗 =================

func _make_hud() -> HUD:
	var hud: HUD = load("res://ui/hud.gd").new()
	root.add_child(hud)
	# HUD._ready 里 await 了一帧才给种子卡片定位，等几帧让构建全部落地
	for i in 3:
		await process_frame
	return hud

func _test_dev_dialog(hud: HUD) -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st
	var p0: PlayerState = st.players[0]
	p0.dev_cards = [Res.Dev.KNIGHT, Res.Dev.MONOPOLY, Res.Dev.YEAR_OF_PLENTY, Res.Dev.VICTORY]
	p0.resources = [3, 3, 3, 3, 3]

	var played: Array = []
	hud.play_dev_pressed.connect(func(c: int, r: int, r1: int, r2: int): played.append([c, r, r1, r2]))
	# ⚠️ 计数用数组而不是 int：GDScript 的 lambda 里对捕获的 int 做 +=
	# 不会写回外层变量，断言永远读到 0。
	var rolled := [0]
	hud.roll_dice_pressed.connect(func(): rolled[0] += 1)

	hud.refresh(st, "掷骰前", true, false, true)
	_ok(not hud._btn_play.disabled, "有可打卡时「打发展卡」可点")
	_ok(hud._btn_play.text == "打发展卡 3", "按钮显示可打张数（胜利点卡不计）", hud._btn_play.text)

	hud._btn_roll.pressed.emit()
	_ok(rolled[0] == 1, "「掷骰子」发出 roll_dice_pressed", "实际 %d" % rolled[0])

	hud.show_dev_dialog()
	_ok(hud._dev_dlg.visible, "选卡弹窗可见")
	# 骑士 / 垄断 / 丰收 三项，胜利点卡自动计分不进列表
	_ok(hud._dev_box.get_child_count() == 3,
		"选卡弹窗列出 3 张可打卡（胜利点卡不列）", "实际 %d" % hud._dev_box.get_child_count())

	# 骑士：无需参数，直接打出并关闭弹窗
	(hud._dev_box.get_child(0) as Button).pressed.emit()
	_ok(played.size() == 1 and played[0][0] == Res.Dev.KNIGHT and played[0][1] == -1,
		"骑士直接打出，参数为 -1", "实际 %s" % str(played))
	_ok(not hud._dev_dlg.visible, "打出后弹窗关闭")

	# 本回合已打过：列表项全禁用，入口按钮也禁用
	st.dev_played_this_turn = true
	hud.refresh(st, "主阶段", true, true, false)
	_ok(hud._btn_play.disabled, "本回合已打过后「打发展卡」置灰")
	hud.show_dev_dialog()
	var all_disabled := true
	for c in hud._dev_box.get_children():
		if c is Button and not (c as Button).disabled:
			all_disabled = false
	_ok(all_disabled, "本回合已打过时选卡弹窗各项禁用")
	hud.close_dev_dialog()
	st.dev_played_this_turn = false

	# 本回合刚买的卡（fresh）不能打
	p0.dev_cards = []
	p0.fresh_dev_cards = [Res.Dev.KNIGHT]
	hud.refresh(st, "掷骰前", true, false, true)
	_ok(hud._btn_play.disabled, "只有本回合刚买的卡时「打发展卡」置灰")
	p0.fresh_dev_cards = []
	p0.dev_cards = [Res.Dev.KNIGHT]

# ================= 4. 垄断弹窗 =================

func _test_mono_dialog(hud: HUD) -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st
	var p0: PlayerState = st.players[0]
	p0.dev_cards = [Res.Dev.MONOPOLY]
	p0.resources = [1, 0, 0, 0, 0]

	# 对手手里：木 2+3=5，其余 0（第 4 家也要清零，否则初始手牌会混进合计）
	var o1: PlayerState = st.players[1]
	var o2: PlayerState = st.players[2]
	var o3: PlayerState = st.players[3]
	o1.resources = [2, 0, 0, 0, 0]
	o2.resources = [3, 0, 0, 0, 0]
	o3.resources = [0, 0, 0, 0, 0]

	var played: Array = []
	hud.play_dev_pressed.connect(func(c: int, r: int, r1: int, r2: int): played.append([c, r, r1, r2]))

	hud.refresh(st, "主阶段", true, true, false)
	hud.show_dev_dialog()
	_ok(hud._dev_box.get_child_count() == 1, "手上只有垄断卡时列表 1 项")

	(hud._dev_box.get_child(0) as Button).pressed.emit()
	_ok(hud._mono_dlg.visible, "点垄断打开二级弹窗")
	_ok(hud._dev_dlg.visible, "二级弹窗打开时一级保持可见（取消能退回）")
	_ok(hud._mono_ok.disabled, "未选资源时确定置灰")

	var wood_btn: Button = hud._mono_btns[Res.R.WOOD]
	_ok(wood_btn.text == "木 ×5", "垄断项显示对手合计张数（自己手里的 1 张不算）", wood_btn.text)
	_ok(not wood_btn.disabled, "合计 5 张的木可选")
	_ok((hud._mono_btns[Res.R.BRICK] as Button).disabled, "合计 0 张的砖禁用")
	_ok(hud._dev_dlg.visible, "二级弹窗打开时一级弹窗仍在")

	wood_btn.pressed.emit()
	_ok(hud._mono_sel == Res.R.WOOD, "选中木材")
	_ok(not hud._mono_ok.disabled, "选好后确定可点")
	hud._mono_ok.pressed.emit()
	_ok(played.size() == 1 and played[0][0] == Res.Dev.MONOPOLY and played[0][1] == Res.R.WOOD,
		"垄断信号参数正确", "实际 %s" % str(played))
	_ok(not hud._mono_dlg.visible and not hud._dev_dlg.visible, "确定后两级弹窗都关闭")

	# 取消：回到一级弹窗，不产生信号
	hud.show_dev_dialog()
	(hud._dev_box.get_child(0) as Button).pressed.emit()
	(hud._mono_btns[Res.R.WOOD] as Button).pressed.emit()
	hud.close_mono_dialog()
	_ok(played.size() == 1, "取消垄断不产生信号", "实际 %s" % str(played))
	_ok(hud._dev_dlg.visible, "取消二级弹窗后回到选卡弹窗")
	hud.close_dev_dialog()

	# 重开后选择复位
	hud.show_mono_dialog()
	_ok(hud._mono_sel == -1 and hud._mono_ok.disabled, "重开垄断弹窗后选择复位")
	hud.close_mono_dialog()

# ================= 5. 丰收弹窗（两列，可相同） =================

func _test_yop_dialog(hud: HUD) -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st
	var p0: PlayerState = st.players[0]
	p0.dev_cards = [Res.Dev.YEAR_OF_PLENTY]
	p0.resources = [0, 0, 0, 0, 0]

	var played: Array = []
	hud.play_dev_pressed.connect(func(c: int, r: int, r1: int, r2: int): played.append([c, r, r1, r2]))

	hud.refresh(st, "主阶段", true, true, false)
	hud.show_dev_dialog()
	(hud._dev_box.get_child(0) as Button).pressed.emit()
	_ok(hud._yop_dlg.visible, "点丰收打开两列弹窗")
	_ok(hud._yop_btns.size() == 2 and hud._yop_btns[0].size() == 5 and hud._yop_btns[1].size() == 5,
		"两列各 5 个资源按钮")
	_ok(hud._yop_ok.disabled, "两列都没选时确定置灰")

	# 选第 1 张：木
	(hud._yop_btns[0][Res.R.WOOD] as Button).pressed.emit()
	_ok(hud._yop_ok.disabled, "只选了第 1 张时确定仍置灰")

	# 两列可以选同一种：把麦子库存压到 1 张，验证第二列会禁掉它
	st.bank[Res.R.GRAIN] = 1
	hud._rebuild_yop_lists()
	(hud._yop_btns[0][Res.R.GRAIN] as Button).pressed.emit()
	_ok((hud._yop_btns[1][Res.R.GRAIN] as Button).disabled,
		"两列选同一种且银行只有 1 张时，第 2 列该资源禁用")
	st.bank[Res.R.GRAIN] = 19
	hud._rebuild_yop_lists()

	# 两列都选木（相同资源，银行充足）
	(hud._yop_btns[0][Res.R.WOOD] as Button).pressed.emit()
	_ok(not (hud._yop_btns[1][Res.R.WOOD] as Button).disabled, "银行充足时两列可选同一种")
	(hud._yop_btns[1][Res.R.WOOD] as Button).pressed.emit()
	_ok(not hud._yop_ok.disabled, "两列都选后确定可点")
	hud._yop_ok.pressed.emit()
	_ok(played.size() == 1 and played[0][0] == Res.Dev.YEAR_OF_PLENTY
			and played[0][2] == Res.R.WOOD and played[0][3] == Res.R.WOOD,
		"丰收信号参数正确（两列同为木）", "实际 %s" % str(played))
	_ok(not hud._yop_dlg.visible, "确定后丰收弹窗关闭")

	# 取消路径
	hud.show_yop_dialog()
	_ok(hud._yop_sel[0] == -1 and hud._yop_sel[1] == -1, "重开丰收弹窗后两列选择复位")
	_ok(hud._yop_ok.disabled, "重开后确定置灰")
	hud.close_yop_dialog()

# ================= 6. 规则层：实际的资源转移与限流 =================

func _test_rules() -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	ctl.start_turn(0)
	var st := ctl.st
	var me: PlayerState = st.players[0]
	var o1: PlayerState = st.players[1]
	var o2: PlayerState = st.players[2]
	var o3: PlayerState = st.players[3]
	me.resources = [1, 0, 0, 0, 0]
	o1.resources = [2, 0, 0, 0, 0]
	o2.resources = [3, 0, 0, 0, 0]
	o3.resources = [0, 0, 0, 0, 0]

	# 垄断：对手归零，自己拿到合计（自己原本的 1 张保留）
	me.dev_cards = [Res.Dev.MONOPOLY]
	_ok(ctl.apply_action(0, {"type": Res.A_PLAY_DEV, "card": Res.Dev.MONOPOLY, "r": Res.R.WOOD}),
		"垄断卡可以打出")
	_ok(o1.resources[Res.R.WOOD] == 0 and o2.resources[Res.R.WOOD] == 0, "垄断后对手该资源归零")
	_ok(me.resources[Res.R.WOOD] == 6, "垄断后自己拿到 5 张 + 原有 1 张 = 6", "实际 %d" % me.resources[Res.R.WOOD])

	# 一回合最多 1 张：上面已打过，再打应被拒
	me.dev_cards = [Res.Dev.KNIGHT]
	_ok(not ctl.apply_action(0, {"type": Res.A_PLAY_DEV, "card": Res.Dev.KNIGHT}),
		"同一回合打第二张被规则层拒绝")

	# 丰收：两列选同一种，真能拿到 2 张
	var ctl2 := _fresh_game(4, 556)
	ctl2.run_setup()
	ctl2.start_turn(0)
	var s2 := ctl2.st
	var me2: PlayerState = s2.players[0]
	me2.resources = [0, 0, 0, 0, 0]
	me2.dev_cards = [Res.Dev.YEAR_OF_PLENTY]
	var bank_before: int = s2.bank[Res.R.WOOL]
	_ok(ctl2.apply_action(0, {"type": Res.A_PLAY_DEV, "card": Res.Dev.YEAR_OF_PLENTY,
			"r1": Res.R.WOOL, "r2": Res.R.WOOL}), "丰收卡可以打出")
	_ok(me2.resources[Res.R.WOOL] == 2, "两列同为羊时拿到 2 张", "实际 %d" % me2.resources[Res.R.WOOL])
	_ok(s2.bank[Res.R.WOOL] == bank_before - 2, "银行相应减少 2 张")

	# 本回合刚买的卡不能打
	var ctl3 := _fresh_game(4, 557)
	ctl3.run_setup()
	ctl3.start_turn(0)
	var me3: PlayerState = ctl3.st.players[0]
	me3.fresh_dev_cards = [Res.Dev.KNIGHT]
	_ok(not ctl3.apply_action(0, {"type": Res.A_PLAY_DEV, "card": Res.Dev.KNIGHT}),
		"本回合刚买的卡不能当回合打出")

# ================= 辅助 =================

func _ok(cond: bool, name: String, detail: String = "") -> bool:
	if cond:
		_pass += 1
		print("  [ok]   %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
	return cond

func _fresh_game(n: int, seed_value: int) -> GameController:
	var configs: Array = []
	var providers: Array = []
	for i in n:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	var ctl := GameController.new()
	ctl.new_game(configs, seed_value, true, providers)
	return ctl
