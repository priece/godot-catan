class_name HUD
extends CanvasLayer

## 右侧玩家面板 + 操作区 + 日志（P5）。
##
## 全部用代码搭控件，不手写 .tscn：面板有大量随状态变化的按钮，
## 代码里动态增删比在场景文件里维护一堆节点更清楚。
##
## 设计上 HUD 是"哑"的：只负责显示状态、发信号，所有判断都在 GameDirector。

signal end_turn_pressed
signal buy_dev_pressed
## 打出发展卡。参数按卡片类型取用，不需要的填 -1：
##   · 垄断 MONOPOLY  → r = 指定的资源
##   · 丰收年 YEAR_OF_PLENTY → r1 / r2 = 拿的 2 张（可以相同）
##   · 骑士 / 修路    → 全 -1
signal play_dev_pressed(card: int, r: int, r1: int, r2: int)
signal bank_trade_pressed(give_r: int, take_r: int)
## 「掷骰子」按钮：只在回合开始的"掷骰前"窗口里有效
signal roll_dice_pressed
## 参数是种子输入框的文本："" = 沿用上一局，"r" = 随机，
## 其他字符串交给 GameDirector 解析（非法值它自己兜底）。
signal restart_pressed(seed_text: String)

const PANEL_X := 896.0
const PANEL_W := 384.0
const VIEW_H := 720.0

const DEV_LABEL := ["骑士", "胜利点", "修路", "丰收年", "垄断"]

## 选卡弹窗里的效果说明。玩家得先知道打出会发生什么，才谈得上选择。
const DEV_TIP := {
	Res.Dev.KNIGHT: "移动强盗到任意地块，封住该地产出，并从相邻的对手手里偷 1 张牌",
	Res.Dev.ROAD_BUILDING: "立刻免费放 2 条路（不消耗资源）",
	Res.Dev.YEAR_OF_PLENTY: "从银行拿走任意 2 张资源，可以拿 2 张相同的",
	Res.Dev.MONOPOLY: "指定 1 种资源，把所有对手手里的该资源全部收走",
}

## "重开一局"是破坏性操作（会丢掉当前进度），所以点开一个面板让玩家
## 看清要发生什么、顺便选种子，替代原来"点两下"的裸确认。
var _dlg: Control
var _seed_edit: LineEdit
var _seed_hint: Label
var _cur_seed := 0                  ## GameDirector 每局开始时告知的当前种子

var _row_chips: Array = []      ## 每行：颜色块
var _row_names: Array = []      ## 每行：名字标签
var _row_vps: Array = []        ## 每行：分数标签
var _row_res: Array = []        ## 每行：资源 RichTextLabel
var _row_frames: Array = []     ## 每行：外框样式（用于高亮当前玩家）
var _row_nodes: Array = []      ## 每行：外框节点（用于挂 tooltip）

var _status: Label
var _dice: Label
var _btn_end: Button
var _btn_buy: Button
var _btn_restart: Button
## 「掷骰子」/「打发展卡」：回合开始的掷骰前窗口里才有掷骰子，
## 打发展卡则掷骰前后都能点（官方规则允许骑士等卡在掷骰前打出）。
var _btn_roll: Button
var _btn_play: Button
var _act_row: HBoxContainer    ## 结束回合 / 买发展卡 / 兑换 —— 掷骰前整行隐藏
## 银行兑换弹窗（替代原来那排"点一下即换"的按钮）：
## 左列 = 可付出的资源（带当前比例 4/3/2），右列 = 换回的资源，
## 两侧都能点选高亮，底部 确定/取消。
var _btn_trade: Button
var _trade_dlg: Control
var _trade_card: PanelContainer
var _trade_give_box: VBoxContainer
var _trade_take_box: VBoxContainer
var _trade_hint: Label
var _trade_ok: Button
var _trade_give_btns: Array = []   ## 左列按钮，下标 = 资源 id
var _trade_take_btns: Array = []   ## 右列按钮，下标 = 资源 id
var _give_sel := -1                ## 左列当前选中（-1 = 未选）
var _take_sel := -1                ## 右列当前选中（-1 = 未选）
var _st: GameState                 ## refresh() 时留存的最新局面，开弹窗时用
var _can_act := false

## 发展卡弹窗（三级）：
##   _dev_dlg  选卡 → 骑士/修路直接打出，垄断/丰收再开二级弹窗选资源
##   _mono_dlg 垄断：单列 5 项，显示对手合计 ×N
##   _yop_dlg  丰收：左右两列各 5 项，允许选同一种
var _dev_dlg: Control
var _dev_card: PanelContainer
var _dev_box: VBoxContainer
var _mono_dlg: Control
var _mono_card: PanelContainer
var _mono_box: VBoxContainer
var _mono_hint: Label
var _mono_ok: Button
var _mono_btns: Array = []
var _mono_sel := -1
var _yop_dlg: Control
var _yop_card: PanelContainer
var _yop_left: VBoxContainer
var _yop_right: VBoxContainer
var _yop_hint: Label
var _yop_ok: Button
var _yop_btns: Array = []      ## 两列各 5 个：_yop_btns[0][r] / _yop_btns[1][r]
var _yop_sel: Array = [-1, -1]

var _log_title: Label
var _log: RichTextLabel

var _trade_sig := ""
var _dev_sig := ""

func _ready() -> void:
	_build()
	_build_trade_dialog()
	# 三个发展卡弹窗按"层级从下到上"的顺序建：后加的子节点盖在前面之上，
	# 所以二级弹窗（垄断/丰收）要建在选卡弹窗之后。
	_build_dev_dialogs()
	# 卡片高度依赖说明文字换行后的实际排版，得等一帧布局完再居中
	await _build_dialog()

