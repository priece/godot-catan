extends SceneTree

## 发展卡弹窗的视觉校验：单测只能验逻辑，排版/高亮/居中必须看画面。
## 抓 3 张图：选卡弹窗、垄断单列弹窗（已选中）、丰收两列弹窗（两列都选）。
##
## 跑法（必须去掉 --headless，否则截不了图）：
##   Godot --path . --resolution 1280x720 --script res://tools/shot_dev_dialog.gd
##
## ⚠️ 分辨率必须和设计分辨率一致，理由同 shot_dialog.gd。
## ⚠️ 只挂 HUD、不加载 main.tscn：主场景开局在布置阶段，发展卡按钮是灰的。
##
## 图写到 user://（跨平台可写目录），日志里会打印实际绝对路径，别去找 E:/xxx。
## 不写死本机路径：别人 clone 后没有 E 盘，save_png 会直接失败。

const OUT := "user://dev_dlg"

var _hud: HUD
var _step := 0
var _fails := 0
var _cards: Array = []      ## 待校验的卡片（居中 + 不出视口）

func _initialize() -> void:
	var w := root.get_visible_rect().size

	# 棋盘区留个浅底，否则截出来是大片透明，看不出弹窗压在什么东西上
	var bg := ColorRect.new()
	bg.color = Color(0.906, 0.898, 0.882)
	bg.size = w
	root.add_child(bg)

	_hud = load("res://ui/hud.gd").new()
	root.add_child(_hud)

	var ctl := GameController.new()
	var configs: Array = []
	var providers: Array = []
	for i in 4:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	ctl.new_game(configs, 20261009, true, providers)
	ctl.run_setup()

	# 手牌：骑士 2 张 + 修路 + 丰收 + 垄断 + 胜利点（胜利点不该出现在列表里）
	var p0: PlayerState = ctl.st.players[0]
	p0.dev_cards = [
		Res.Dev.KNIGHT, Res.Dev.KNIGHT, Res.Dev.ROAD_BUILDING,
		Res.Dev.YEAR_OF_PLENTY, Res.Dev.MONOPOLY, Res.Dev.VICTORY,
	]
	p0.resources = [4, 2, 1, 3, 0]
	# 让垄断弹窗有话可说：对手手里木 5 张、麦 2 张，其余 0
	var o1: PlayerState = ctl.st.players[1]
	var o2: PlayerState = ctl.st.players[2]
	var o3: PlayerState = ctl.st.players[3]
	o1.resources = [2, 0, 0, 0, 0]
	o2.resources = [3, 0, 2, 0, 0]
	o3.resources = [0, 0, 0, 0, 0]

	RenderingServer.frame_post_draw.connect(_on_frame)
	_ready.call_deferred(ctl)

func _ready(ctl: GameController) -> void:
	for i in 3:
		await process_frame
	# 掷骰前的窗口：能看到「掷骰子」+「打发展卡」，操作行藏着
	_hud.refresh(ctl.st, "轮到你了：先「掷骰子」，或打出 1 张发展卡", true, false, true)
	_hud.set_turn_info(ctl.st.round, 0)
	_hud.set_log(ctl.st.log_lines)
	print(">> 掷骰子按钮 visible=%s · 打发展卡 disabled=%s"
		% [_hud._btn_roll.visible, _hud._btn_play.disabled])
	if not _hud._btn_roll.visible or _hud._btn_play.disabled:
		print("  [FAIL] 掷骰前窗口的按钮状态不对")
		_fails += 1

func _on_frame() -> void:
	_step += 1
	match _step:
		6:
			_hud.show_dev_dialog()
		8:
			_snap("%s_1_pick.png" % OUT)
			_open_mono()
		11:
			_pick_mono()
		13:
			_snap("%s_2_monopoly.png" % OUT)
			_switch_to_yop()
		16:
			_pick_yop()
		18:
			_snap("%s_3_plenty.png" % OUT)
			_verify()
		20:
			_finish()

func _open_mono() -> void:
	# 列表顺序：骑士 / 修路 / 丰收 / 垄断 → 最后一项是垄断
	var box := _hud._dev_box
	var last: Button = box.get_child(box.get_child_count() - 1)
	print(">> 选卡弹窗共 %d 项，点最后一项（%s）" % [box.get_child_count(), last.text])
	last.pressed.emit()

func _pick_mono() -> void:
	_cards.append(_hud._mono_card)
	var b: Button = _hud._mono_btns[Res.R.WOOD]
	if b.disabled:
		print("  [FAIL] 垄断弹窗里木材不该禁用")
		_fails += 1
		return
	b.pressed.emit()
	print(">> 垄断选中：%s" % _hud._mono_hint.text)

func _switch_to_yop() -> void:
	_hud.close_mono_dialog()
	_hud.close_dev_dialog()
	_hud.show_dev_dialog()
	var box := _hud._dev_box
	# 骑士(0) / 修路(1) / 丰收(2) / 垄断(3)
	(box.get_child(2) as Button).pressed.emit()
	_cards.append(_hud._yop_card)

func _pick_yop() -> void:
	(_hud._yop_btns[0][Res.R.ORE] as Button).pressed.emit()
	(_hud._yop_btns[1][Res.R.GRAIN] as Button).pressed.emit()
	print(">> 丰收选中：%s" % _hud._yop_hint.text)
	if _hud._yop_ok.disabled:
		print("  [FAIL] 两列都选了确定还是灰的")
		_fails += 1
	_cards.append(_hud._dev_card)

func _verify() -> void:
	var vp := root.get_visible_rect().size
	for c in _cards:
		# _cards 是无类型 Array，取出来要显式标类型才能做算术（否则报"Cannot infer the type"）
		var card: Control = c
		var cx := (vp.x - card.size.x) * 0.5
		if absf(card.position.x - cx) > 2.0:
			print("  [FAIL] 卡片没水平居中：pos.x=%.0f 期望 %.0f" % [card.position.x, cx])
			_fails += 1
		elif card.position.y < 0 or card.position.y + card.size.y > vp.y:
			print("  [FAIL] 卡片超出视口：pos=%s size=%s" % [card.position, card.size])
			_fails += 1
		else:
			print("  [ok]   卡片居中且在视口内（%.0f×%.0f @ %.0f,%.0f）"
				% [card.size.x, card.size.y, card.position.x, card.position.y])

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	if img.save_png(path) == OK:
		print(">> 已保存 %s（实际位置 %s）" % [path, ProjectSettings.globalize_path(path)])
	else:
		print("!! 保存失败 %s（实际位置 %s）" % [path, ProjectSettings.globalize_path(path)])
		_fails += 1

func _finish() -> void:
	print("--- 结果：%s ---" % ("PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)
