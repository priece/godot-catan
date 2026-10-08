extends SceneTree

## 一次性探针：确认 beginner=true 时不同种子是否真的生成不同棋盘。
## （board.gd 的注释说"新手局每局完全一致"，需要用实测确认它是死注释还是真约束。）

func _initialize() -> void:
	for beginner in [true, false]:
		print("=== beginner=%s ===" % beginner)
		var sigs := {}
		for s in [1, 2, 3, 7, 1000, 20261005]:
			var b := Board.generate(s, beginner)
			var sig := "%s|%s|%s" % [
				",".join(b.hex_terrain.map(func(x): return str(x))),
				",".join(b.hex_number.map(func(x): return str(x))),
				str(b.port_edges)]
			var same_as_first: bool = sig == String(sigs.get("first", ""))
			print("  seed %-9d 指纹 %s" % [s, sig.substr(0, 42) + "…"])
			if not sigs.has("first"):
				sigs["first"] = sig
			print("     与 seed1 相同? %s" % same_as_first)
		# 同种子重复生成必须完全一致（可复现是硬要求）
		var a := Board.generate(4242, beginner)
		var c := Board.generate(4242, beginner)
		print("  同种子可复现: %s" % (a.hex_number == c.hex_number and a.hex_terrain == c.hex_terrain))
	quit(0)