## 重开面板：显示当前种子，可以手打一个新种子，也可以点两个快捷方式。
## 用 LineEdit 而非 SpinBox：种子就是个 9 位整数，用不着加减按钮，
## 而且键盘直接打字比点箭头快得多。
##
## 按钮分两层，别搞混：
##   · 「随机一局」「沿用本局」是**快捷方式**，点了立刻重开（会用它们的值覆盖输入框）；
##   · 「确定」是**主操作**，提交输入框里手打的种子。
## 之前只有前者、没有后者，导致手打的种子无处提交（看 _submit_seed 的注释）。
func _build_dialog() -> void:
	_dlg = Control.new()
	_dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dlg.visible = false
	# 关掉时不能把点击吞掉——它只是浮层，底下该还能点棋盘。
	_dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dlg)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.34)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_dlg.add_child(shade)

	# 遮罩是全屏的，卡片就得跟着整个视口居中，而不是按 PANEL_X 算——
	# 否则它会以右侧信息栏为中心，看着像偏了半边屏幕。
	#
	# 两个踩过的坑，记一下免得下次又绕回去：
	#   1. CenterContainer 会把子节点压到"能放下的最小尺寸"，
	#      表现是标题还在、输入框和按钮被挤没（PanelContainer 没有
	#      SIZE_SHRINK_CENTER 那种语义给它用）。
	#   2. anchor=0.5 + grow_offsets 也不行：父节点是普通 Control，
	#      没有布局给它跑，position 停在 anchor 点上不往回挪。
	# 所以就是老老实实按视口尺寸算左上角。
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(320, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_dlg.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)

	box.add_child(_label("重开一局", 15, UIPalette.INK, true))

	_seed_hint = _label("", 11, UIPalette.MUTED, false)
	_seed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seed_hint.custom_minimum_size = Vector2(280, 0)
	box.add_child(_seed_hint)

	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "留空 = 沿用上一局棋盘"
	_seed_edit.max_length = 12
	_seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Godot 默认主题是暗色的，LineEdit 不覆盖样式就会在白卡片上出现
	# 一条深灰输入框 + 深色提示字，几乎看不见。
	_seed_edit.add_theme_stylebox_override("normal", _input_style())
	_seed_edit.add_theme_stylebox_override("focus", _input_style(true))
	# ⚠️ 是 add_theme_color_override，不是 add_theme_font_color_override。
	# 后者在 Godot 4 里根本不存在，写了不会报编译错、只在运行时喷一行
	# SCRIPT ERROR 然后静默跳过 —— 表现就是种子输入框的字还是默认近白色，
	# 打在白卡片上几乎看不见。别照抄 Godot 3 的 add_color_override。
	_seed_edit.add_theme_color_override("font_color", UIPalette.INK)
	_seed_edit.add_theme_color_override("font_uneditable_color", UIPalette.INK)
	_seed_edit.add_theme_color_override("font_placeholder_color", Color(0.62, 0.61, 0.59))
	_seed_edit.add_theme_color_override("caret_color", UIPalette.INK)
	_seed_edit.add_theme_constant_override("minimum_character_width", 6)
	_seed_edit.text_changed.connect(_on_seed_text_changed)
	# 回车 = 确定。不接这个玩家会以为"打完了按回车没反应 = 输入框坏了"。
	_seed_edit.text_submitted.connect(func(_t: String): _fire_restart())
	box.add_child(_seed_edit)

	# 两个快捷方式放在输入框下面。它们先填内容再提交，
	# 保证"输入框里显示的"永远等于"实际用的种子"。
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	box.add_child(quick)

	var rnd := _button("随机一局")
	rnd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rnd.tooltip_text = "换一个随机种子，生成全新地图"
	rnd.pressed.connect(func(): _submit_seed("r"))
	quick.add_child(rnd)

	var keep := _button("沿用本局")
	keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keep.tooltip_text = "同一张棋盘重开，方便复盘刚才的局面"
	keep.pressed.connect(func(): _submit_seed(""))
	quick.add_child(keep)

	# 主操作行：取消 + 确定。
	# ⚠️ 「确定」不能省。以前只有"随机一局 / 沿用本局"两个按钮，
	# 而它们都会先覆盖输入框（填 "r" / 清空）再重开 ——
	# 于是玩家手打的种子**没有任何按钮能提交它**，表现就是
	# "输入框能打字，但输什么都白输"，看起来像输入框坏了。
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var cancel := _button("取消")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close_dialog)
	row.add_child(cancel)

	var ok := _button("确定", true)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.tooltip_text = "用输入框里的种子重开（留空 = 沿用本局）"
	ok.pressed.connect(_fire_restart)
	row.add_child(ok)

	# 内容都挂完了，这时才知道真实高度（说明文字会换行，事先算不准）。
	# 放在 add_child 之后读 size、算居中位置 —— 排版完成前读到的是 0。
	await get_tree().process_frame
	_center_card(card)

func _center_card(card: Control, width: float = 320.0) -> void:
	var vp := get_viewport().get_visible_rect().size
	# 隐藏状态下 card.size 不可靠，用 combined minimum 兜底（内容高度事先算不准）
	var h: float = maxf(maxf(card.size.y, card.get_combined_minimum_size().y), 150.0)
	card.size = Vector2(width, h)
	card.position = ((vp - card.size) * 0.5).round()

func _input_style(focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.97)
	sb.border_color = Color(0.62, 0.71, 0.80) if focused else Color(0.82, 0.81, 0.78)
	sb.set_border_width_all(2 if focused else 1)
	sb.set_corner_radius_all(7)
	return sb

## 卡片样式。pad 是内容到边框的内边距 ——
## ⚠️ StyleBoxFlat 的 content_margin 默认是 0，不显式设就会让内容直接贴着
## 边框（看着像没做排版）。两个弹窗共用这一份，保证内边距一致。
func _card_style(pad: float = 16.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.border_color = Color(0.86, 0.85, 0.82)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.20)
	sb.shadow_size = 14
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

