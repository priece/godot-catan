class_name UIPalette
extends RefCounted

## 界面与棋盘共用的配色，避免两边各写一份后跑偏。

## 四个玩家：蓝=你，红 / 橙 / 绿=电脑。
## 三种电脑色都刻意避开地形色：橙与田野(0.878,0.725,0.247)靠明度拉开，
## 绿比森林(0.247,0.478,0.310)更亮更偏冷，棋子自带深色描边，压得住。
const PLAYER := [
	Color(0.184, 0.435, 0.816),
	# 小红 = macOS systemRed 的 sRGB 值 #FF383C（就是 Dock 角标那个红）。
	# 别手调，手调出来的红一律偏暗偏土。试颜色值：
	#   cat > /tmp/c.swift <<'EOF'
	#   import AppKit
	#   print(NSColor.systemRed.usingColorSpace(.sRGB)!)
	#   EOF && swift /tmp/c.swift
	Color(1.0, 0.220, 0.235),
	Color(0.878, 0.545, 0.169),
	Color(0.118, 0.639, 0.353),
]

const PLAYER_NAMES := ["蓝方", "小红", "小橙", "小绿"]

## 资源短名，用于紧凑排版
const RES_SHORT := ["木", "砖", "羊", "麦", "矿"]

## 资源 bbcode 颜色（RichTextLabel 用，不能引用 const Color，只能用字符串）
const RES_HEX := ["#3f7a4f", "#b06a3b", "#8cc152", "#e0b93f", "#8a8f98"]

## 棋子/地块用的资源色
const RES_COLOR := [
	Color(0.247, 0.478, 0.310),
	Color(0.690, 0.416, 0.231),
	Color(0.549, 0.757, 0.322),
	Color(0.878, 0.725, 0.247),
	Color(0.541, 0.561, 0.596),
]

const INK := Color(0.11, 0.11, 0.11)
const MUTED := Color(0.44, 0.44, 0.44)
const WARN := Color(0.75, 0.22, 0.17)
const GOOD := Color(0.11, 0.55, 0.31)

static func player_color(pid: int) -> Color:
	return PLAYER[pid % PLAYER.size()]

static func player_name(pid: int) -> String:
	return PLAYER_NAMES[pid % PLAYER_NAMES.size()]
