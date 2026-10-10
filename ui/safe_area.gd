class_name SafeArea
extends RefCounted

## 手机端"安全区"（屏幕圆角 / 刘海 / 挖孔摄像头）的统一算法。
##
## 为什么不写几个常数了事：各机型挖孔的位置和尺寸都不一样（有的在左、
## 有的在右、有的居中），圆角半径也不同。写死常数只能瞎猜一个"够大"的值，
## 白白浪费屏幕；而 DisplayServer 上报的是**本机真实**的可交互区域。
##
## 返回值统一是 Vector4：**x = 左, y = 上, z = 右, w = 下**，单位是
## **视口逻辑像素**（与 get_viewport_rect().size 同一坐标系），调用方直接相减。
##
## ⚠️ 桌面端实测安全区 = 整块屏幕，算出来四条边全是 0 —— 所以 1280×720 下的
## 布局与"加这个模块之前"**逐像素一致**（`tools/test_safe_area.gd` 把这条钉死）。
## 最小边距 MIN_* 只在 mobile 平台生效：桌面不吃，免得白白把布局挤歪。

## 最小让位。圆角属于"视觉建议"而非硬遮挡，不少设备也不上报，给一层兜底。
const MIN_X := 18.0
const MIN_Y := 10.0
## 上限。上报异常时（比如窗口被拖到屏幕外）不能把布局挤垮。
const MAX_X := 80.0
const MAX_Y := 56.0

## 手动注入的安全区，null = 用真实值。**只为预览用**：
## 安全区分支（挖孔避让）在桌面上永远走不到，等于"只能上真机才发现对不对"。
## 把它注入成一组手机横屏的值，就能在开发机上直接看布局（见 tools/shot_help.gd）。
static var _override = null

static func set_override(v) -> void:
	_override = v

static func insets() -> Vector4:
	if _override != null:
		return _override

	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0

	# headless / 无窗口的场合没有"屏幕边角"可言，直接跳过
	if DisplayServer.get_name() != "headless":
		var win := DisplayServer.window_get_size()
		var safe := DisplayServer.get_display_safe_area()
		if win.x > 0 and win.y > 0 and safe.size.x > 0 and safe.size.y > 0:
			var wp := DisplayServer.window_get_position()
			# 窗口四条边分别被安全区切掉多少（屏幕像素）。
			# 窗口整个落在安全区内时这四个值都是负的，下面 maxf 自然丢掉。
			var k := _viewport_scale(win)
			l = maxf(l, float(safe.position.x - wp.x) * k.x)
			t = maxf(t, float(safe.position.y - wp.y) * k.y)
			r = maxf(r, float(wp.x + win.x - safe.position.x - safe.size.x) * k.x)
			b = maxf(b, float(wp.y + win.y - safe.position.y - safe.size.y) * k.y)

	if OS.has_feature("mobile"):
		l = maxf(l, MIN_X)
		t = maxf(t, MIN_Y)
		r = maxf(r, MIN_X)
		b = maxf(b, MIN_Y)

	return Vector4(
		clampf(l, 0.0, MAX_X), clampf(t, 0.0, MAX_Y),
		clampf(r, 0.0, MAX_X), clampf(b, 0.0, MAX_Y))

## 视口逻辑像素 / 窗口像素。
## stretch=canvas_items 时两者并不相等（1280 设计稿放大到 1600 宽的窗口），
## 而安全区上报的是屏幕像素，必须乘这个比例才能拿去减视口坐标。
static func _viewport_scale(win: Vector2i) -> Vector2:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var vp: Vector2 = (loop as SceneTree).root.get_visible_rect().size
		if vp.x > 0.0 and vp.y > 0.0:
			return Vector2(vp.x / float(win.x), vp.y / float(win.y))
	return Vector2.ONE
