extends SceneTree

## 「新开一局」开局弹窗单元测试（headless 可跑，只碰 HUD 不碰渲染）。
##
## 这个弹窗承担两件事，任何一件写错都会让玩家开局就卡住：
##   1. 开局前给三个电脑各选一档难度（互斥、回填、越界兜底）；
##   2. **不再有种子输入框** —— 棋盘每局自动随机。
## 第 2 条特别容易"改着改着又长回来"，所以这里直接断言弹窗里 LineEdit 数量为 0。
##
## 用法： godot --headless --path . --script res://tools/test_setup_dialog.gd
## 退出码 0 = 全通过

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== 开局弹窗单元测试 ===")
	_run_tests.call_deferred()

func _run_tests() -> void:
	var hud: HUD = load("res://ui/hud.gd").new()
	root.add_child(hud)
	for i in 3:
		await process_frame

	var got: Array = []
	hud.new_game_pressed.connect(func(d: Array): got.append(d))

	# ---- 难度合法化（静态纯函数，与弹窗选中的值同一套规则）----
	_ok(_eq(GameDirector.sanitize_diffs([2, 0, 1]), [2, 0, 1]), "合法数组原样通过")
	_ok(_eq(GameDirector.sanitize_diffs([9, -3]), [2, 0, 1]), "越界夹到 [困难, 简单, 标准]",
		"实际 %s" % str(GameDirector.sanitize_diffs([9, -3])))
	_ok(_eq(GameDirector.sanitize_diffs([]), [1, 1, 1]), "空数组 = 全「标准」")

	# ---- 结构 ----
	_ok(not hud._dlg.visible, "弹窗默认收起（交给 GameDirector 决定何时开）")
	_ok(hud._diff_btns.size() == GameDirector.AI_LABELS.size(),
		"每个电脑一行难度选择", "实际 %d 行" % hud._diff_btns.size())
	var btn_n := 0
	var labels_ok := true
	for row in hud._diff_btns:
		btn_n += (row as Array).size()
		for d in (row as Array).size():
			if ((row as Array)[d] as Button).text != GameDirector.DIFF_NAMES[d]:
				labels_ok = false
	_ok(btn_n == 9 and labels_ok, "每行 3 档（简单/标准/困难），共 9 个", "实际 %d 个" % btn_n)
	_ok(_count_lineedit(hud._dlg) == 0, "弹窗里没有任何输入框（种子已改为每局随机）")

	# ---- 回填 ----
	hud.select_difficulties([2, 0, 1])
	_ok(_eq(hud.selected_difficulties(), [2, 0, 1]), "难度回填后能原样读出",
		"实际 %s" % str(hud.selected_difficulties()))
	_ok(_one_pressed_per_row(hud), "每行同时只有一档被选中（互斥）")
	# 越界 / 缺项：夹到合法范围、缺的按「标准」补 —— 不能崩，也不能读出 -1
	hud.select_difficulties([9])
	_ok(_eq(hud.selected_difficulties(), [2, 1, 1]), "越界夹到「困难」、缺项补「标准」",
		"实际 %s" % str(hud.selected_difficulties()))
	hud.select_difficulties([])
	_ok(_eq(hud.selected_difficulties(), [1, 1, 1]), "空数组 = 全「标准」",
		"实际 %s" % str(hud.selected_difficulties()))

	# ---- 开局前：不能取消 ----
	hud.show_new_game_dialog([0, 2, 1], false)
	_ok(hud._dlg.visible, "开局前弹窗能打开")
	_ok(not hud._btn_dlg_cancel.visible, "开局前「取消」隐藏（没有本局可回）")
	_ok(_eq(hud.selected_difficulties(), [0, 2, 1]), "打开时回填传入的难度")
	_ok("种子" not in hud._diff_hint.text or "随机" in hud._diff_hint.text,
		"提示文案说明棋盘自动随机", "实际：%s" % hud._diff_hint.text)

	# ---- 点「开始游戏」----
	var ok_btn := _find_button(hud._dlg, "开始游戏")
	_ok(ok_btn != null, "有「开始游戏」主按钮")
	if ok_btn != null:
		ok_btn.pressed.emit()
	_ok(got.size() == 1 and _eq(got[0], [0, 2, 1]), "信号带出选中的三个难度",
		"实际 %s" % str(got))
	_ok(not hud._dlg.visible, "开始后弹窗自动收起")

	# ---- 局中：可取消，取消不发信号 ----
	got.clear()
	hud.on_new_game(123456, [2, 2, 2])
	hud._open_new_game_dialog()
	_ok(hud._dlg.visible and hud._btn_dlg_cancel.visible, "局中打开时「取消」可见")
	_ok(_eq(hud.selected_difficulties(), [2, 2, 2]), "局中回填本局难度",
		"实际 %s" % str(hud.selected_difficulties()))
	_ok("123456" in hud._diff_hint.text, "提示里带上当前种子（排查用）",
		"实际：%s" % hud._diff_hint.text)
	var cancel_btn := _find_button(hud._dlg, "取消")
	if cancel_btn != null:
		cancel_btn.pressed.emit()
	_ok(not hud._dlg.visible and got.is_empty(), "取消只关弹窗、不发开局信号")

	# ---- 回车 = 开始游戏 ----
	hud.show_new_game_dialog([1, 1, 0], false)
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ENTER
	hud._unhandled_input(ev)
	_ok(got.size() == 1 and _eq(got[0], [1, 1, 0]), "回车等于点「开始游戏」",
		"实际 %s" % str(got))

	# ---- 开局前 Esc 不许关（否则留下一张空棋盘）----
	hud.show_new_game_dialog([1, 1, 1], false)
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	hud._unhandled_input(esc)
	_ok(hud._dlg.visible, "开局前 Esc 不关弹窗")
	hud.show_new_game_dialog([1, 1, 1], true)
	hud._unhandled_input(esc)
	_ok(not hud._dlg.visible, "局中 Esc = 取消")

	print("")
	print("开局弹窗测试：%d 通过 / %d 失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

# ---------------- 工具 ----------------

## 逐项比较（不用 `==`：带类型的 Array[int] 与字面量 Array 直接比不一定相等，
## 这里只关心值，不关心容器类型）
func _eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true

func _count_lineedit(n: Node) -> int:
	var c := 1 if n is LineEdit else 0
	for ch in n.get_children():
		c += _count_lineedit(ch)
	return c

func _one_pressed_per_row(hud: HUD) -> bool:
	for row in hud._diff_btns:
		var n := 0
		for b in row:
			if (b as Button).button_pressed:
				n += 1
		if n != 1:
			return false
	return true

func _find_button(n: Node, label: String) -> Button:
	if n is Button and (n as Button).text == label:
		return n
	for c in n.get_children():
		var r := _find_button(c, label)
		if r != null:
			return r
	return null

func _ok(cond: bool, what: String, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [ok]   %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  ← " + extra) if extra != "" else ""])
