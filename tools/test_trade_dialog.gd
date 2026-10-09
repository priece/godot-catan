extends SceneTree

## 银行兑换弹窗单元测试（headless 可跑，只碰 HUD 不碰渲染）。
##
## 旧版交易 UI 是"点一下即换"的按钮排，弹窗化之后交互状态变多，
## 靠肉眼回归太容易漏：左列选中 → 右列才亮、同种/缺货资源禁用、
## 确定按钮联动、信号参数、取消不触发。全部在这里断言。
##
## 用法： godot --headless --path . --script res://tools/test_trade_dialog.gd
## 退出码 0 = 全通过

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== 银行兑换弹窗单元测试 ===")
	_run_tests.call_deferred()

func _run_tests() -> void:
	var ctl := _fresh_game(4, 555)
	ctl.run_setup()
	var st := ctl.st
	# 手工构造手牌：4 木 3 砖，其他 0。木够 4:1，砖够不够要看港口比例，
	# 所以断言一律按 Rules.best_ratio_for 现算，不写死数字。
	#
	# ⚠️ resources 是 Array[int]，必须走强类型局部引用赋值：
	# 经 st.players[0]（Variant）赋值不给隐式转换，会报
	# "Invalid assignment ... with value of type 'Array'"。
	var p0: PlayerState = st.players[0]
	p0.resources = [4, 3, 0, 0, 0]

	var hud: HUD = load("res://ui/hud.gd").new()
	root.add_child(hud)
	# HUD._ready 里 await 了一帧才给种子卡片定位，等几帧让构建全部落地
	for i in 3:
		await process_frame

	hud.refresh(st, "测试", true)

	var got: Array = []
	hud.bank_trade_pressed.connect(func(g: int, t: int): got.append([g, t]))

	# ---- 入口按钮 ----
	_ok(not hud._btn_trade.disabled, "有可换组合时「兑换」按钮可点")

	# ---- 打开弹窗 ----
	hud.show_trade_dialog()
	_ok(hud._trade_dlg.visible, "弹窗可见")
	_ok(hud._trade_give_btns.size() == 5 and hud._trade_take_btns.size() == 5,
		"左右各 5 个资源按钮", "实际 %d / %d" % [hud._trade_give_btns.size(), hud._trade_take_btns.size()])
	_ok(hud._trade_ok.disabled, "未选时确定按钮置灰")

	# ---- 左列可用性：与 Rules 现算的期望一致 ----
	for r in Res.R_COUNT:
		var ratio := Rules.best_ratio_for(st, 0, r)
		var expect_enabled: bool = p0.count(r) >= ratio
		var actual_enabled: bool = not (hud._trade_give_btns[r] as Button).disabled
		_ok(actual_enabled == expect_enabled,
			"左列[%s]可用性正确（持有 %d / 比例 %d）" % [UIPalette.RES_SHORT[r], p0.count(r), ratio],
			"期望 %s 实际 %s" % [expect_enabled, actual_enabled])

	# ---- 右列：没选付出资源时全灰 ----
	var all_disabled := true
	for r in Res.R_COUNT:
		if not (hud._trade_take_btns[r] as Button).disabled:
			all_disabled = false
	_ok(all_disabled, "未选付出资源时右列全灰")

	# ---- 点选付出资源（木材） ----
	(hud._trade_give_btns[Res.R.WOOD] as Button).pressed.emit()
	_ok(hud._give_sel == Res.R.WOOD, "左列选中木材")
	_ok((hud._trade_take_btns[Res.R.WOOD] as Button).disabled, "右列同种资源（木）禁用")
	_ok(not (hud._trade_take_btns[Res.R.GRAIN] as Button).disabled, "右列麦子可选")
	_ok(hud._trade_ok.disabled, "只选了付出侧，确定仍置灰")

	# 银行缺货的资源不可选
	st.bank[Res.R.WOOL] = 0
	hud._refresh_take_states()
	_ok((hud._trade_take_btns[Res.R.WOOL] as Button).disabled, "银行缺货的资源（羊）禁用")
	st.bank[Res.R.WOOL] = 19

	# ---- 点选换回资源（麦）→ 确定 ----
	(hud._trade_take_btns[Res.R.GRAIN] as Button).pressed.emit()
	_ok(hud._take_sel == Res.R.GRAIN, "右列选中麦子")
	_ok(not hud._trade_ok.disabled, "两侧都选后确定可点")
	(hud._trade_ok as Button).pressed.emit()
	_ok(got.size() == 1 and got[0][0] == Res.R.WOOD and got[0][1] == Res.R.GRAIN,
		"bank_trade_pressed 参数正确（木→麦）", "实际 %s" % str(got))
	_ok(not hud._trade_dlg.visible, "确定后弹窗关闭")

	# ---- 取消路径：不触发信号，状态复位 ----
	hud.show_trade_dialog()
	(hud._trade_give_btns[Res.R.WOOD] as Button).pressed.emit()
	hud.close_trade_dialog()
	_ok(got.size() == 1, "取消不产生交易信号", "实际 %s" % str(got))
	hud.show_trade_dialog()
	_ok(hud._give_sel == -1 and hud._take_sel == -1, "重开后两侧选择复位")
	_ok(hud._trade_ok.disabled, "重开后确定置灰")
	_ok(hud._trade_hint.text == "先在左侧选一个要付出的资源", "重开后提示语复位", hud._trade_hint.text)
	hud.close_trade_dialog()

	# ---- 非行动回合：兑换按钮置灰 ----
	hud.refresh(st, "等待", false)
	_ok(hud._btn_trade.disabled, "非本方回合「兑换」按钮置灰")

	print("")
	print("通过 %d · 失败 %d" % [_pass, _fail])
	print("弹窗测试结果：%s" % ("PASS" if _fail == 0 else "FAIL"))
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, name: String, detail: String = "") -> bool:
	if cond:
		_pass += 1
		print("  [ok]   %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
	return cond

# ================= 辅助 =================

func _fresh_game(n: int, seed_value: int) -> GameController:
	var configs: Array = []
	var providers: Array = []
	for i in n:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	var ctl := GameController.new()
	ctl.new_game(configs, seed_value, true, providers)
	return ctl
