extends SceneTree

## 显示环境探针（plan-2026.10.11.b §5 P0）。
## 打印视口 / 内容缩放 / 窗口 / DPI / 安全区 —— 量了再定，别照抄网上结论。
## 三种跑法（含义各不相同，别混着看）：
##   1) headless（确认 headless 路径安全，SafeArea 应当全 0）：
##      Godot --headless --path . --script res://tools/probe_display.gd
##   2) 默认横窗口（桌面基线）：
##      Godot --path . --script res://tools/probe_display.gd
##   3) 竖窗口（竖屏判定的依据，AGENTS.md trap 3：--resolution 改窗口不改视口，
##      本探针就是用来量化这条的 —— 打印"窗口物理尺寸 vs 视口逻辑尺寸"两个数）：
##      Godot --path . --resolution 720x1280 --script res://tools/probe_display.gd
## 真机：print 走 logcat / 控制台，输出后 adb logcat -s godot 过滤即可。

func _initialize() -> void:
	# ⚠️ 实测（P0，Mac14,3 / 4.7.2）：_initialize 时窗口创建流程尚未完成——
	# 此时 root 的视口还是初始的 1280×1280（与窗口 1280×720 对不上，换算倍率 0.5625）。
	# 等一帧 process_frame 后视口才与 content_scale 对齐。探针必须等，别在 _initialize
	# 里直接采信任何视口值。
	await process_frame
	var ds_name := DisplayServer.get_name()
	var headless := ds_name == "headless"
	var win := root

	print("== 显示环境探针 ==")
	print("[平台]   DisplayServer=%s   mobile=%s   型号=%s" % [
		ds_name, OS.has_feature("mobile"), OS.get_model_name()])

	# 工程缩放配置（竖屏改造的关键三件套 + 两项本次新增）
	var stretch := str(ProjectSettings.get_setting("display/window/stretch/mode", "（未设置）"))
	var aspect := str(ProjectSettings.get_setting("display/window/stretch/aspect", "（未设置）"))
	var base_w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var base_h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	var orient: int = ProjectSettings.get_setting("display/window/handheld/orientation", 0)
	var fps: int = ProjectSettings.get_setting("application/run/max_fps", 0)
	print("[工程]   stretch=%s aspect=%s   设计基准=%d×%d" % [stretch, aspect, base_w, base_h])
	print("[工程]   handheld/orientation=%d（0=横 1=竖）   run/max_fps=%d（0=不限）" % [orient, fps])

	# 窗口（物理像素）与视口（逻辑像素）。两者在 canvas_items+expand 下不相等，
	# 相差的就是内容缩放 —— trap 3 的全部内容就是这一行换算。
	var win_sz: Vector2i = DisplayServer.window_get_size()
	var vp := win.get_visible_rect().size
	var css: Vector2i = win.content_scale_size
	var csf: float = win.content_scale_factor
	print("[窗口]   物理=%d×%d   视口逻辑=%.0f×%.0f" % [win_sz.x, win_sz.y, vp.x, vp.y])
	print("[缩放]   content_scale_size=%d×%d   content_scale_factor=%.3f" % [css.x, css.y, csf])

	# 从"物理窗口"反推的内容缩放（expand 下取短边对齐），与上面的官方值互为印证。
	if win_sz.x > 0 and win_sz.y > 0 and css.x > 0 and css.y > 0:
		var implied := minf(float(win_sz.x) / css.x, float(win_sz.y) / css.y)
		var vp_from_impl := Vector2(win_sz) / implied
		print("[缩放]   短边对齐推算 factor=%.4f -> 隐含视口=%.0f×%.0f" % [implied, vp_from_impl.x, vp_from_impl.y])
		print("[推论]   窗口宽/设计宽=%.3f  窗口高/设计高=%.3f  -> 竖屏判定(vp.x<vp.y)=%s" % [
			float(win_sz.x) / base_w, float(win_sz.y) / base_h, vp.x < vp.y])

	if headless:
		print("[安全区] headless 下无屏幕边角可言， insets 应当全 0（SafeArea 自带跳过）")
	else:
		var dpi: int = DisplayServer.screen_get_dpi()
		var sc_scale: float = DisplayServer.screen_get_scale()
		var safe := DisplayServer.get_display_safe_area()
		print("[屏幕]   dpi=%d   screen_scale=%.3f" % [dpi, sc_scale])

	# SafeArea：竖屏布局的输入之一（桌面全 0，真机有值）
	var ins := SafeArea.insets()
	print("[安全区] SafeArea.insets=(左%.0f, 上%.0f, 右%.0f, 下%.0f)" % [ins.x, ins.y, ins.z, ins.w])

	# 换算检查：视口坐标 -> 窗口物理坐标的倍率（合成鼠标事件点位换算就用它）
	if win_sz.x > 0 and vp.x > 0:
		print("[换算]   视口->窗口倍率 = %.4f × %.4f（trap 3：涉鼠标测试必须窗口=基准，否则点偏）" % [
			float(win_sz.x) / vp.x, float(win_sz.y) / vp.y])

	print("== 探针结束 ==")
	quit(0)