## 种子只可能是数字，所以直接把非数字字符挡在输入框外。
## 比"允许输入再标红报错"更省事：玩家根本打不出非法种子，
## 也就不存在"点了确定才发现没生效"的挫败感。
##
## ⚠️ 在 text_changed 里改 text 会再次触发 text_changed，必须用
## _sanitizing 挡住递归，否则死循环。
var _sanitizing := false

func _on_seed_text_changed(t: String) -> void:
	if _sanitizing:
		return
	var clean := ""
	for i in t.length():
		if t[i].is_valid_int():
			clean += t[i]
	if clean == t:
		return
	_sanitizing = true
	# 光标位置按"删掉了几个字符"往回补，别让它跳到末尾（中途改字会很难受）
	_seed_edit.text = clean
	_seed_edit.caret_column = mini(_seed_edit.caret_column, clean.length())
	_sanitizing = false

## 快捷按钮：先把种子写进输入框，再提交。
## 这样"输入框里是什么"和"实际用了什么种子"永远一致 ——
## 玩家不会出现"手打了数字，点个按钮却被悄悄覆盖掉"的情况。
func _submit_seed(t: String) -> void:
	_seed_edit.text = t
	_fire_restart()

## 点"重开一局"时由 GameDirector 告知当前种子，显示出来方便玩家照着换
func show_dialog(cur_seed: int) -> void:
	_seed_hint.text = "当前棋盘种子 %d。改个数字就换一张地图；" % cur_seed \
		+ "留空（或点「沿用本局」）则用同一个种子重开。事件日志会保留。"
	# 预填当前种子 + 全选：想换图就改一位数字（全选后直接打会把整串替换掉），
	# 想重打就全选后直接输入。空着让玩家从零敲 9 位数字纯属折磨。
	_seed_edit.text = str(cur_seed)
	_dlg.visible = true
	# 每次打开都重算一次：分辨率被改过、或窗口尺寸变了，居中位置会过期
	_center_card(_dlg.get_child(1) as Control)
	# 打开就聚焦并全选：玩家多半是想直接改数字
	_seed_edit.grab_focus()
	_seed_edit.select_all()

func close_dialog() -> void:
	_dlg.visible = false

func _fire_restart() -> void:
	var t := _seed_edit.text.strip_edges()
	close_dialog()
	restart_pressed.emit(t)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _dlg.visible:
		if event.keycode == KEY_ESCAPE:
			# Esc 关掉浮层，别让玩家以为游戏卡住了
			close_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# 输入框有焦点时回车走 LineEdit.text_submitted，这里兜住
			# "焦点跑到别处（比如点了快捷按钮）后按回车"的情况。
			_fire_restart()
			get_viewport().set_input_as_handled()
	elif _yop_dlg != null and _yop_dlg.visible:
		# 弹窗可能叠着开（选卡 → 丰收），Esc 只关最上面那层，底下的选卡弹窗留着
		if event.keycode == KEY_ESCAPE:
			close_yop_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm_yop()
			get_viewport().set_input_as_handled()
	elif _mono_dlg != null and _mono_dlg.visible:
		if event.keycode == KEY_ESCAPE:
			close_mono_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm_mono()
			get_viewport().set_input_as_handled()
	elif _dev_dlg != null and _dev_dlg.visible:
		if event.keycode == KEY_ESCAPE:
			close_dev_dialog()
			get_viewport().set_input_as_handled()
	elif _trade_dlg != null and _trade_dlg.visible:
		if event.keycode == KEY_ESCAPE:
			close_trade_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm_trade()
			get_viewport().set_input_as_handled()

## 新开一局时清掉各种"增量刷新"的缓存，否则新旧界面的按钮可能对不上
func on_new_game(cur_seed: int) -> void:
	_trade_sig = ""
	_dev_sig = ""
	_log_count = -1
	_log_last = ""
	_cur_seed = cur_seed
	close_dialog()
	close_trade_dialog()
	close_dev_dialog()
	close_mono_dialog()
	close_yop_dialog()

# ================= 构建 =================

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.965, 0.961, 0.953)
	bg.position = Vector2(PANEL_X, 0)
	bg.size = Vector2(PANEL_W, VIEW_H)
	add_child(bg)

	var sep := ColorRect.new()
	sep.color = Color(0.78, 0.77, 0.74)
	sep.position = Vector2(PANEL_X, 0)
	sep.size = Vector2(1.5, VIEW_H)
	add_child(sep)

	var box := VBoxContainer.new()
	box.position = Vector2(PANEL_X + 14, 12)
	box.size = Vector2(PANEL_W - 28, VIEW_H - 24)
	box.add_theme_constant_override("separation", 7)
	add_child(box)

	# 标题行：左边标题，右边"重开一局"。放标题行是为了不占日志的竖向空间。
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	box.add_child(title_row)

	var title := _label("卡坦岛 · 人机对战", 15, UIPalette.INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_btn_restart = _button("重开一局")
	_btn_restart.add_theme_font_size_override("font_size", 12)
	_btn_restart.tooltip_text = "放弃当前这局，重新开始（会保留之前的日志）"
	_btn_restart.pressed.connect(func(): show_dialog(_cur_seed))
	title_row.add_child(_btn_restart)

	for pid in 4:
		box.add_child(_make_player_row(pid))

	_status = _label("", 13, UIPalette.INK, true)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 36)
	box.add_child(_status)

	_dice = _label("", 13, UIPalette.MUTED, true)
	box.add_child(_dice)

	# 掷骰行：「掷骰子」只在掷骰前的窗口里出现（其余状态隐藏，避免误点），
	# 「打发展卡」掷骰前后都能用，所以留在这行里。
	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", 8)
	box.add_child(roll_row)
	_btn_roll = _button("掷骰子", true)
	_btn_roll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_roll.tooltip_text = "掷两颗骰子，结算本回合产出"
	_btn_roll.pressed.connect(func(): roll_dice_pressed.emit())
	roll_row.add_child(_btn_roll)
	_btn_play = _button("打发展卡")
	_btn_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_play.tooltip_text = "打出 1 张发展卡：掷骰前、掷骰后都可以，每回合限 1 张"
	_btn_play.pressed.connect(show_dev_dialog)
	roll_row.add_child(_btn_play)

	# 主阶段的操作行。掷骰前整行隐藏 —— 那时不能建造、不能交易、不能结束回合。
	_act_row = HBoxContainer.new()
	_act_row.add_theme_constant_override("separation", 8)
	box.add_child(_act_row)
	_btn_end = _button("结束回合")
	_btn_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_end.pressed.connect(func(): end_turn_pressed.emit())
	_act_row.add_child(_btn_end)
	_btn_buy = _button("买发展卡")
	_btn_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_buy.pressed.connect(func(): buy_dev_pressed.emit())
	_act_row.add_child(_btn_buy)
	_btn_trade = _button("兑换")
	_btn_trade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_trade.tooltip_text = "与银行兑换资源：4:1，任意型港口 3:1，特定型港口 2:1"
	_btn_trade.pressed.connect(show_trade_dialog)
	_act_row.add_child(_btn_trade)

	_log_title = _label("事件日志", 12, UIPalette.MUTED, true)
	box.add_child(_log_title)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	# 不做自动跟随：玩家往上翻看历史时，新事件不应该把他拽回底部。
	# 只有当他本来就停在底部时才自动滚到最新（见 set_log）。
	_log.scroll_following = false
	_log.scroll_active = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 150)
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_color_override("default_color", UIPalette.INK)
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(1, 1, 1)
	lsb.border_color = Color(0.86, 0.85, 0.82)
	lsb.set_border_width_all(1)
	lsb.set_corner_radius_all(6)
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lsb.content_margin_top = 6
	lsb.content_margin_bottom = 6
	_log.add_theme_stylebox_override("normal", lsb)
	box.add_child(_log)

