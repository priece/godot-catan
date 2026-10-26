extends SceneTree

## 竖屏分区渲染验证 —— **禁止 --headless**（trap 4：frame_post_draw 不触发，
## 主循环空转被 kill 成 exit 137）。
##
## 用法（auto 由 game_director.gd 解析，把人类座位交给 AI，整局自动推进）：
##   Godot --path . --resolution 720x1280 --script res://tools/shot_portrait.gd -- auto
##
## 它干五件事（plan-2026.10.15.a §5.2）：
##   1. 注入手机竖屏安全区 (18,34,18,18)，加载 main.tscn，等 20 帧
##      （§4.4 实测：写 content_scale_size 当帧 vp 即生效，20 帧绰绰有余）；
##   2. 断言朝向锁定、px_per_unit 与 Layout 算式一致、棋盘落在 board_rect 内、
##      信息区（底色 + 内容盒）不压棋盘且让开安全区；
##   3. 真实点击「查看日志」按钮（root.push_input；trap 3：推送坐标按窗口坐标
##      解释，要乘 窗口/视口 倍率换算），断言日志弹窗打开、日志非空，Esc 能关掉；
##   4. 竖屏下点**下方信息区**也要能关掉图例（`_input` 是唯一能看到这次点击的地方，
##      见 board_view.gd `_input` 的注释）；
##   5. 存两张图（分区全景 / 弹窗打开态）到 user:// 并打印绝对路径，
##      供 crop_shot.gd 放大检查 20px 细节。

var _scene: Node
var _bv: BoardView
var _hud: HUD
var _fails := 0
var _step := 0
var _wait := 20

func _initialize() -> void:
	SafeArea.set_override(Vector4(18, 34, 18, 18))
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("!! 无法加载主场景")
		quit(1)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_frame)

func _on_frame() -> void:
	if _step > 3:
		return
	if _wait > 0:
		_wait -= 1
		return
	match _step:
		0:
			_step0()
		1:
			_step1()
		2:
			_step2()
		_:
			_step3()

# ---------- 第 0 步：分区断言 + 全景截图 + 点「查看日志」 ----------
func _step0() -> void:
	_bv = _find_board(_scene)
	_hud = _find_hud(_scene)
	if _bv == null or _hud == null:
		print("!! 没找到 BoardView / HUD")
		quit(1)
		return

	var vp: Vector2 = root.get_visible_rect().size
	var ins := SafeArea.insets()
	print("== 竖屏分区验证 ==  vp=%.0f×%.0f  安全区=%s  px=%.2f  原点=%s" % [
		vp.x, vp.y, ins, _bv.px_per_unit, _bv.board_origin])

	_check("Layout.is_portrait()=true", Layout.is_portrait())
	_check("视口竖向 vp.x<vp.y（%.0f<%.0f）" % [vp.x, vp.y], vp.x < vp.y)

	# px 与原点必须等于 Layout 算式（plan-a §4.3 行 2：720×1280 → 62.96）
	var bz := Layout.board_rect(vp, ins)
	var want_px := Layout.px_per_unit_for(bz)
	_check("px_per_unit=%.2f 符合 Layout 算式（%.2f）" % [_bv.px_per_unit, want_px],
		absf(_bv.px_per_unit - want_px) < 0.5)
	_check("棋盘原点=棋盘区中心", _bv.board_origin.is_equal_approx(bz.get_center()))

	# 棋盘外接尺寸（含海岸带 + 港口牌外推）完整落在棋盘区内
	var half := Vector2(Layout.BOARD_W_U, Layout.BOARD_H_U) * _bv.px_per_unit * 0.5
	_check("棋盘外接框在棋盘区内（x: %.0f~%.0f / y: %.0f~%.0f）" % [
		_bv.board_origin.x - half.x, _bv.board_origin.x + half.x,
		_bv.board_origin.y - half.y, _bv.board_origin.y + half.y],
		_bv.board_origin.x - half.x >= bz.position.x - 0.5
		and _bv.board_origin.x + half.x <= bz.end.x + 0.5
		and _bv.board_origin.y - half.y >= bz.position.y - 0.5
		and _bv.board_origin.y + half.y <= bz.end.y + 0.5)

	# 信息区：底色铺到屏边、顶不压棋盘；内容盒让开安全区
	var pr := Layout.panel_rect(vp, ins)
	_check("信息区顶 %.1f ≥ 棋盘底 %.1f（不压棋盘）" % [pr.position.y, bz.end.y],
		pr.position.y >= bz.end.y - 0.5)
	_check("信息区底色横贯屏宽 %.0f" % pr.size.x, is_equal_approx(pr.size.x, vp.x))
	_check("_bg 按 panel_rect 摆放", _hud._bg.position.is_equal_approx(pr.position)
		and _hud._bg.size.is_equal_approx(pr.size))
	var cr := Layout.content_rect(vp, ins)
	# 实际值一起打出来：容器被最小尺寸撑大时，光说"没对上"看不出是被谁撑的
	_check("_box 按 content_rect 摆放（实际 pos %.1f,%.1f size %.1f×%.1f / 期望 %.1f,%.1f %.1f×%.1f · min %.1f）" % [
		_hud._box.position.x, _hud._box.position.y, _hud._box.size.x, _hud._box.size.y,
		cr.position.x, cr.position.y, cr.size.x, cr.size.y,
		_hud._box.get_combined_minimum_size().y],
		_hud._box.position.is_equal_approx(cr.position)
		and _hud._box.size.is_equal_approx(cr.size))
	_check("内容盒不越安全区（右缘 %.0f ≤ %.0f，底缘 %.0f ≤ %.0f）" % [
		cr.end.x, vp.x - ins.z, cr.end.y, vp.y - ins.w],
		cr.end.x <= vp.x - ins.z and cr.end.y <= vp.y - ins.w)

	# 竖屏才有日志按钮；横屏成员为 null
	_check("竖屏存在「查看日志」按钮", _hud._btn_log != null)

	_shot("user://portrait.png")
	_click_vp(_hud._btn_log.get_global_rect().get_center())
	_wait = 5
	_step = 1

