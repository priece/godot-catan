extends SceneTree

## 银行兑换弹窗的视觉校验：单测只能验逻辑，排版/高亮/居中必须看画面。
## 抓 3 张图：刚打开（未选）、选中付出侧（左列高亮 + 右列解锁）、两侧都选。
##
## 跑法（必须去掉 --headless，否则截不了图）：
##   Godot --path . --resolution 1280x720 --script res://tools/shot_trade_dialog.gd
##
## ⚠️ 分辨率必须和设计分辨率一致，理由同 shot_dialog.gd。
## ⚠️ 只挂 HUD、不加载 main.tscn：主场景开局在布置阶段，兑换按钮是灰的，
##    得先手动摆完房子才能点开，绕远路。这里直接造局面喂给 HUD。
##
## 图写到 user://（跨平台可写目录），日志里会打印实际绝对路径，别去找 E:/xxx。
## 不写死本机路径：别人 clone 后没有 E 盘，save_png 会直接失败。

const OUT := "user://trade_dlg"

var _hud: HUD
var _step := 0
var _fails := 0

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

	# 给点资源，让左右两列有的可选、有的置灰，截图才有信息量
	var p0: PlayerState = ctl.st.players[0]
	p0.resources = [6, 3, 0, 1, 5]

	RenderingServer.frame_post_draw.connect(_on_frame)
	# 等 HUD 的 _ready 跑完（里面 await 了一帧给种子卡片定位）
	_ready.call_deferred(ctl)

func _ready(ctl: GameController) -> void:
	for i in 3:
		await process_frame
	_hud.refresh(ctl.st, "你的回合：可以建设或兑换", true)
	_hud.set_turn_info(ctl.st.round, 7)
	_hud.set_log(ctl.st.log_lines)
	print(">> 兑换按钮 disabled=%s" % _hud._btn_trade.disabled)
	if _hud._btn_trade.disabled:
		print("  [FAIL] 兑换按钮不该是灰的")
		_fails += 1
	_hud.show_trade_dialog()
	var card := _hud._trade_card
	print("   视口 %s · 卡片 size=%s pos=%s" % [
		root.get_visible_rect().size, card.size, card.position])

func _on_frame() -> void:
	_step += 1
	if _step == 8:
		_snap("%s_1_open.png" % OUT)
		_click_give()
	elif _step == 11:
		_snap("%s_2_give.png" % OUT)
		_click_take()
	elif _step == 14:
		_snap("%s_3_both.png" % OUT)
		_verify()
	elif _step > 16:
		return

func _click_give() -> void:
	# 选木材（持有 6，够 4:1）
	var b: Button = _hud._trade_give_btns[Res.R.WOOD]
	b.pressed.emit()
	print(">> 左列选中木材 → 提示语：%s" % _hud._trade_hint.text)

func _click_take() -> void:
	var b: Button = _hud._trade_take_btns[Res.R.GRAIN]
	if b.disabled:
		print("  [FAIL] 右列麦子不该禁用")
		_fails += 1
		return
	b.pressed.emit()
	print(">> 右列选中麦子 → 提示语：%s" % _hud._trade_hint.text)

func _verify() -> void:
	var vp := root.get_visible_rect().size
	var card := _hud._trade_card
	var cx := (vp.x - card.size.x) * 0.5
	if absf(card.position.x - cx) > 2.0:
		print("  [FAIL] 卡片没水平居中：pos.x=%.0f 期望 %.0f" % [card.position.x, cx])
		_fails += 1
	else:
		print("  [ok]   卡片水平居中（pos.x=%.0f）" % card.position.x)
	if card.position.y < 0 or card.position.y + card.size.y > vp.y:
		print("  [FAIL] 卡片超出视口：pos=%s size=%s" % [card.position, card.size])
		_fails += 1
	else:
		print("  [ok]   卡片完整落在 720 高的视口内（pos.y=%.0f h=%.0f）" % [card.position.y, card.size.y])
	if _hud._trade_ok.disabled:
		print("  [FAIL] 两侧都选了确定还是灰的")
		_fails += 1
	else:
		print("  [ok]   两侧都选后确定可点")
	_finish()

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