func _make_player_row(pid: int) -> Control:
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.border_color = Color(0.87, 0.86, 0.83)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	frame.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 7)
	frame.add_child(h)

	var chip := ColorRect.new()
	chip.color = UIPalette.player_color(pid)
	chip.custom_minimum_size = Vector2(9, 16)
	h.add_child(chip)

	var nm := _label("", 13, UIPalette.INK, true)
	nm.custom_minimum_size = Vector2(52, 0)
	h.add_child(nm)

	var vp := _label("", 13, UIPalette.INK, true)
	vp.custom_minimum_size = Vector2(46, 0)
	h.add_child(vp)

	var res := RichTextLabel.new()
	res.bbcode_enabled = true
	res.fit_content = true
	res.scroll_active = false
	res.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res.add_theme_font_size_override("normal_font_size", 12)
	res.add_theme_color_override("default_color", UIPalette.INK)
	h.add_child(res)

	_row_chips.append(chip)
	_row_names.append(nm)
	_row_vps.append(vp)
	_row_res.append(res)
	_row_frames.append(sb)
	_row_nodes.append(frame)
	return frame

# ================= 刷新 =================

## status: 当前该干嘛（玩家看得懂的提示）
## can_act: 人类玩家现在能否操作（含布置、放强盗这些"能点棋盘"的时刻）
## main_phase: 是否已掷过骰、能建造 / 交易 / 结束回合
## preroll: 正处在回合开始的掷骰前窗口
##
## ⚠️ can_act 和 main_phase 必须分开：掷骰前玩家"能操作"（可以打发展卡），
## 但"不能建造"—— 合成一个布尔就会让他在拿到产出前先偷建。
func refresh(st: GameState, status: String, can_act: bool, main_phase: bool = true, preroll: bool = false) -> void:
	# 兑换弹窗打开时要用当前比例和库存，把局面留一份在 HUD 上
	_st = st
	_can_act = can_act
	for pid in 4:
		var p: PlayerState = st.players[pid]
		var is_active := (pid == st.current)
		_row_names[pid].text = ("▶ " if is_active else "") + p.label
		var vp := st.victory_points(p.id)
		var extra := ""
		if st.longest_road_owner == pid:
			extra += " 路+2"
		if st.largest_army_owner == pid:
			extra += " 军+2"
		_row_vps[pid].text = "%d分%s" % [vp, extra]
		_row_res[pid].text = _res_bbcode(p)

		# 当前玩家高亮边框
		var sb: StyleBoxFlat = _row_frames[pid]
		if is_active:
			sb.border_color = UIPalette.player_color(pid)
			sb.set_border_width_all(2)
		else:
			sb.border_color = Color(0.87, 0.86, 0.83)
			sb.set_border_width_all(1)
		# 面板标签只放得下"小红"这种短名，难度挂 tooltip 补足
		if p.is_ai:
			_row_nodes[pid].tooltip_text = "%s · 难度：%s" % [p.label, GameDirector.DIFF_NAMES[p.difficulty]]

	_status.text = status
	_status.add_theme_color_override("font_color",
		UIPalette.GOOD if can_act else UIPalette.INK)

	# 掷骰前只留「掷骰子 + 打发展卡」，主阶段才给建造/交易/结束回合。
	# 隐藏而不是置灰：灰按钮会让玩家以为"再等等就能点"，实际这个窗口里永远点不了。
	_act_row.visible = main_phase
	_btn_roll.visible = preroll
	_btn_end.disabled = not (can_act and main_phase)
	_btn_buy.disabled = not (can_act and main_phase and Rules.can_buy_dev(st, 0))

	_refresh_trade(st, can_act and main_phase)
	_refresh_dev_btn(st, can_act)

## 轮次与骰子
func set_turn_info(round_no: int, dice: int) -> void:
	var parts: Array[String] = []
	if round_no > 0:
		parts.append("第 %d 轮" % round_no)
	if dice > 0:
		parts.append("骰子 %d" % dice)
	_dice.text = "   ·   ".join(parts)

var _log_count := -1
var _log_last := ""

