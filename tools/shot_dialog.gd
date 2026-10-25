extends SceneTree

## 「新开一局」弹窗的渲染 + 真实点击校验（**必须去掉 --headless**）。
##
## 单测（test_setup_dialog.gd）验的是"状态对不对"，这里验的是"玩家真点得到"：
##   · 开局时弹窗**自己**弹出来（不点任何按钮），且不挡住背后的棋盘；
##   · 用 root.push_input 发真实鼠标点击给「困难」按钮 → 选中真的变了；
##   · 点「开始游戏」→ 对局按选中的难度开出来，棋盘换成新种子，弹窗收起；
##   · 局中点「重开一局」→ 弹窗重开、回填本局难度、「取消」可用。
##
## 跑法（必须去掉 --headless，否则截不了图）：
##   Godot --path . --resolution 1280x720 --script res://tools/shot_dialog.gd
##
## ⚠️ 分辨率要和 project.godot 的设计分辨率（1280x720）一致。
## 传别的值只会改窗口、不改视口（stretch=canvas_items），
## 排版按 1280x720 算完再缩放，坐标全对不上。
##
## 图写到 user://，日志里会打印实际绝对路径。

const OUT := "user://dlg"

var _scene: Node
var _step := 0
var _shots: Array[String] = []
var _fails := 0
var _seed_before := 0

