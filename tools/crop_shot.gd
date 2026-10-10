extends SceneTree

## 截图局部放大：把 PNG 的某一块矩形裁下来再整数倍放大。
## 用途只有一个 —— 棋盘 UI 里有大量 20px 上下的细节（港口牌、图例小字、顶点锚点），
## 整图看根本看不清，靠肉眼在缩略图上"感觉没问题"是自欺欺人。
##
## 用法：
##   Godot --headless --path . --script res://tools/crop_shot.gd -- \
##       /tmp/catan_board.png 185 210 135 265 3 /tmp/crop.png
##   参数：源图 / x / y / 宽 / 高 / 放大倍数 / 输出
##
## ⚠️ 别用 macOS 的 sips 裁：`sips -c` 只支持居中裁，
## 早先想用 `--cropOffset` 指定位置，实测参数被忽略、裁出来是图心，白折腾一轮。
## 纯粹是内存里的 Image 操作，**可以 headless**（不依赖 frame_post_draw）。

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 7:
		print("用法: -- 源图 x y 宽 高 放大倍数 输出")
		quit(1)
		return
	var src: Image = Image.load_from_file(a[0])
	if src == null:
		print("!! 读不到 %s" % a[0])
		quit(1)
		return
	var x := int(a[1]); var y := int(a[2])
	var w := int(a[3]); var h := int(a[4])
	var z := maxi(1, int(a[5]))
	var r := Rect2i(x, y, w, h).intersection(Rect2i(Vector2i.ZERO, src.get_size()))
	var img := src.get_region(r)
	# 用 NEAREST：放大后每个源像素是硬边方块，正好能看出"字是不是糊的 / 有没有压线"
	img.resize(w * z, h * z, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(a[6])
	print("OK 裁 %s ×%d -> %s（%s）" % [r, z, a[6], "失败" if err != OK else "成功"])
	quit(0)
