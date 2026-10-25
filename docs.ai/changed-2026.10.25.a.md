# changed · 开局弹窗：逐 AI 难度 + 去掉种子输入框（棋盘每局随机）

> 类型：`changed`（变体 A）。日期：2026-10-25（当日第 1 份）。
> 基线：`portrait @ 0e5f4e8`（竖屏操作网格 3×2）。
> 需求原话：「现在在开局弹窗中，可以设置每个 AI 的难度，不需要输入随机数，直接随机即可，每次开局都随机」。

---

## 1. 做了什么

### 1.1 弹窗内容：种子输入框 → 逐 AI 难度

旧版「重开一局」弹窗里是一个 `LineEdit`（手打 9 位种子）+ 「随机一局 / 沿用本局 / 确定 / 取消」。
现在换成：

```
新开一局
棋盘每局自动随机，不用输种子。给三个电脑各选一档难度吧。

小红   [简单] [标准] [困难]      ← 三个互斥 toggle（ButtonGroup）
小橙   [简单] [标准] [困难]
小绿   [简单] [标准] [困难]

[开始游戏]                        ← 局中打开时左半边还有「取消」
```

- `HUD._diff_btns[i][d]`：第 i 个 AI 的第 d 档按钮，下标对齐
  `GameDirector.AI_LABELS` / `DIFF_NAMES`，不再另存一份"当前选择"数组
  （按钮的 `button_pressed` 是唯一真源，避免两处不同步）。
- 选中态**单独画成蓝底白字**：`_button()` 默认的 pressed 是浅蓝，与 hover 几乎同色，
  触屏上没有 hover 对比就分不出选了哪档。
  ⚠️ 必须同时覆盖 `hover_pressed` 样式与 `font_hover_pressed_color`，
  只覆盖 `pressed` 会让鼠标悬停到已选中的按钮上时掉回 Godot 默认暗色主题（白字看不见）。
- 名字用各自棋子的颜色（`UIPalette.player_color`），和三色的玩家面板行对得上。

### 1.2 种子：玩家不再碰，每局自动随机

- `HUD` 信号 `restart_pressed(seed_text: String)` → `new_game_pressed(diffs: Array)`。
- `GameDirector._on_restart`（解析 `""` / `"r"` / 整数）删除，换成
  `start_game(diffs)`：夹紧难度 → `seed_value = _roll_seed()` → `_start_new_game()`。
- 复现需求保留但挪出界面：命令行 `--seed=NNN`（`GameDirector._ready` 里解析，
  存 `_fixed_seed`，`>= 0` 时不再随机）。日志照旧打印「棋盘种子 N（每局随机）」，
  出问题可以照着命令行钉住。

### 1.3 开局前自动弹窗

- `GameDirector.bind()` 里原来的 `_start_new_game.call_deferred()` 换成 `_boot.call_deferred()`：
  - `auto_play`（截图 / 批量验收 / `-- auto`）→ 直接开局；
  - 交互式 → `hud.show_new_game_dialog(ai_difficulties, false)`。

  `auto` 必须跳过弹窗，否则 `screenshot.gd` / `shot_help.gd` / `test_interaction.gd`
  这些加载 `main.tscn` 的脚本全会卡在没人点的模态浮层上。
- 开局前 `can_cancel = false`：没有「本局」可回，取消按钮隐藏、**Esc 也不生效**
  （否则玩家会得到一张空棋盘，还得自己去找「重开一局」把面板叫回来）。
- 局中点「重开一局」= 同一个弹窗 `can_cancel = true`，难度按本局回填
  （`HUD.on_new_game(seed, diffs)` 记下来的 `_cur_diffs`）。

### 1.4 `HUD.show_idle()`：收拾弹窗背后的空面板

