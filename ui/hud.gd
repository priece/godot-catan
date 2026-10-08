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
signal play_dev_pressed(card: int)
signal bank_trade_pressed(give_r: int, take_r: int)
## 参数是种子输入框的文本："" = 沿用上一局，"r" = 随机，
## 其他字符串交给 GameDirector 解析（非法值它自己兜底）。
signal restart_pressed(seed_text: String)

const PANEL_X := 896.0
const PANEL_W := 384.0
const VIEW_H := 720.0

const DEV_LABEL := ["骑士", "胜利点", "修路", "丰收年", "垄断"]

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
var _trade_grid: GridContainer
var _trade_title: Label
var _dev_grid: GridContainer
var _dev_title: Label
var _log_title: Label
var _log: RichTextLabel

var _trade_sig := ""
var _dev_sig := ""

func _ready() -> void:
	_build()
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

func _center_card(card: Control) -> void:
	var vp := get_viewport().get_visible_rect().size
	card.size = Vector2(320.0, maxf(card.size.y, 150.0))
	card.position = ((vp - card.size) * 0.5).round()

func _input_style(focused: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.98, 0.97)
	sb.border_color = Color(0.62, 0.71, 0.80) if focused else Color(0.82, 0.81, 0.78)
	sb.set_border_width_all(2 if focused else 1)
	sb.set_corner_radius_all(7)
	return sb

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.border_color = Color(0.86, 0.85, 0.82)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.20)
	sb.shadow_size = 14
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
	if not _dlg.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			# Esc 关掉浮层，别让玩家以为游戏卡住了
			close_dialog()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# 输入框有焦点时回车走 LineEdit.text_submitted，这里兜住
			# "焦点跑到别处（比如点了快捷按钮）后按回车"的情况。
			_fire_restart()
			get_viewport().set_input_as_handled()

## 新开一局时清掉各种"增量刷新"的缓存，否则新旧界面的按钮可能对不上
func on_new_game(cur_seed: int) -> void:
	_trade_sig = ""
	_dev_sig = ""
	_log_count = -1
	_log_last = ""
	_cur_seed = cur_seed
	close_dialog()

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

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_btn_end = _button("结束回合")
	_btn_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_end.pressed.connect(func(): end_turn_pressed.emit())
	row.add_child(_btn_end)
	_btn_buy = _button("买发展卡")
	_btn_buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_buy.pressed.connect(func(): buy_dev_pressed.emit())
	row.add_child(_btn_buy)

	_trade_title = _label("银行交易（点一下即换）", 12, UIPalette.MUTED, true)
	box.add_child(_trade_title)
	_trade_grid = GridContainer.new()
	_trade_grid.columns = 2
	_trade_grid.add_theme_constant_override("h_separation", 6)
	_trade_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_trade_grid)

	_dev_title = _label("发展卡", 12, UIPalette.MUTED, true)
	box.add_child(_dev_title)
	_dev_grid = GridContainer.new()
	_dev_grid.columns = 2
	_dev_grid.add_theme_constant_override("h_separation", 6)
	_dev_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_dev_grid)

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
## can_act: 人类玩家现在能否操作
func refresh(st: GameState, status: String, can_act: bool) -> void:
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

	_btn_end.disabled = not can_act
	_btn_buy.disabled = not (can_act and Rules.can_buy_dev(st, 0))

	_refresh_trade(st, can_act)
	_refresh_dev(st, can_act)

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

## 银行交易按钮：每个"付出资源"一个按钮，换进来的资源自动挑当前最缺的
func _refresh_trade(st: GameState, can_act: bool) -> void:
	var p: PlayerState = st.players[0]
	var opts := Rules.bank_trade_options(st, 0)
	var sig := "%s|%s" % [can_act, str(opts)]
	if sig == _trade_sig:
		return
	_trade_sig = sig

	for c in _trade_grid.get_children():
		c.queue_free()

	# 每种"付出资源"只留最好的那一档
	var seen := {}
	for o in opts:
		var give_r: int = o[0]
		if seen.has(give_r):
			continue
		seen[give_r] = true
		var ratio: int = o[2]
		var take_r := _most_needed(p, give_r)
		var b := _button("%d %s → %s" % [ratio, UIPalette.RES_SHORT[give_r], UIPalette.RES_SHORT[take_r]])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not can_act
		b.tooltip_text = "用 %d 个%s 向银行换 1 个%s" % [ratio, UIPalette.RES_SHORT[give_r], UIPalette.RES_SHORT[take_r]]
		b.pressed.connect(func(): bank_trade_pressed.emit(give_r, take_r))
		_trade_grid.add_child(b)

	if _trade_grid.get_child_count() == 0:
		var hint := _label("（暂时没有可换的组合）", 11, UIPalette.MUTED, false)
		_trade_grid.add_child(hint)

func _most_needed(p: PlayerState, exclude: int) -> int:
	var best := 0
	var best_n := -1
	for r in Res.R_COUNT:
		if r == exclude:
			continue
		var need := 0
		for cost in [Res.COST_CITY, Res.COST_SETTLEMENT, Res.COST_DEV]:
			need = maxi(need, maxi(0, cost.get(r, 0) - p.resources[r]))
		if need > best_n:
			best_n = need
			best = r
	return best

## 发展卡按钮：只列可打出的（胜利点卡自动计分，不显示）
func _refresh_dev(st: GameState, can_act: bool) -> void:
	var p: PlayerState = st.players[0]
	var playable := Rules.playable_dev_cards(p)
	var sig := "%s|%s|%s" % [can_act, st.dev_played_this_turn, str(playable)]
	if sig == _dev_sig:
		return
	_dev_sig = sig

	for c in _dev_grid.get_children():
		c.queue_free()

	if playable.is_empty():
		_dev_title.text = "发展卡（暂无）"
		return
	_dev_title.text = "发展卡（本回合还能打 1 张）" if not st.dev_played_this_turn else "发展卡（本回合已打过）"

	for card in playable:
		if card == Res.Dev.VICTORY:
			continue
		var b := _button("打出：" + DEV_LABEL[card])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not can_act or st.dev_played_this_turn
		b.pressed.connect(func(): play_dev_pressed.emit(card))
		_dev_grid.add_child(b)

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
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, sb)
	return b