## 全量显示，不做截断 —— 老事件不会被"刷新掉"。
## 想让玩家既能看历史、又不被新事件打断滚动，所以只在
## "他本来就停在底部"时才自动滚到最新。
##
## 变更有无靠"条数 + 末行"判断，不能拿数组自己和自己比：
## 传进来的就是 GameState.log_lines 这个引用，比较长度永远相等。
func set_log(lines: Array[String]) -> void:
	var last := lines[lines.size() - 1] if not lines.is_empty() else ""
	if lines.size() == _log_count and last == _log_last:
		return   # 没有新内容，别动滚动位置
	_log_count = lines.size()
	_log_last = last

	var stick := _at_log_bottom()
	_log.text = "\n".join(lines)
	_log_title.text = "事件日志（共 %d 条）" % lines.size()
	if stick:
		_scroll_log_to_end.call_deferred()

func _at_log_bottom() -> bool:
	if _log == null or _log.get_line_count() == 0:
		return true
	var sb := _log.get_v_scroll_bar()
	if sb == null:
		return true
	return sb.value >= sb.max_value - sb.page - 2.0

func _scroll_log_to_end() -> void:
	_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))

func _res_bbcode(p: PlayerState) -> String:
	var parts: Array[String] = []
	for r in Res.R_COUNT:
		var n: int = p.resources[r]
		var col: String = UIPalette.RES_HEX[r]
		if n > 0:
			parts.append("[color=%s]%s[/color]%d" % [col, UIPalette.RES_SHORT[r], n])
		else:
			parts.append("[color=#c9c7c2]%s[/color]0" % UIPalette.RES_SHORT[r])
	var dev := p.dev_cards.size() + p.fresh_dev_cards.size()
	parts.append("  券%d 骑%d" % [dev, p.played_knights])
	return " ".join(parts)

## 「兑换」按钮：只要有任意可行组合就亮着，具体怎么换交给弹窗里选
func _refresh_trade(st: GameState, can_act: bool) -> void:
	var opts := Rules.bank_trade_options(st, 0)
	var sig := "%s|%s" % [can_act, str(opts)]
	if sig == _trade_sig:
		return
	_trade_sig = sig
	_btn_trade.disabled = not can_act or opts.is_empty()

# ================= 银行兑换弹窗 =================

