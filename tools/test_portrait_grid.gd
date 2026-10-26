extends SceneTree

## 竖屏 3×2 操作网格单测（headless 可跑：只挂 HUD，不碰渲染）。
##
## 守三条已经被踩过的坑：
##   1. 七个按钮**永远 visible** —— 藏按钮会让 GridContainer 收掉整行，
##      面板高度跟着跳（AI 回合最明显）；阶段变化只能改 disabled / 图标 / 文案。
##   2. 「掷骰子 / 结束回合」是**同一个**按钮，按状态换图标和文案，
##      pressed 时按当前模式分发 roll_dice_pressed / end_turn_pressed。
##   3. 摆位固定：第一行 = 掷骰·结束 / 兑换 / 买发展卡，第二行 = 打发展卡 / 查看日志 / 重开一局。
##
## 用法： godot --headless --path . --script res://tools/test_portrait_grid.gd
## 退出码 0 = 全通过

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== 竖屏操作网格单测 ===")
	_run.call_deferred()

func _run() -> void:
	root.content_scale_size = Vector2i(720, 1280)
	Layout.set_portrait(true)
	var hud: HUD = load("res://ui/hud.gd").new()
	root.add_child(hud)
	# HUD._ready 里 await 了一帧才给种子卡片定位，等几帧让构建全部落地
	for i in 3:
		await process_frame

	var ctl := _fresh_game()
	var got: Array[String] = []
	hud.roll_dice_pressed.connect(func(): got.append("roll"))
	hud.end_turn_pressed.connect(func(): got.append("end"))

	_test_layout(hud)

	# ---- 主阶段：共用按钮 = 结束回合 ----
	hud.refresh(ctl.st, "你的回合：可以建设或兑换", true, true, false)
	var h_main: float = hud._btn_turn.custom_minimum_size.y
	_ok(hud._btn_turn.text == "结束回合", "主阶段文案是「结束回合」（实际 %s）" % hud._btn_turn.text)
	_ok(_icon(hud._btn_turn) == "1_end_turn.png",
		"主阶段图标是 1_end_turn.png（实际 %s）" % _icon(hud._btn_turn))
	_ok(not hud._btn_turn.disabled, "主阶段「结束回合」可点")
	hud._btn_turn.pressed.emit()

	# ---- 掷骰前：共用按钮 = 掷骰子，兑换 / 买发展卡灰着但不消失 ----
	hud.refresh(ctl.st, "你的回合：先掷骰子", true, false, true)
	_ok(hud._btn_turn.text == "掷骰子", "掷骰前文案是「掷骰子」（实际 %s）" % hud._btn_turn.text)
	_ok(_icon(hud._btn_turn) == "4_dice.png",
		"掷骰前图标是 4_dice.png（实际 %s）" % _icon(hud._btn_turn))
	_ok(not hud._btn_turn.disabled, "掷骰前「掷骰子」可点")
	_ok(hud._btn_buy.disabled and hud._btn_buy.visible, "掷骰前「买发展卡」置灰但仍在格子里")
	_ok(hud._btn_trade.visible, "掷骰前「兑换」仍在格子里")
	hud._btn_turn.pressed.emit()

	# ---- AI 回合：整行置灰，形状不动 ----
	hud.refresh(ctl.st, "小红（简单） 行动中…", false, false, false)
	_ok(hud._btn_turn.disabled, "AI 回合「掷骰子」置灰")
	_ok(_all_visible(hud), "AI 回合七个按钮全部 visible（不收行、不跳变）")
	_ok(not hud._btn_log.disabled and not hud._btn_restart.disabled,
		"AI 回合「查看日志 / 重开一局」仍可用")
	_ok(is_equal_approx(h_main, hud._btn_turn.custom_minimum_size.y),
		"三个阶段按钮行高一致（%.1f / %.1f）" % [h_main, hud._btn_turn.custom_minimum_size.y])
	_ok(got == ["end", "roll"], "共用按钮按状态分发信号（实际 %s）" % str(got))

	# ---- 开局前的空面板：全灰但不隐藏 ----
	hud.show_idle()
	_ok(_all_visible(hud), "开局前空面板也不隐藏按钮")
	var all_disabled := true
	for b: Button in hud._portrait_buttons():
		all_disabled = all_disabled and b.disabled
	_ok(all_disabled, "开局前七个按钮全部置灰")
	hud.refresh(ctl.st, "你的回合：可以建设或兑换", true, true, false)
	_ok(not hud._btn_log.disabled and not hud._btn_restart.disabled,
		"开局后「查看日志 / 重开一局」从灰态恢复")

	print("")
	print("通过 %d · 失败 %d" % [_pass, _fail])
	print("竖屏网格测试结果：%s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

# ================= 摆位 =================

## 第一行：掷骰·结束 / 兑换 / 买发展卡；第二行：打发展卡 / 查看日志 / 重开一局。
func _test_layout(hud: HUD) -> void:
	_ok(hud._act_grid.columns == 3, "网格是 3 列")
	_ok(hud._act_grid.get_child_count() == 6,
		"网格恒为 6 个格子（实际 %d）" % hud._act_grid.get_child_count())
	var want: Array = [hud._btn_turn, hud._btn_trade, hud._btn_buy,
		hud._btn_play, hud._btn_log, hud._btn_restart]
	var names: Array[String] = ["掷骰·结束", "兑换", "买发展卡", "打发展卡", "查看日志", "重开一局"]
	for i in want.size():
		var slot: Node = hud._act_grid.get_child(i)
		var btn: Node = slot.get_child(0) if slot.get_child_count() > 0 else null
		_ok(btn == want[i], "%s 在第 %d 格（第 %d 行第 %d 列）" % [names[i], i, i / 3, i % 3])

func _all_visible(hud: HUD) -> bool:
	for b: Button in hud._portrait_buttons():
		if not b.visible:
			return false
	return true

func _icon(b: Button) -> String:
	return b.icon.resource_path.get_file() if b.icon != null else "null"

func _fresh_game() -> GameController:
	var ctl := GameController.new()
	var configs: Array = []
	var providers: Array = []
	for i in 4:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	ctl.new_game(configs, 20261026, true, providers)
	ctl.run_setup()
	# 给点资源，主阶段「买发展卡」才是亮的（不然测不出"可点"）
	var p0: PlayerState = ctl.st.players[0]
	p0.resources = [6, 3, 2, 1, 4]
	return ctl

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [ok]   %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)