func _initialize() -> void:
	var packed := load("res://scenes/main.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame() -> void:
	_step += 1
	match _step:
		12:
			_verify_opening()
		13:
			_snap("%s_1_open.png" % OUT)
		14:
			_click_difficulty(0, 2)      # 小红 -> 困难（真实鼠标点击）
		16:
			_verify_pick(0, 2)
			_snap("%s_2_picked.png" % OUT)
		17:
			_click_start()
		40:
			_verify_started()
		41:
			_snap("%s_3_playing.png" % OUT)
		42:
			_open_restart()
		44:
			_verify_reopen()
			_snap("%s_4_restart.png" % OUT)
		45:
			_finish()

func _hud() -> HUD:
	return _scene.get_node("HUD")

func _director() -> GameDirector:
	return _scene.get_node("GameDirector")

## 开局弹窗应该在没有任何点击的情况下自己出现
func _verify_opening() -> void:
	var hud := _hud()
	var dir := _director()
	print("--- 开局自动弹窗 ---")
	if not hud._dlg.visible:
		print("  [FAIL] 开局时弹窗没自己弹出来")
		_fails += 1
	else:
		print("  [ok]   开局弹窗自动出现")
	if dir.ctl != null:
		print("  [FAIL] 弹窗还开着就已经开局了")
		_fails += 1
	print("   视口 %s · 浮层 size=%s" % [root.get_visible_rect().size, hud._dlg.size])
	var card := hud._dlg.get_child(1) as Control
	print("   卡片 size=%s pos=%s（居中应在 x=%.0f）" % [
		card.size, card.position, (root.get_visible_rect().size.x - card.size.x) * 0.5])
	if absf(card.position.x - (root.get_visible_rect().size.x - card.size.x) * 0.5) > 1.0:
		print("  [FAIL] 卡片没有水平居中")
		_fails += 1
	if _count(hud._dlg, "LineEdit") > 0:
		print("  [FAIL] 弹窗里还有输入框（种子应该改成每局随机）")
		_fails += 1
	else:
		print("  [ok]   弹窗里没有种子输入框")
	if _hud()._btn_dlg_cancel.visible:
		print("  [FAIL] 开局前不该有「取消」")
		_fails += 1
	_seed_before = dir.seed_value

## 真实点击：走 Viewport → GUI 的完整输入通路，不是直接 emit pressed
func _click_difficulty(row: int, diff: int) -> void:
	var hud := _hud()
	var b: Button = hud._diff_btns[row][diff]
	var pos := b.get_global_rect().get_center()
	print(">> 点「%s」的「%s」（按钮中心 %s）" % [
		GameDirector.AI_LABELS[row], GameDirector.DIFF_NAMES[diff], pos])
	_click(pos)

func _verify_pick(row: int, diff: int) -> void:
	var hud := _hud()
	var sel := hud.selected_difficulties()
	print("--- 点选校验 ---")
	print("   当前选择 %s（期望第 %d 位 = %d）" % [str(sel), row, diff])
	if sel[row] != diff:
		print("  [FAIL] 点击没选中「%s」" % GameDirector.DIFF_NAMES[diff])
		_fails += 1
	else:
		print("  [ok]   真实点击能选中难度")
	# 同一行只允许亮一个
	var lit := 0
	for b in hud._diff_btns[row]:
		if (b as Button).button_pressed:
			lit += 1
	if lit != 1:
		print("  [FAIL] 该行同时亮了 %d 档（应互斥）" % lit)
		_fails += 1

func _click_start() -> void:
	var ok := _find_button(_hud()._dlg, "开始游戏")
	if ok == null:
		print("  [FAIL] 找不到「开始游戏」按钮")
		_fails += 1
		return
	_click(ok.get_global_rect().get_center())

func _verify_started() -> void:
	var dir := _director()
	var hud := _hud()
	print("--- 开局校验 ---")
	if dir.ctl == null:
		print("  [FAIL] 点了「开始游戏」还没开局")
		_fails += 1
		return
	if hud._dlg.visible:
		print("  [FAIL] 开局后弹窗没收起")
		_fails += 1
	else:
		print("  [ok]   开始游戏后弹窗收起")
	if dir.ai_difficulties[0] != 2:
		print("  [FAIL] 难度没生效：%s" % str(dir.ai_difficulties))
		_fails += 1
	else:
		print("  [ok]   难度按选择的生效 %s" % str(dir.ai_difficulties))
	if dir.seed_value == _seed_before:
		print("  [FAIL] 种子没变（每局必须随机）")
		_fails += 1
	else:
		print("  [ok]   换了一张新地图（种子 %d）" % dir.seed_value)
	if dir.ctl.st.board.seed_used != dir.seed_value:
		print("  [FAIL] 棋盘种子不符：%d" % dir.ctl.st.board.seed_used)
		_fails += 1
	var errs: Array = dir.ctl.st.board.self_check(true)
	if errs.is_empty():
		print("  [ok]   新棋盘自检通过")
	else:
		for e in errs:
			print("  [FAIL] %s" % e)
		_fails += 1
	var logged := false
	for line in dir.ctl.st.log_lines:
		if "每局随机" in line:
			logged = true
			print("  [ok]   事件日志记录了随机种子: %s" % line.strip_edges())
	if not logged:
		print("  [FAIL] 事件日志里没有种子说明")
		_fails += 1

## 局中点「重开一局」：弹窗要回填本局难度、且「取消」可用
func _open_restart() -> void:
	var btn := _find_button(_hud(), "重开一局")
	if btn == null:
		print("  [FAIL] 找不到「重开一局」按钮")
		_fails += 1
		return
	_click(btn.get_global_rect().get_center())

func _verify_reopen() -> void:
	var hud := _hud()
	var dir := _director()
	print("--- 局中重开弹窗 ---")
	if not hud._dlg.visible:
		print("  [FAIL] 点「重开一局」没打开弹窗")
		_fails += 1
		return
	print("  [ok]   弹窗已打开")
	if not hud._btn_dlg_cancel.visible:
		print("  [FAIL] 局中打开时「取消」应该可见")
		_fails += 1
	if hud.selected_difficulties() != dir.ai_difficulties:
		print("  [FAIL] 没有回填本局难度：%s vs %s" % [
			str(hud.selected_difficulties()), str(dir.ai_difficulties)])
		_fails += 1
	else:
		print("  [ok]   回填了本局难度 %s" % str(dir.ai_difficulties))

## 发一次真实左键点击（走完整的输入通路：Viewport -> GUI -> _unhandled_input）。
## ⚠️ 必须「按下 + 抬起」两个事件都发：Godot 的 Button 默认
## action_mode = ACTION_MODE_BUTTON_RELEASE，只发按下**不会**触发 pressed
## （棋盘是按下即响应，所以别照抄 shot_help 里那个只发按下的版本）。
func _click(pos: Vector2) -> void:
	# 先移一下鼠标：按钮的 hover 状态与"点在不在里面"都靠它对齐，
	# 少了这一步，某些情况下按下事件到不了按钮。
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	root.push_input(mv)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		root.push_input(ev)

func _count(n: Node, cls: String) -> int:
	var c := 1 if n.get_class() == cls else 0
	for ch in n.get_children():
		c += _count(ch, cls)
	return c

func _find_button(n: Node, label: String) -> Button:
	if n is Button and (n as Button).text == label:
		return n
	for c in n.get_children():
		var r := _find_button(c, label)
		if r != null:
			return r
	return null

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	if err == OK:
		_shots.append(path)
		print(">> 已保存 %s（实际位置 %s）" % [path, ProjectSettings.globalize_path(path)])
	else:
		print("!! 保存失败 %s err=%d" % [path, err])

func _finish() -> void:
	print("--- 结果：%s（截图 %d 张）---" % ["PASS" if _fails == 0 else "FAIL %d" % _fails, _shots.size()])
	quit(0 if _fails == 0 else 1)