## 结构与"重开一局"弹窗同一套路：全屏遮罩 + 居中白卡片。
## 左右两列各 5 个资源按钮，每次打开时按当前局面重建——
## 港口比例（4/3/2）和持有量随时在变，不能建一次用到底。
func _build_trade_dialog() -> void:
	_trade_dlg = Control.new()
	_trade_dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_trade_dlg.visible = false
	_trade_dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_trade_dlg)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.34)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_trade_dlg.add_child(shade)

	_trade_card = PanelContainer.new()
	_trade_card.add_theme_stylebox_override("panel", _card_style())
	# 宽度要算上卡片内边距（左右各 16），否则说明文字会被挤到换行溢出
	_trade_card.custom_minimum_size = Vector2(470, 0)
	_trade_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_trade_dlg.add_child(_trade_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	_trade_card.add_child(box)

	box.add_child(_label("银行兑换", 15, UIPalette.INK, true))

	var tip := _label("左侧选要付出的资源，右侧选想换回的资源。比例随港口改善：银行 4:1，任意型港口 3:1，特定型港口 2:1。", 11, UIPalette.MUTED, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(420, 0)
	box.add_child(tip)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	left.add_child(_label("付出", 12, UIPalette.MUTED, true))
	_trade_give_box = VBoxContainer.new()
	_trade_give_box.add_theme_constant_override("separation", 4)
	left.add_child(_trade_give_box)

	var arrow := _label("→", 18, UIPalette.MUTED, true)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(arrow)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(_label("换回", 12, UIPalette.MUTED, true))
	_trade_take_box = VBoxContainer.new()
	_trade_take_box.add_theme_constant_override("separation", 4)
	right.add_child(_trade_take_box)

	_trade_hint = _label("先在左侧选一个要付出的资源", 11, UIPalette.MUTED, false)
	box.add_child(_trade_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var cancel := _button("取消")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close_trade_dialog)
	row.add_child(cancel)

	_trade_ok = _button("确定", true)
	_trade_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_ok.disabled = true
	_trade_ok.pressed.connect(_confirm_trade)
	row.add_child(_trade_ok)

## 每次打开都重建两侧列表：比例和持有量是"打开那一刻"的快照
func show_trade_dialog() -> void:
	if _st == null:
		return
	_give_sel = -1
	_take_sel = -1
	_rebuild_trade_lists()
	_trade_dlg.visible = true
	_center_card(_trade_card, 470.0)

func close_trade_dialog() -> void:
	if _trade_dlg == null:
		return
	_trade_dlg.visible = false

func _rebuild_trade_lists() -> void:
	var p: PlayerState = _st.players[0]
	for c in _trade_give_box.get_children():
		c.queue_free()
	for c in _trade_take_box.get_children():
		c.queue_free()
	_trade_give_btns.clear()
	_trade_take_btns.clear()
	# 上一次打开时的提示会残留（"确定后：付出…"），重置回初始引导语
	_trade_hint.text = "先在左侧选一个要付出的资源"

	for r in Res.R_COUNT:
		var ratio := Rules.best_ratio_for(_st, 0, r)
		var n: int = p.count(r)
		var gb := _res_button("%s ×%d（持有 %d）" % [UIPalette.RES_SHORT[r], ratio, n])
		gb.disabled = not _can_act or n < ratio
		gb.tooltip_text = "付出 %d 个%s，从银行换回 1 个右侧任意资源" % [ratio, UIPalette.RES_SHORT[r]]
		gb.pressed.connect(_on_give_clicked.bind(r))
		_trade_give_box.add_child(gb)
		_trade_give_btns.append(gb)

		var tb := _res_button("%s ×1" % UIPalette.RES_SHORT[r])
		tb.tooltip_text = "换回 1 个%s（银行库存 %d）" % [UIPalette.RES_SHORT[r], _st.bank[r]]
		tb.pressed.connect(_on_take_clicked.bind(r))
		_trade_take_box.add_child(tb)
		_trade_take_btns.append(tb)

	_refresh_take_states()
	_update_trade_ok()

func _on_give_clicked(r: int) -> void:
	_give_sel = r
	# 付出的资源换了，之前选的"换回"多半不再有效（比如换回同种资源），清掉重选
	_take_sel = -1
	for i in Res.R_COUNT:
		_style_res_button(_trade_give_btns[i], i == r)
	var ratio := Rules.best_ratio_for(_st, 0, r)
	_trade_hint.text = "付出 %d 个%s，再从右侧选一个换回的资源" % [ratio, UIPalette.RES_SHORT[r]]
	_refresh_take_states()
	_update_trade_ok()

func _on_take_clicked(r: int) -> void:
	_take_sel = r
	var ratio := Rules.best_ratio_for(_st, 0, _give_sel)
	_trade_hint.text = "确定后：付出 %d 个%s，换回 1 个%s" % [ratio, UIPalette.RES_SHORT[_give_sel], UIPalette.RES_SHORT[r]]
	_refresh_take_states()
	_update_trade_ok()

## 右列可用性随左列选择变化：没选付出资源时全灰，
## 选了之后排除同种资源 + 银行缺货的资源
func _refresh_take_states() -> void:
	for r in Res.R_COUNT:
		var b: Button = _trade_take_btns[r]
		var invalid: bool = r == _give_sel or _st.bank[r] <= 0
		b.disabled = _give_sel < 0 or invalid
		_style_res_button(b, r == _take_sel and not b.disabled)

func _update_trade_ok() -> void:
	_trade_ok.disabled = _give_sel < 0 or _take_sel < 0

func _confirm_trade() -> void:
	if _give_sel < 0 or _take_sel < 0 or _give_sel == _take_sel:
		return
	var g := _give_sel
	var t := _take_sel
	close_trade_dialog()
	bank_trade_pressed.emit(g, t)

## 资源选择按钮：选中 = 蓝框高亮，未选 = 普通浅灰，禁用 = 更淡的灰。
## 选中态靠重设 stylebox 实现（Button 的 toggle_mode 语义是"按住开关"，
## 和这里"单选高亮"不是一回事，自己管样式更直观）。
func _res_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var fg := UIPalette.INK
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", Color(0.30, 0.30, 0.30))
	b.add_theme_color_override("font_disabled_color", Color(0.68, 0.67, 0.65))
	_style_res_button(b, false)
	return b

func _style_res_button(b: Button, selected: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		if selected:
			sb.bg_color = Color(0.851, 0.898, 0.969)
			sb.border_color = UIPalette.PLAYER[0]
			sb.set_border_width_all(2)
		else:
			match state:
				"normal":
					sb.bg_color = Color(0.945, 0.937, 0.910)
					sb.border_color = Color(0.74, 0.72, 0.68)
				"hover":
					sb.bg_color = Color(0.878, 0.918, 0.973)
					sb.border_color = Color(0.35, 0.55, 0.80)
				_:
					sb.bg_color = Color(0.792, 0.867, 0.949)
					sb.border_color = Color(0.25, 0.45, 0.72)
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	# 禁用态单独盖一层更淡的样式（选中与否都一样，反正点不了）
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0.929, 0.925, 0.914)
	dsb.border_color = Color(0.855, 0.847, 0.827)
	dsb.set_border_width_all(1)
	dsb.set_corner_radius_all(6)
	dsb.content_margin_left = 10
	dsb.content_margin_right = 10
	dsb.content_margin_top = 6
	dsb.content_margin_bottom = 6
	b.add_theme_stylebox_override("disabled", dsb)

## 「打发展卡」按钮：本回合还没打过、且手上有能打的卡时才亮。
## 掷骰前后都能点 —— 官方规则里骑士、修路、丰收、垄断都可以在掷骰前打出。
func _refresh_dev_btn(st: GameState, can_act: bool) -> void:
	var counts := _dev_counts(st.players[0])
	var sig := "%s|%s|%s" % [can_act, st.dev_played_this_turn, str(counts)]
	if sig == _dev_sig:
		return
	_dev_sig = sig

	var total := 0
	for c in counts:
		total += counts[c]
	_btn_play.disabled = not can_act or st.dev_played_this_turn or total == 0
	_btn_play.text = "打发展卡 %d" % total if total > 0 else "打发展卡"
	_btn_play.tooltip_text = "本回合已打过 1 张，下回合才能再打" if st.dev_played_this_turn \
		else "打出 1 张发展卡：掷骰前、掷骰后都可以，每回合限 1 张"

## 手里能打的卡按类型计数。胜利点卡自动计分、不进列表；
## 本回合刚买的卡在 fresh_dev_cards 里，playable_dev_cards 已经排除了。
func _dev_counts(p: PlayerState) -> Dictionary:
	var counts := {}
	for card in Rules.playable_dev_cards(p):
		if card == Res.Dev.VICTORY:
			continue
		counts[card] = counts.get(card, 0) + 1
	return counts

# ================= 发展卡弹窗 =================

## 三级弹窗：选卡 →（垄断 / 丰收）再选资源。
##
## 层级靠 add_child 顺序保证：mono / yop 建在 dev 之后，所以盖在上面。
## 二级弹窗关闭时**一级保持可见**，取消就能退回上一步，
## 不会出现"点了个取消结果整串流程消失"的迷惑。
func _build_dev_dialogs() -> void:
	_build_dev_dialog()
	_build_mono_dialog()
	_build_yop_dialog()

## 浮层骨架：全屏遮罩 + 居中白卡片（与兑换弹窗同一套路）
func _new_dialog(width: float) -> Dictionary:
	var dlg := Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.visible = false
	dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dlg)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.34)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.add_child(shade)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(width, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)
	return {"dlg": dlg, "card": card, "box": box}

