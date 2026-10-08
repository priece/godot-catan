extends SceneTree

## 重开面板的交互校验：截图工具只负责静态画面，点不到按钮。
## 这里手动驱动 HUD 的浮层，抓 3 张图：
##   1. 面板打开的样子（定位 / 遮挡 / 有没有超出屏幕）
##   2. 输入了非数字时被输入框直接挡掉（种子只能是数字）
##   3. 真正走一遍"确定"按钮，确认信号连到 director 且棋盘真的换了
##
## 跑法（必须去掉 --headless，否则截不了图）：
##   Godot --path . --resolution 1280x720 --script res://tools/shot_dialog.gd
##
## ⚠️ 分辨率要和 project.godot 的设计分辨率（1280x720）一致。
## 传别的值只会改窗口、不改视口（stretch=canvas_items），
## 排版按 1280x720 算完再缩放，坐标全对不上。
##
## 会把图写到 /tmp/ 下面，并在日志里打印关键状态。

const OUT := "/tmp/dlg"

var _scene: Node
var _step := 0
var _shots: Array[String] = []
var _fails := 0

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame() -> void:
	_step += 1
	if _step == 5:
		_open_dialog()
	elif _step == 8:
		_snap("%s_1_open.png" % OUT)
		_type_bad_seed()
	elif _step == 11:
		_verify_sanitize()
		_snap("%s_2_bad_input.png" % OUT)
		_type_good_seed()
	elif _step == 14:
		_snap("%s_3_typed.png" % OUT)
		_fire()
	elif _step == 40:
		_verify_3()
	elif _step == 44:
		_snap("%s_4_after.png" % OUT)
		_finish()
	elif _step > 46:
		return

func _hud() -> HUD:
	return _scene.get_node("HUD")

func _director() -> GameDirector:
	return _scene.get_node("GameDirector")

func _open_dialog() -> void:
	var hud := _hud()
	var dir := _director()
	print(">> 打开重开面板（当前种子 %d）" % dir.seed_value)
	hud.show_dialog(dir.seed_value)
	# 浮层尺寸全靠 anchor 猜不得，打出来看
	var vp := root.get_visible_rect()
	print("   视口 %s · 浮层 size=%s pos=%s" % [vp.size, hud._dlg.size, hud._dlg.position])
	var center := hud._dlg.get_child(1)
	var card := center as Control
	print("   卡片 size=%s pos=%s（居中应在 x=%.0f）" % [
		card.size, card.position, (vp.size.x - card.size.x) * 0.5])
	var edit := hud._seed_edit
	print("   输入框 size=%s pos=%s" % [edit.size, edit.position])

func _type_bad_seed() -> void:
	var hud := _hud()
	hud._seed_edit.text = ""
	hud._seed_edit.grab_focus()
	print(">> 真实键盘输入 'a b 1 2 c'，期望只剩 '12'")
	for ch in ["a", "b", "1", "2", "c"]:
		_key(ch)

func _type_good_seed() -> void:
	var hud := _hud()
	hud._seed_edit.text = ""
	hud._seed_edit.grab_focus()
	print(">> 真实键盘输入 '314159'，期望原样保留")
	for ch in ["3", "1", "4", "1", "5", "9"]:
		_key(ch)

## 喂一个真实按键事件，走和玩家打字完全相同的路径。
##
## ⚠️ 千万别用 `_seed_edit.text = "..."` 代替：LineEdit 程序化赋值**不会**
## 触发 text_changed（实测 hits=[]），那样测不到任何"输入即处理"的逻辑，
## 只会得到一个假阳性/假阴性。必须走 Viewport 输入链。
## 另外 gui_input 是**信号**不是方法，不能直接调用 —— 用 root.push_input()。
func _key(ch: String) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.unicode = ch.unicode_at(0)
	ev.keycode = OS.find_keycode_from_string(ch)
	root.push_input(ev)

func _fire() -> void:
	var hud := _hud()
	var dir := _director()
	print(">> 点「确定」（输入框里是 %s）" % hud._seed_edit.text)
	var before := dir.seed_value
	var ok := _find_button(hud._dlg, "确定")
	if ok == null:
		print("  [FAIL] 找不到「确定」按钮 —— 手打的种子将无法提交")
		_fails += 1
		return
	ok.pressed.emit()
	print("   信号发出后 seed_value: %d -> %d" % [before, dir.seed_value])

func _find_button(n: Node, label: String) -> Button:
	if n is Button and (n as Button).text == label:
		return n
	for c in n.get_children():
		var r := _find_button(c, label)
		if r != null:
			return r
	return null

func _verify_sanitize() -> void:
	var hud := _hud()
	print("--- 输入过滤校验 ---")
	print("  非数字被挡后的内容: '%s'（期望 '12'）" % hud._seed_edit.text)
	if hud._seed_edit.text != "12":
		print("  [FAIL] 非数字没被挡掉")
		_fails += 1
	else:
		print("  [ok]   非数字被挡在输入框外")
	var names := ["随机一局", "沿用本局", "取消", "确定"]
	var missing := ""
	for nm in names:
		if _find_button(hud._dlg, nm) == null:
			missing += nm + " "
	if missing != "":
		print("  [FAIL] 缺按钮: %s" % missing)
		_fails += 1
	else:
		print("  [ok]   随机一局 / 沿用本局 / 取消 / 确定 四个按钮都在")

func _verify_3() -> void:
	var dir := _director()
	var ctl := dir.ctl
	print("--- 校验 ---")
	if dir.seed_value == 314159:
		print("  [ok]   director 收到种子 314159")
	else:
		print("  [FAIL] 种子没生效: %d" % dir.seed_value)
		_fails += 1
	# 日志里应该写了新种子
	var found := false
	for line in ctl.st.log_lines:
		if "314159" in line:
			found = true
			print("  [ok]   事件日志记录了新种子: %s" % line.strip_edges())
	if not found:
		print("  [FAIL] 事件日志里找不到新种子")
		_fails += 1
	# 浮层必须已经收起来，否则会挡住棋盘
	if _hud()._dlg.visible:
		print("  [FAIL] 重开后浮层没收起")
		_fails += 1
	else:
		print("  [ok]   重开后浮层已收起")
	# 棋盘确实是新生成的（种子变了必然变，但要确认没崩）
	if ctl.st.board.seed_used == 314159:
		print("  [ok]   棋盘用新种子重建 (seed_used=%d)" % ctl.st.board.seed_used)
	else:
		print("  [FAIL] 棋盘种子不符: %d" % ctl.st.board.seed_used)
		_fails += 1
	var errs: Array = ctl.st.board.self_check(true)
	if errs.is_empty():
		print("  [ok]   新棋盘自检通过")
	else:
		for e in errs:
			print("  [FAIL] %s" % e)
		_fails += 1
	# 上一局的日志必须还在（日志只增不减）
	print("  日志总条数: %d（含历史）" % ctl.st.log_lines.size())

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		_shots.append(path)
		print(">> 已保存 %s" % path)
	else:
		print("!! 保存失败 %s err=%d" % [path, err])

func _finish() -> void:
	print("--- 结果：%s（截图 %d 张）---" % ["PASS" if _fails == 0 else "FAIL %d" % _fails, _shots.size()])
	quit(0 if _fails == 0 else 1)