# ---------- 第 1 步：弹窗断言 + 截图 + Esc ----------
func _step1() -> void:
	_check("点击后日志弹窗 visible", _hud._log_dlg != null and _hud._log_dlg.visible)
	_check("日志非空（%d 行）" % _hud._log.get_line_count(), _hud._log.get_line_count() > 0)
	_shot("user://portrait_log.png")
	_press_esc()
	_wait = 3
	_step = 2

# ---------- 第 2 步：竖屏点信息区也能关图例 ----------
func _step2() -> void:
	_check("Esc 关掉日志弹窗", not _hud._log_dlg.visible)

	# 图例开着时点下方信息区的空白（底色 ColorRect 的地盘）——
	# 那里点击会被 GUI STOP 掉，只有 BoardView._input 看得见，断言它确实关了。
	var vp: Vector2 = root.get_visible_rect().size
	var pr := Layout.panel_rect(vp, SafeArea.insets())
	_bv.legend_open = true
	_bv.redraw()
	_click_vp(pr.position + Vector2(6.0, 6.0))
	_check("竖屏点信息区空白关掉图例（legend_open=%s）" % _bv.legend_open,
		not _bv.legend_open)

	_wait = 3
	_step = 3

# ---------- 第 3 步：收尾 ----------
func _step3() -> void:
	_step = 4          # 先置位：quit() 要等本帧结束，不然会重复跑
	SafeArea.set_override(null)
	print("通过 %d · 失败 %d" % [_ok_count, _fails])
	print("竖屏分区渲染验证：%s" % ("PASS" if _fails == 0 else "FAIL"))
	quit(0 if _fails == 0 else 1)

var _ok_count := 0

func _check(what: String, ok: bool) -> void:
	if ok:
		_ok_count += 1
		print("  [ok]   %s" % what)
	else:
		_fails += 1
		print("  [FAIL] %s" % what)

## 发一次真实左键点击。trap 3：push_input 的坐标按**窗口**坐标解释再乘视口倍率，
## 而 get_global_rect 给的是视口坐标 —— 必须乘 窗口/视口 换算，否则点偏。
## （本机 --resolution 720x1280 实际窗口 720×1061 → vp 868×1280，倍率 0.83。）
func _click_vp(vp_pos: Vector2) -> void:
	var win_sz := DisplayServer.window_get_size()
	var vp_sz: Vector2 = root.get_visible_rect().size
	var pos := vp_pos * (Vector2(win_sz) / vp_sz)   # trap 3：推送坐标按窗口坐标解释
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	root.push_input(ev)
	# Button.pressed 要"按下 + 抬起"成对才发信号（shot_help 点的是 Node2D，
	# 只吃 pressed，所以没有 release；这里必须补一个同位置抬起）
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	root.push_input(up)

func _press_esc() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	root.push_input(ev)

func _shot(path: String) -> void:
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("截图 -> %s" % ProjectSettings.globalize_path(path))

func _find_board(n: Node) -> BoardView:
	if n is BoardView:
		return n
	for c in n.get_children():
		var r := _find_board(c)
		if r != null:
			return r
	return null

func _find_hud(n: Node) -> HUD:
	if n is HUD:
		return n
	for c in n.get_children():
		var r := _find_hud(c)
		if r != null:
			return r
	return null