## 弹窗底部的 取消 / 确定 一行。返回「确定」按钮（初始禁用，选好才亮）
func _dialog_buttons(box: Node, cancel_cb: Callable, ok_cb: Callable) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var cancel := _button("取消")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(cancel_cb)
	row.add_child(cancel)
	var ok := _button("确定", true)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.disabled = true
	ok.pressed.connect(ok_cb)
	row.add_child(ok)
	return ok

## 清空容器。用 remove_child + free 而不是 queue_free：
## queue_free 要等到这一帧结束才生效，紧接着算卡片高度时
## 那些"该删掉"的按钮还挂在树上，居中就会按旧高度算偏。
func _clear_box(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.free()

func _build_dev_dialog() -> void:
	var d := _new_dialog(430.0)
	_dev_dlg = d["dlg"]
	_dev_card = d["card"]
	var box: VBoxContainer = d["box"]

	box.add_child(_label("打出发展卡", 15, UIPalette.INK, true))
	var tip := _label("每回合最多打 1 张；本回合刚买的卡要到下回合才能打。", 11, UIPalette.MUTED, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(380, 0)
	box.add_child(tip)

	_dev_box = VBoxContainer.new()
	_dev_box.add_theme_constant_override("separation", 4)
	box.add_child(_dev_box)

	# 选卡弹窗没有"确定"：点哪张就是打哪张（垄断 / 丰收会再开一级选资源）
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var cancel := _button("取消")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close_dev_dialog)
	row.add_child(cancel)

func _build_mono_dialog() -> void:
	var d := _new_dialog(400.0)
	_mono_dlg = d["dlg"]
	_mono_card = d["card"]
	var box: VBoxContainer = d["box"]

	box.add_child(_label("垄断：指定一种资源", 15, UIPalette.INK, true))
	var tip := _label("收走所有对手手里的该资源，自己手里的不动。合计为 0 的选不了。", 11, UIPalette.MUTED, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(350, 0)
	box.add_child(tip)

	_mono_box = VBoxContainer.new()
	_mono_box.add_theme_constant_override("separation", 4)
	box.add_child(_mono_box)

	_mono_hint = _label("选择要垄断的资源", 11, UIPalette.MUTED, false)
	box.add_child(_mono_hint)
	_mono_ok = _dialog_buttons(box, close_mono_dialog, _confirm_mono)

func _build_yop_dialog() -> void:
	var d := _new_dialog(470.0)
	_yop_dlg = d["dlg"]
	_yop_card = d["card"]
	var box: VBoxContainer = d["box"]

	box.add_child(_label("丰收年：拿 2 张资源", 15, UIPalette.INK, true))
	var tip := _label("左右两列各选 1 张，可以选同一种（银行要有足够的存货）。", 11, UIPalette.MUTED, false)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(420, 0)
	box.add_child(tip)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	box.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	left.add_child(_label("第 1 张", 12, UIPalette.MUTED, true))
	_yop_left = VBoxContainer.new()
	_yop_left.add_theme_constant_override("separation", 4)
	left.add_child(_yop_left)

	var plus := _label("+", 18, UIPalette.MUTED, true)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(plus)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(_label("第 2 张", 12, UIPalette.MUTED, true))
	_yop_right = VBoxContainer.new()
	_yop_right.add_theme_constant_override("separation", 4)
	right.add_child(_yop_right)

	_yop_hint = _label("两列各选 1 张", 11, UIPalette.MUTED, false)
	box.add_child(_yop_hint)
	_yop_ok = _dialog_buttons(box, close_yop_dialog, _confirm_yop)

# ---------------- 选卡弹窗 ----------------

func show_dev_dialog() -> void:
	if _st == null:
		return
	_rebuild_dev_list()
	_dev_dlg.visible = true
	_center_card(_dev_card, 430.0)

func close_dev_dialog() -> void:
	if _dev_dlg == null:
		return
	_dev_dlg.visible = false

func _rebuild_dev_list() -> void:
	_clear_box(_dev_box)
	var counts := _dev_counts(_st.players[0])
	# 固定顺序，别让列表顺序随手牌顺序跳动
	for card in [Res.Dev.KNIGHT, Res.Dev.ROAD_BUILDING, Res.Dev.YEAR_OF_PLENTY, Res.Dev.MONOPOLY]:
		if not counts.has(card):
			continue
		var b := _res_button("%s ×%d" % [DEV_LABEL[card], counts[card]])
		b.disabled = not _can_act or _st.dev_played_this_turn
		b.tooltip_text = DEV_TIP[card]
		b.pressed.connect(_on_dev_card_clicked.bind(card))
		_dev_box.add_child(b)

	if _dev_box.get_child_count() == 0:
		_dev_box.add_child(_label("（暂时没有可打出的卡）", 11, UIPalette.MUTED, false))
	elif _st.dev_played_this_turn:
		_dev_box.add_child(_label("本回合已经打过 1 张了，下回合再来", 11, UIPalette.MUTED, false))

func _on_dev_card_clicked(card: int) -> void:
	match card:
		Res.Dev.MONOPOLY:
			show_mono_dialog()
		Res.Dev.YEAR_OF_PLENTY:
			show_yop_dialog()
		_:
			# 骑士 / 修路：没有参数，直接打出
			close_dev_dialog()
			play_dev_pressed.emit(card, -1, -1, -1)

# ---------------- 垄断：单列选 1 种资源 ----------------

func show_mono_dialog() -> void:
	if _st == null:
		return
	_mono_sel = -1
	_rebuild_mono_list()
	_mono_dlg.visible = true
	_center_card(_mono_card, 400.0)

func close_mono_dialog() -> void:
	if _mono_dlg == null:
		return
	_mono_dlg.visible = false

func _rebuild_mono_list() -> void:
	_clear_box(_mono_box)
	_mono_btns.clear()
	_mono_hint.text = "选择要垄断的资源"

	for r in Res.R_COUNT:
		# 收的是对手手里的牌，自己手里的不算
		var n := Rules.monopoly_yield(_st, 0, r)
		var b := _res_button("%s ×%d" % [UIPalette.RES_SHORT[r], n])
		b.disabled = not _can_act or n <= 0
		b.tooltip_text = "%s：%s" % [UIPalette.RES_SHORT[r], Rules.monopoly_breakdown(_st, 0, r)]
		b.pressed.connect(_on_mono_clicked.bind(r))
		_mono_box.add_child(b)
		_mono_btns.append(b)
	_mono_ok.disabled = true

func _on_mono_clicked(r: int) -> void:
	_mono_sel = r
	for i in Res.R_COUNT:
		_style_res_button(_mono_btns[i], i == r)
	_mono_hint.text = "确定后：收走全场 %d 张%s" % [Rules.monopoly_yield(_st, 0, r), UIPalette.RES_SHORT[r]]
	_mono_ok.disabled = false

func _confirm_mono() -> void:
	if _mono_sel < 0:
		return
	var r := _mono_sel
	close_mono_dialog()
	close_dev_dialog()
	play_dev_pressed.emit(Res.Dev.MONOPOLY, r, -1, -1)

# ---------------- 丰收年：两列各选 1 张（可相同） ----------------

func show_yop_dialog() -> void:
	if _st == null:
		return
	_yop_sel = [-1, -1]
	_rebuild_yop_lists()
	_yop_dlg.visible = true
	_center_card(_yop_card, 470.0)

func close_yop_dialog() -> void:
	if _yop_dlg == null:
		return
	_yop_dlg.visible = false

func _rebuild_yop_lists() -> void:
	_clear_box(_yop_left)
	_clear_box(_yop_right)
	_yop_btns = [[], []]
	_yop_hint.text = "两列各选 1 张，可以选同一种"

	for r in Res.R_COUNT:
		for col in 2:
			var b := _res_button("%s ×1" % UIPalette.RES_SHORT[r])
			b.tooltip_text = "拿 1 张%s（银行库存 %d）" % [UIPalette.RES_SHORT[r], _st.bank[r]]
			b.pressed.connect(_on_yop_clicked.bind(col, r))
			(_yop_left if col == 0 else _yop_right).add_child(b)
			_yop_btns[col].append(b)
	_refresh_yop_states()
	_yop_ok.disabled = true

func _on_yop_clicked(col: int, r: int) -> void:
	_yop_sel[col] = r
	_refresh_yop_states()
	_yop_ok.disabled = _yop_sel[0] < 0 or _yop_sel[1] < 0
	if _yop_ok.disabled:
		_yop_hint.text = "还要再选第 %d 张" % (2 if _yop_sel[0] >= 0 else 1)
	else:
		_yop_hint.text = "确定后：拿走 %s、%s" % [
			UIPalette.RES_SHORT[_yop_sel[0]], UIPalette.RES_SHORT[_yop_sel[1]]]

## 两列的可用性互相牵连：两列选同一种时，那种资源银行得有 2 张才发得出来，
## 否则第二张会静默发不出（bank_take 取空）—— 所以直接在 UI 上禁掉。
func _refresh_yop_states() -> void:
	for col in 2:
		for r in Res.R_COUNT:
			var b: Button = _yop_btns[col][r]
			var need := 2 if r == _yop_sel[1 - col] else 1
			b.disabled = not _can_act or _st.bank[r] < need
			_style_res_button(b, r == _yop_sel[col] and not b.disabled)

func _confirm_yop() -> void:
	if _yop_sel[0] < 0 or _yop_sel[1] < 0:
		return
	var r1: int = _yop_sel[0]
	var r2: int = _yop_sel[1]
	close_yop_dialog()
	close_dev_dialog()
	play_dev_pressed.emit(Res.Dev.YEAR_OF_PLENTY, -1, r1, r2)

# ================= 控件工厂 =================

func _label(text: String, size: int, col: Color, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0))
	return l

## primary=true 用来标出弹窗里的主操作（"确定"）：深蓝底 + 白字，
## 和旁边一排浅色次级按钮拉开层级，玩家一眼知道该点哪个。
func _button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	var fg := Color(1, 1, 1) if primary else UIPalette.INK
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", Color(0.88, 0.90, 0.95) if primary else Color(0.30, 0.30, 0.30))
	b.add_theme_color_override("font_disabled_color", Color(0.88, 0.90, 0.94) if primary else Color(0.68, 0.67, 0.65))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		if primary:
			match state:
				"normal":
					sb.bg_color = Color(0.184, 0.435, 0.816)
					sb.border_color = Color(0.133, 0.329, 0.655)
				"hover":
					sb.bg_color = Color(0.243, 0.502, 0.878)
					sb.border_color = Color(0.133, 0.329, 0.655)
				"pressed":
					sb.bg_color = Color(0.129, 0.325, 0.643)
					sb.border_color = Color(0.098, 0.255, 0.529)
				_:
					sb.bg_color = Color(0.741, 0.792, 0.878)
					sb.border_color = Color(0.655, 0.714, 0.820)
		else:
			match state:
				"normal":
					sb.bg_color = Color(0.945, 0.937, 0.910)
					sb.border_color = Color(0.74, 0.72, 0.68)
				"hover":
					sb.bg_color = Color(0.878, 0.918, 0.973)
					sb.border_color = Color(0.35, 0.55, 0.80)
				"pressed":
					sb.bg_color = Color(0.792, 0.867, 0.949)
					sb.border_color = Color(0.25, 0.45, 0.72)
				_:
					sb.bg_color = Color(0.929, 0.925, 0.914)
					sb.border_color = Color(0.855, 0.847, 0.827)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, sb)
	return b
