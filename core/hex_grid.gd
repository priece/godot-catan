class_name HexGrid
extends RefCounted

## 卡坦岛六边形棋盘的几何工具。
##
## 坐标系统：axial 坐标 (q, r)，六边形为 pointy-top（上下为尖角、左右为平边）。
## 选 pointy-top 是为了让棋盘呈现经典卡坦岛的横排布局 3-4-5-4-3。
##
## 拓扑不手写邻接表，而是"算出所有顶点像素坐标 → 按坐标取整合并"
## 得到共享的顶点/边。这样 19/54/72 的共享关系由几何自动保证，不会抄错。
## 注：顶点/边的数量与度数分布是拓扑属性，与 pointy/flat 取向无关。

const BOARD_RADIUS := 2           ## 半径 2 的六边形 = 19 个地块
const HEX_SIZE := 1.0             ## 逻辑尺寸，只影响坐标绝对值，不影响拓扑
const MERGE_SCALE := 1000.0       ## 顶点合并精度：像素 * 1000 后取整作 key

## 6 个相邻方向（axial，与取向无关）
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

## 生成半径 2 范围内的全部地块坐标，共 19 个，横排分布为 3-4-5-4-3
static func generate_hex_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		for r in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
			if abs(q + r) <= BOARD_RADIUS:
				out.append(Vector2i(q, r))
	return out

## axial -> 像素中心（pointy-top 布局）
static func hex_to_pixel(h: Vector2i, size: float = HEX_SIZE) -> Vector2:
	var x := size * sqrt(3.0) * (float(h.x) + float(h.y) * 0.5)
	var y := size * 1.5 * float(h.y)
	return Vector2(x, y)

## 第 i 个角相对中心的偏移（i = 0..5，pointy-top 从 30° 起每 60° 一个）
static func hex_corner_offset(i: int, size: float = HEX_SIZE) -> Vector2:
	var ang := deg_to_rad(60.0 * float(i) + 30.0)
	return Vector2(size * cos(ang), size * sin(ang))

## 第 i 个角的绝对像素坐标
static func hex_corner_pixel(h: Vector2i, i: int, size: float = HEX_SIZE) -> Vector2:
	return hex_to_pixel(h, size) + hex_corner_offset(i, size)

## 把像素坐标量化成整数 key，用于顶点合并
static func pixel_key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * MERGE_SCALE), roundi(p.y * MERGE_SCALE))

## 两个地块是否相邻
static func are_hex_neighbors(a: Vector2i, b: Vector2i) -> bool:
	return (b - a) in DIRS
