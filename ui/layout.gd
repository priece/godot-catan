class_name Layout
extends RefCounted

## 竖屏布局算式 + 朝向锁定（plan-2026.10.15.a §4.1）。
##
## 为什么单开一个类：竖屏「上棋盘 / 下信息区」的分区算式如果散落在
## BoardView / HUD 里，横屏那三条既有算式（桌面 1280×720 逐像素基线）
## 就得跟着搬家，回归面白扩大一倍。所以这里只装**竖屏分支**的算式与常数，
## 横屏算式原地不动（BoardView.board_origin_for / HUD.content_rect /
## HUD._apply_layout 的横屏路径逐字节保留），两个入口各加一个三元分支。
##
## 朝向是**启动时锁一次**的（BoardView._ready 里按窗口物理尺寸判定，
## 见 is_portrait_for_window 的注释），运行中不随转屏变 —— P0 已把
## handheld/orientation 锁成竖屏。测试用 set_portrait 注入（同 SafeArea.set_override）。

static var _portrait := false

static func set_portrait(v: bool) -> void:
	_portrait = v

static func is_portrait() -> bool:
	return _portrait

## 纯函数：窗口物理尺寸判竖屏。headless 是 0×0 → false；
## (1280,720)→false；(720,1280)/(1080,2400)/(1536,2048)→true。
## 注意读的是**窗口**不是视口：_ready 那刻视口还没和基准对齐（P0 探针实测）。
static func is_portrait_for_window(win: Vector2i) -> bool:
	return win.x > 0 and win.x < win.y

## 启动时一次性写入 Window.content_scale_size 的基准（D5：先比现值，不同才写）。
static func content_scale_for(portrait: bool) -> Vector2i:
	return Vector2i(720, 1280) if portrait else Vector2i(1280, 720)

## 棋盘外接尺寸（世界单位）：19 格外接矩形 + 海岸带 + 港口牌外推（plan-b §3.1）。
const BOARD_W_U := 9.9003
const BOARD_H_U := 9.2400

const FIT := 0.98        ## 棋盘与外接框之间留 2% 呼吸空间
const PAD := 8.0         ## 棋盘区四周内边距（让开安全区后再收一圈）
const GAP := 12.0        ## 棋盘区与信息区之间的缝

## 信息区高度 = 视口高 × UI_RATIO，夹在 [UI_MIN, UI_MAX]。
## ⚠️ 三个数来自 plan-b 的估算，P2 出图后按"宁可比桌面大，不要比桌面小"校准（plan-a §6 Q4）。
const UI_RATIO := 0.48
const UI_MIN := 400.0
const UI_MAX := 940.0

static func ui_height(vp: Vector2) -> float:
	return clampf(vp.y * UI_RATIO, UI_MIN, UI_MAX)

## 竖屏棋盘区：视口扣掉安全区后，底部留出信息区 + 缝，其余全给棋盘。
static func board_rect(vp: Vector2, ins: Vector4) -> Rect2:
	var avail_y: float = vp.y - ins.y - ins.w
	var ui_h := ui_height(vp)
	return Rect2(ins.x + PAD, ins.y + PAD,
		vp.x - ins.x - ins.z - 2.0 * PAD,
		avail_y - ui_h - PAD - GAP)

## 竖屏每世界单位像素数：外接框等比缩放进棋盘区（D3：只在竖屏分支写回 px_per_unit）。
static func px_per_unit_for(bz: Rect2) -> float:
	return minf(bz.size.x / BOARD_W_U, bz.size.y / BOARD_H_U) * FIT

## 竖屏信息区：从棋盘区下缘 + 缝一直铺到屏底（底色到边，安全区只作用于内容）。
static func panel_rect(vp: Vector2, ins: Vector4) -> Rect2:
	var bz := board_rect(vp, ins)
	return Rect2(0, bz.end.y + GAP, vp.x, vp.y - bz.end.y - GAP)

## 竖屏信息区内容盒：左右让安全区 + 14，上下比底色区各收 10/（10 + 底部安全区）。
static func content_rect(vp: Vector2, ins: Vector4) -> Rect2:
	var panel := panel_rect(vp, ins)
	return Rect2(ins.x + 14.0, panel.position.y + 10.0,
		vp.x - ins.x - ins.z - 28.0, panel.size.y - 20.0 - ins.w)
