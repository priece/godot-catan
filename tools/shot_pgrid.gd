extends SceneTree

## 竖屏操作网格（大方块按钮）的视觉校验。
## shot_portrait.gd 走 auto 演示，人类座位被 AI 占掉，永远看不到
## 掷骰前 / 主阶段两个关键界面；这里像 shot_trade_dialog.gd 一样只挂 HUD、
## 手动造局面喂 refresh()，把三种阶段状态各截一张：
##   1. 主阶段（结束回合/买发展卡/兑换 + 常驻行）
##   2. 掷骰前（掷骰子与打发展卡共格互斥，A2/A3 空格）
##   3. AI 回合（A 行整体隐藏，只剩常驻行）
##
## 跑法（禁止 --headless）：Godot --path . --resolution 720x1280 --script res://tools/shot_pgrid.gd
## ⚠️ SceneTree --script 上下文没有 user://，PNG 写到当前工作目录（_1_main.png 等）。

const OUT := "user://pgrid"

var _hud: HUD
var _ctl: GameController
var _step := 0

func _initialize() -> void:
	# 模拟 BoardView._ready 的朝向锁 + 手机竖屏安全区（不加载 main.tscn）
	root.content_scale_size = Vector2i(720, 1280)
	Layout.set_portrait(true)
	SafeArea.set_override(Vector4(18, 34, 18, 18))

	var w := root.get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.906, 0.898, 0.882)
	bg.size = w
	root.add_child(bg)

	_hud = load("res://ui/hud.gd").new()
	root.add_child(_hud)

	_ctl = GameController.new()
	var configs: Array = []
	var providers: Array = []
	for i in 4:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	_ctl.new_game(configs, 20261009, true, providers)
	_ctl.run_setup()
	var p0: PlayerState = _ctl.st.players[0]
	p0.resources = [6, 3, 2, 1, 4]
	# 给几张能打的卡，「打发展卡」按钮才显示张数且可点
	p0.dev_cards = [Res.Dev.KNIGHT, Res.Dev.KNIGHT, Res.Dev.YEAR_OF_PLENTY]

	RenderingServer.frame_post_draw.connect(_on_frame)
	_go.call_deferred()

func _go() -> void:
	for i in 3:
		await process_frame
	_hud.set_turn_info(_ctl.st.round, 7)
	_hud.set_log(_ctl.st.log_lines)
	# 状态 1：主阶段
	_hud.refresh(_ctl.st, "你的回合：可以建设或兑换", true, true, false)
	_step = 1

func _on_frame() -> void:
	if _step == 1:
		_step = 2
		_snap("_1_main.png")
		# 状态 2：掷骰前
		_hud.refresh(_ctl.st, "你的回合：可以先打发展卡，或直接掷骰子", true, false, true)
	elif _step == 2:
		_step = 3
		_snap("_2_preroll.png")
		# 状态 3：AI 回合（A 行隐藏）
		_hud.refresh(_ctl.st, "小红（简单） 行动中…", false, false, false)
	elif _step == 3:
		_step = 4
		_snap("_3_ai.png")
		print("--- 竖屏操作网格截图完成 ---")
		quit(0)

func _snap(path: String) -> void:
	var img := root.get_texture().get_image()
	if img.save_png(path) == OK:
		print(">> 已保存 %s（实际位置 %s）" % [path, ProjectSettings.globalize_path(path)])
	else:
		print("!! 保存失败 %s" % path)
