extends SceneTree

## 验证「棋盘每局随机」这件事本身：
##   · 不同种子必须真的换一张地图、同种子必须可复现；
##   · 官方数字摆放规则（6/8 不相邻等）不因为随机而破；
##   · 连续取种子不能撞。
##
## 跑法：Godot --headless --path . --script res://tools/test_seed.gd
##
## ⚠️ 这里曾经还测过"种子输入框的文本怎么解析"（空串=沿用、'r'=随机…）。
## 那个功能已经**删除**了 —— 开局弹窗不再有种子输入框，种子由 GameDirector
## 每局自动滚动。别把解析规则又加回来（要复现某张图请用命令行 --seed=NNN）。
##
## 注意 _roll_seed 是从 GameDirector 复制过来的副本，不是引用。
## 这不是为了偷懒：GameDirector 是 Node，headless 下不方便在不进场景树的情况下
## 单独 new 出来调私有方法。改那边时记得同步改这边，否则这条断言就形同虚设。

var fails := 0

## 与 GameDirector 的实现保持一致（故意复制而非引用，见文件末尾说明）
var _roll_rng := RandomNumberGenerator.new()
var _roll_count := 0

func _initialize() -> void:
	# --- 不同种子必须真的换地图（这是本需求的核心）---
	var a := Board.generate(1, true)
	var b := Board.generate(2, true)
	_check("beginner 下换种子地形确实不同", a.hex_terrain != b.hex_terrain)
	_check("beginner 下换种子数字确实不同", a.hex_number != b.hex_number)
	_check("同种子可复现（地形）",
		Board.generate(777, true).hex_terrain == Board.generate(777, true).hex_terrain)

	# --- 官方数字摆放规则（Almanac：完全随机摆放时 6/8 不能相邻、相邻不能同数字）---
	# 6/8 相邻是任何模式都不允许的硬规则，多试些种子确保不是碰巧。
	var red_bad := 0
	var samenum_bad_beginner := 0
	var samenum_bad_random := 0
	for s in 200:
		var bg := Board.generate(3000 + s, true)
		var rd := Board.generate(3000 + s, false)
		if _red_clash(bg) > 0 or _red_clash(rd) > 0:
			red_bad += 1
		if _same_number_clash(bg) > 0:
			samenum_bad_beginner += 1
		if _same_number_clash(rd) > 0:
			samenum_bad_random += 1
	_check("200 种子 · 两种模式下 6/8 都从不相邻（违规 %d）" % red_bad, red_bad == 0)
	_check("均衡模式下相邻不同数字（违规 %d）" % samenum_bad_beginner, samenum_bad_beginner == 0)

	# 地形**没有**"同资源不相邻"这条官方限制：出现相邻同地形是正常的，不能当错误。
	# 这里反过来断言"确实会出现"，避免有人又把它当成 bug 加回去。
	var terr_clash := 0
	for s in 50:
		if _same_terrain_clash(Board.generate(4000 + s, true)) > 0:
			terr_clash += 1
	_check("地形相邻限制已被移除（50 局里有 %d 局存在相邻同地形，应 > 0）" % terr_clash,
		terr_clash > 0)

	# --- 随机种子不撞 ---
	var seen := {}
	for i in 20:
		seen[_roll_seed()] = true
	_check("连续 20 次随机种子几乎不重复（>18 个不同）", seen.size() >= 18)

	if fails == 0:
		print("种子重开测试：全部通过")
	quit(0)

## 相邻地块里的红色数字（6/8）对数
func _red_clash(b: Board) -> int:
	var v := 0
	for hi in b.topo.hexes.size():
		var num: int = b.hex_number[hi]
		if num != 6 and num != 8:
			continue
		for d in HexGrid.DIRS:
			var n: Vector2i = b.topo.hexes[hi] + d
			if not b.topo.hex_index.has(n):
				continue
			var o: int = b.hex_number[b.topo.hex_index[n]]
			if (num == 6 and o == 8) or (num == 8 and o == 6):
				v += 1
	return v / 2

## 相邻地块同数字的对数
func _same_number_clash(b: Board) -> int:
	var v := 0
	for hi in b.topo.hexes.size():
		var num: int = b.hex_number[hi]
		if num == 0:
			continue
		for d in HexGrid.DIRS:
			var n: Vector2i = b.topo.hexes[hi] + d
			if b.topo.hex_index.has(n) and b.hex_number[b.topo.hex_index[n]] == num:
				v += 1
	return v / 2

## 相邻地块同地形的对数（官方允许，仅用于反向断言）
func _same_terrain_clash(b: Board) -> int:
	var v := 0
	for hi in b.topo.hexes.size():
		var t: int = b.hex_terrain[hi]
		for d in HexGrid.DIRS:
			var n: Vector2i = b.topo.hexes[hi] + d
			if b.topo.hex_index.has(n) and b.hex_terrain[b.topo.hex_index[n]] == t:
				v += 1
	return v / 2

## 与 GameDirector._roll_seed 保持一致
func _roll_seed() -> int:
	_roll_count += 1
	return _roll_rng.randi() + _roll_count

func _check(what: String, ok: bool) -> void:
	if ok:
		print("  [ok]   %s" % what)
	else:
		print("  [FAIL] %s" % what)
		fails += 1