以前开局即刻发牌，「还没开局」的 HUD 状态永远露不出来。现在开局弹窗浮在它上面，
而 `refresh()` 还没跑过 —— 竖屏的 A1 格会同时显示「掷骰子」和「结束回合」
（两个按钮默认都 visible），横屏则多出一条能点的「打发展卡」。
新增 `show_idle()` 在 `_ready` 末尾把这些阶段按钮收起来；`refresh()` 里补
`_btn_play.visible = true` 明确恢复（不再依赖"默认就是 visible"）。

### 1.5 难度合法化抽成静态纯函数

`GameDirector.sanitize_diffs(diffs)`：越界夹紧、缺项按「标准」补、恒返回 3 项。
弹窗、命令行、测试都走这一份 —— `GameDirector` 是 Node，headless 里不方便 new 出来调
实例方法，静态函数可以直接调（`test_setup_dialog.gd` 就是这么验的）。

## 2. 改动文件

| 文件 | 改动 |
|---|---|
| `ui/hud.gd` | 弹窗重建（难度三档）、信号改名、`show_idle()`、`select_difficulties` / `selected_difficulties`、删掉 `_seed_edit` / `_input_style` / `_on_seed_text_changed` / `_submit_seed` |
| `game/game_director.gd` | `_boot()`、`start_game(diffs)`、`sanitize_diffs()`、`--seed=` 解析、`on_new_game(seed, diffs)` |
| `tools/test_setup_dialog.gd` | **新增**（headless，25 条） |
| `tools/shot_dialog.gd` | 重写：开局自动弹窗 → 真点「困难」→「开始游戏」→ 局中重开回填 |
| `tools/test_interaction.gd` | 开局走弹窗处理函数；重开改用 `new_game_pressed` 并断言**种子变了** |
| `tools/shot_help.gd` | 先按默认难度开局（否则截到空棋盘 + 遮罩） |
| `tools/test_seed.gd` | 删掉种子解析断言（功能已移除），保留随机性 / 官方数字规则 |
| `AGENTS.md` | 测试清单、trap 24（按钮要 press+release）/ trap 25（种子不再是玩家旋钮）、Definition of done |
| `DESIGN.md` | §16.9 改写为「开局弹窗 / 重开一局」 |
| `README.md` / `README.zh-CN.md` | 操作表、说明段、工具表 |
| `docs.ai/ref-项目架构总览.md` | 信号清单、弹窗清单、工具表 |

## 3. 验收

| 项 | 结果 |
|---|---|
| `test_setup_dialog.gd`（新增） | **25 通过 / 0 失败**（含"弹窗里 LineEdit 数量必须为 0"） |
| `shot_dialog.gd`（横屏 1280×720） | PASS：自动弹出 · 真点「困难」生效 · 开局换新种子 · 重开回填难度 |
| `shot_dialog.gd`（竖屏 720×1280） | PASS（卡片 320×262 居中于 (200,509)） |
| `test_interaction.gd -- 6000` | **M2 验收 PASS**（人类 22 次点击 / 8 次建造 / 胜者小橙 11 分；重开后种子确实变了） |
| `test_rules` / `test_seed` / `test_trade_dialog` / `test_dev_dialog` / `test_layout` / `test_safe_area` / `test_legend` / `test_ports` / `verify_topology` | 全绿，桌面棋盘原点仍为 (510, 360)（零漂移红线未破） |
| `shot_help.gd` | 图例交互全绿（含"点面板不落子"） |
| `screenshot.gd … auto` | 棋盘自检通过、`地形贴图: 6/6` |

## 4. 备注 / 风险

- **界面上的种子复现没了**：要复盘某张图必须知道日志里的种子号，并带 `--seed=` 重启。
  这是需求要求的取舍（"不需要输入随机数，直接随机即可"），已写进 README 与 trap 25。
- 开局弹窗开着时，局中的 AI 不会暂停（和旧版重开面板一致）。开局前没有对局，不存在这个问题；
  局中改难度时 AI 可能已经走了半步，属于既有行为，本次未改。
- `_diff_btns` 的按钮靠行内共享的 `ButtonGroup` 保证互斥；**不要**改成"全局一个 group"，
  那样三个电脑会互相取消。
