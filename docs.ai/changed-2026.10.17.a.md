# changed · 竖屏 P1/P2 落地：分区布局 + 日志弹窗（桌面逐像素不变）

> 类型：`changed`（变体 A）。日期：2026-10-17（当日第 1 份）。
> 上游：`plan-2026.10.15.a.md`（开工计划，§8 验收清单已逐项打勾并回填 §4.4 实测）。
> 基线：`portrait @ d214c6d`（P0）。提交组：C1 = `3fa50aa`，C2+C3 = `9ef4682`，C4 = 本文档所在提交。
> 代码改动范围严守计划：只动 `ui/` 与 `tools/`，`core/` `ai/` `game/` `scenes/` `project.godot` 一行未动。

---

## 1. 做了什么

### P1（C1，`3fa50aa`）—— `ui/layout.gd` + 朝向锁定 + 棋盘自适应

- 新增 `ui/layout.gd`（`class_name Layout`，全静态）：**只装竖屏分支**的算式与常数
  （`board_rect` / `panel_rect` / `content_rect` / `px_per_unit_for` / `ui_height`），
  横屏三条既有算式逐字节不动（D1/D3/D4）。
- `BoardView._ready` 开头按**窗口物理尺寸**锁朝向（`is_portrait_for_window`，纯函数），
  `content_scale_size` 先比现值、不同才写（D5）。
- `board_origin_for` / `_fit_to_viewport` 各加一个分支；竖屏不叠加 `BOARD_X_BIAS`，
  `px_per_unit` 只在竖屏写回（横屏单一真源不破）。
- `probe_display.gd` 加 `-- css` 分支，实测**写基准后 `size_changed` 当帧触发、新 vp
  当帧生效**（plan §4.4 回填）。
- 新增 `tools/test_layout.gd`（29 条）。

### P2（C2+C3，`9ef4682`）—— 信息区分区 + 日志弹窗化

- `HUD._apply_layout` / `HUD.content_rect` 竖屏分支：信息区横贯屏宽铺在棋盘下方，
  底色到屏边、内容盒让开安全区；分隔线竖条改横条。横屏路径逐字节不动。
- 日志两种形态**不同构**（D7/N2）：竖屏 `_box` 里放「查看日志（N 条）」按钮 +
  全屏弹窗（复用 `_new_dialog`，宽 560；宽度自适应按 N1 归 P3）；横屏照旧内嵌。
  `_log` / `_log_title` 两朝向都存在且被 `set_log()` 填满。
- Esc 链紧跟重开弹窗插入日志层（D6，null 守卫）；`on_new_game()` 一并关闭；
  `set_log()` 末尾追加按钮条数跟随 + 弹窗开着强制滚到底。
- **Q6 结论：不加 ScrollContainer**——720×1280 内容富余 ~120px（出图确认），
  iPad 720×960 略紧但"能跑不崩即可"；EXPAND_FILL 的坑留到 P3 量完自然高度再定。

### C4 —— 渲染验证工具 + 文档

- 新增 `tools/shot_portrait.gd`（禁止 headless）：注入安全区 (18,34,18,18) →
  分区几何断言 → 真实点击日志按钮（push_input，按下+抬起成对，坐标乘窗口/视口倍率）→
  Esc 关闭断言 → 两张出图。
- `AGENTS.md`：命令区补 `test_layout.gd` / `shot_portrait.gd` 与竖屏预览说明；
  traps 17~20（Button 需要按下+抬起、push_input 坐标按窗口解释、Windows git stash
  翻转 CRLF、is_equal_approx 无容差参数）；definition of done 补两行。
- `docs.ai/README.md` 速查表行（立项时已加）、`plan-2026.10.15.a.md` §4.4 回填 + §8 打勾。

## 2. 验证结果（全绿）

| 项 | 结果 |
|---|---|
| `test_layout.gd`（新） | 通过 29 · 失败 0；自检表 66.12 / 62.96 / 45.3 逐个对上 |
| `test_safe_area.gd` | 18/18（桌面 (510,360)、px=62 零漂） |
| `test_pick` / `test_legend` / `test_ports` | 8 / 36 / 51 全过 |
| `verify_topology` / `test_rules` / `test_seed` | TOPOLOGY OK / 46/46 / 全过 |
| `test_trade_dialog` / `test_dev_dialog` | 24/24 / 56/56 |
| `sim_runner -- 200` | 三条不变量 0 破坏，M1 PASS |
| 桌面空棋盘截图 vs P0 worktree 基线 | **md5 逐像素一致**（8085b9fc…） |
| `test_interaction -- 6000`（渲染） | M2 PASS（250 帧打完 22 轮，小橙 10 分胜） |
| `shot_dialog`（渲染，桌面弹窗构图） | PASS |
| `shot_portrait`（渲染，720×1280 窗口 + auto） | 14/14 PASS；vp=868×1280、px=62.96、棋盘外接框在棋盘区内、信息区不压棋盘、弹窗点开/Esc 关 |

## 3. 实测中发现的新事实（已写进 AGENTS.md traps 17~20）

1. `--resolution 720x1280` 在本机被窗口管理器压成 720×**1061**，vp = 868×1280
   （expand 短边对齐），仍判竖屏；合成鼠标坐标必须乘 `窗口/视口` 倍率（trap 3 的推论）。
2. `Button.pressed` 经 `root.push_input` 需要**按下+抬起成对**只推 pressed 永不触发。
3. 本机 `git stash` 往返会把工作区文件翻成 CRLF（仓库是 LF），全库显示假改动；
   要基线截图用 `git worktree add` 别用 stash。
4. Godot `is_equal_approx` 没有容差参数，要容差自己写 `absf(a-b) <= tol`。

## 4. 遗留（按计划归 P3/P4）

- 弹窗宽度自适应（N1，竖屏重开/垄断/选卡/兑换都还是横屏宽度算法）。
- `UI_RATIO 0.48 / UI_MIN 400 / UI_MAX 940` 是估算值，P3 按"宁可比桌面大"校准；
  竖屏信息区自然内容高度量出来后再定 ScrollContainer 与 EXPAND_FILL。
- hover 关闭、点击位移阈值、`HELP_R` 22、返回键、软键盘避让、按钮最小高度、真机。
