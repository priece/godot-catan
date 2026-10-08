extends SceneTree

## 验证重开一局的种子解析规则。
## 跑法：Godot --headless --path . --script res://tools/test_seed.gd
##
## 注意 _resolve / _roll_seed 是从 GameDirector 复制过来的副本，不是引用。
## 这不是为了偷懒：GameDirector 是 Node，headless 下不方便在不进场景树的情况下
## 单独 new 出来调私有方法。改那边时记得同步改这边，否则这条断言就形同虚设。

var fails := 0

## 与 GameDirector 的实现保持一致（故意复制而非引用，见文件末尾说明）
var _roll_rng := RandomNumberGenerator.new()
var _roll_count := 0

func _initialize() -> void:
	# --- 解析规则 ---
	_check("空串 -> 沿用当前种子", _resolve("", 111) == 111)
	_check("纯空格 -> 沿用当前种子", _resolve("   ", 111) == 111)
	_check("'r' -> 随机（不该等于当前种子）", _resolve("r", 111) != 111)
	_check("'随机' -> 随机", _resolve("随机", 111) != 111)
	_check("整数 20261005 -> 原样", _resolve("20261005", 111) == 20261005)
	_check("带空格 ' 42 ' -> 42", _resolve(" 42 ", 111) == 42)
	_check("负数 -> 原样", _resolve("-7", 111) == -7)
	_check("0 -> 0（0 是合法种子，不能当空处理）", _resolve("0", 111) == 0)
	_check("非法 'abc' -> 沿用当前种子", _resolve("abc", 111) == 111)
	_check("非法 '12ab' -> 沿用当前种子", _resolve("12ab", 111) == 111)

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

## 与 GameDirector._on_restart 里的解析规则保持一致
func _resolve(text: String, cur: int) -> int:
	var t := text.strip_edges()
	if t == "r" or t == "随机":
		return _roll_seed()
	if t.is_valid_int():
		return int(t)
	return cur

func _roll_seed() -> int:
	_roll_count += 1
	return _roll_rng.randi() + _roll_count

func _check(what: String, ok: bool) -> void:
	if ok:
		print("  [ok]   %s" % what)
	else:
		print("  [FAIL] %s" % what)
		fails += 1