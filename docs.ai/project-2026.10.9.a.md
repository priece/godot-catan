# 2026-10-09 交互改造归档（a）：银行兑换弹窗化 → 弹窗样式修整 → 发展卡交互改造

> **本文覆盖当天连续四块改动**，其中第四块是 `plan-2026.10.9.a.md`（方案文档）的落地归档。
> 与 `rule-godot-命令与验证指南_v1.0.md` 的关系：那篇讲"怎么跑 Godot 验证"，本文讲"今天改了什么、为什么这么改、怎么证明没改坏"。
> 与 `project-2026.10.8.a.md` 的关系：那篇是项目总览（架构/棋盘几何/历史踩坑），本文是当日增量。

---

## 零、当日总览

结论先行：**三块 UI 改造全部落在 `ui/hud.gd` + 规则/流程层的必要支撑上，AI 与规则引擎的既有语义一行未改**——用 `sim_runner -- 200` 与改动前基线**逐项一致**证明。

| # | 改动 | 主要文件 | 新增验证 |
|---|---|---|---|
| 一 | 银行兑换从"按钮排"改为「兑换」弹窗（左列付出带比例、右列换回、双侧高亮） | `ui/hud.gd` | `test_trade_dialog.gd` 24 条 + 3 张截图 |
| 二 | 弹窗加内边距（修"贴边难看"） | `ui/hud.gd`、`shot_dialog.gd` | 24/24 复跑 + 4 张截图 |
| 三 | 沉淀 Godot 命令与验证指南 | `docs.ai/rule-godot-命令与验证指南_v1.0.md` | —（文档） |
| 四 | **发展卡交互改造**：掷骰前可打全部功能卡 + 三级弹窗 | `core/*`、`game/game_director.gd`、`ui/hud.gd` | `test_dev_dialog.gd` 56 条 + 3 张截图 |

净增：`tools/test_trade_dialog.gd`、`tools/shot_trade_dialog.gd`、`tools/test_dev_dialog.gd`、`tools/shot_dev_dialog.gd` 四个脚本，共 80 条 headless 单测 + 6 张真渲染截图。

---

## 一、银行兑换弹窗化

### 1.1 需求与结果

| 需求 | 结果 |
|---|---|
| 面板上「兑换」一个按钮，不再是一排"点一下即换" | ✅ 操作行 = 结束回合 / 买发展卡 / 兑换 |
| 左列列出可用资源，带比例 ×N | ✅ 银行 ×4、任意型港口 ×3、特定型港口该资源 ×2，比例**按规则层现算**（`Rules.bank_trade_options`） |
| 右列是兑换结果 | ✅ 同种资源禁用、银行缺货禁用 |
| 两侧都可高亮选择 | ✅ 点选即蓝色高亮，底部实时提示"确定后：付出 4 个木，换回 1 个麦" |
| 下面是确定 / 取消 | ✅ 两侧都选好后「确定」才可点；走原有 `bank_trade_pressed` 信号 |

### 1.2 改动（全部在 `ui/hud.gd`）

- 删掉原 `_trade_grid` 按钮排与 `_most_needed`（原来"换回哪种"是 HUD 自己猜最缺的，现在交给玩家）
- 新增 `_build_trade_dialog` / `show_trade_dialog` / `_rebuild_trade_lists` / `_on_give_clicked` / `_on_take_clicked` / `_style_res_button`
- `_refresh_trade` 简化为只管「兑换」按钮的可用态
- `_center_card` 增加宽度参数，并用 `get_combined_minimum_size()` 兜底隐藏态高度
- Esc / 回车对兑换弹窗同样生效；`on_new_game` 时自动关闭

**关键取舍**：`bank_trade_pressed` 信号与 `GameDirector` 的处理链路**原样复用**，弹窗只负责"怎么选"，不碰"怎么换"。

### 1.3 验证

| 项 | 结果 |
|---|---|
| `test_trade_dialog.gd` | 24/24（左右可用性、同种/缺货禁用、确定联动、信号参数、取消复位） |
| `shot_trade_dialog.gd` | 3 张，卡片居中且完整落在 720 高视口内 |
| 回归 | test_rules 46/46、test_seed 全过、verify_topology OK、sim_runner 200 局不变量 0 破坏 |

> 单测里麦子的比例是 2——开局村庄挨着特定型港口。断言按 `Rules` 现算值比对，正好覆盖到这个分支，不是写死数字。

---

## 二、弹窗样式修整（内边距）

鸣叔反馈"弹窗太难看、边缘加点 margin"。**根因不是 margin 没写，而是 `StyleBoxFlat` 的 `content_margin_*` 默认是 0**——`_card_style()` 只画了白底圆角边框，从没设过内容边距，所以内容一直贴着边。

| 改动 | 值 |
|---|---|
| `_card_style(pad: float = 16.0)` | 四边内边距统一 16px，**两个弹窗共用同一份样式** |
| 兑换卡片宽度 | 430 → **470**（把左右内边距算进去，说明文字不被挤）；列间距 12 → 16 |
| 资源按钮内边距 | 8/5 → 10/6 |

顺带修 `shot_dialog.gd`：输出路径写死 macOS 的 `/tmp/`，Windows 上存不了图；改 `user://dlg` 跨平台写法并打印 `globalize_path`，4 张截图全部落盘 PASS。

改动后 `test_trade_dialog` 24/24 复跑通过，「重开一局」弹窗（共用样式）也一并变好看。

---

## 三、沉淀 Godot 使用指南

当日踩的环境坑太多，写成 `docs.ai/rule-godot-命令与验证指南_v1.0.md`（`rule-<主题>_vX.Y.md` 命名）：

| 章节 | 内容 |
|---|---|
| 一、结论先行 | 一张表回答"用什么 exe、在哪跑、改什么跑什么" |
| 二、本机环境 | exe 位置与两个文件的区别；**沙箱限制：exe 必须拷进工作区**；PowerShell 工具为什么不通 |
| 三、首次导入 | 新克隆 / 新增 `class_name` 脚本前必跑 `--import`，附成功判据 |
| 四、命令速查 | headless 类 / 必须渲染类两栏，含 1280×720 硬约束与输出抓取写法 |
| 五、验证三档 | 语法 check-only / 逻辑单测 / 视觉截图，各能验什么、**验不了什么** |
| 六、测试脚本模板 | `extends SceneTree` + `_initialize` + 必须 `quit()` 的完整骨架 |
| 七、踩坑实录 | 共 7 条（见 §五汇总） |
| 八、验收基线 | 各命令的期望输出 |

---

## 四、发展卡交互改造（当日主改动）

### 4.1 需求与结果对照

需求原文（开工前鸣叔补充的**关键澄清**）：**所有功能卡（骑士/修路/丰收/垄断）都能在掷骰前打出**，只受两条硬限——本回合买的不能打、一回合最多 1 张。这条推翻了方案 §7.5 的默认判断（原以为只有骑士可前置），PREROLL 弹窗因此列出全部功能卡。

| # | 需求 | 结果 |
|---|---|---|
| 1 | 掷骰前可打出全部功能卡 | ✅ PREROLL 选卡弹窗列出骑士/修路/丰收/垄断 |
| 2 | 掷骰前出现「掷骰子」「打发展卡」两个按钮 | ✅ 主阶段时「掷骰子」隐藏、建造/交易/结束回合整行隐藏 |
| 3 | 无卡可打则自动掷骰 | ✅ `_begin_next_turn` 里只有"人类且有可打卡"才停在掷骰前 |
| 4 | 打发展卡触发选卡弹窗 | ✅ 一级弹窗，点哪张打哪张 |
| 5 | 骑士 → 地图选强盗，放完**回掷骰前**继续掷 | ✅ `_on_hex_clicked` 按 `dice_rolled` 分流 |
| 6 | 垄断 → 弹窗选资源，显示对手合计 ×N | ✅ 单列，N=0 禁用，tooltip 按对手拆分 |
| 7 | 丰收 → 两列各选 1 张，可相同 | ✅ 两列选同种时要求银行 ≥2 张 |

### 4.2 改动清单

| 文件 | 改动 |
|---|---|
| `core/game_state.gd` | +`dice_rolled: bool`（**不能用 `dice == 0` 判断"还没掷"，上回合值会残留**） |
| `core/game_controller.gd` | `begin_turn` 拆为 `start_turn` + `roll_dice`；`begin_turn` = 两者合体，**RNG 顺序一字未动** |
| `core/rules.gd` | +`monopoly_yield` / `monopoly_breakdown`（纯函数，弹窗显示用；HUD 是哑的拿不到 director，只能走规则层） |
| `game/game_director.gd` | +`S.HUMAN_PREROLL`、`roll_dice_pressed`；`_begin_next_turn` 分流；`_on_hex_clicked` 按 `dice_rolled` 回流；`_on_play_dev` 改接收弹窗参数，**删掉 AI 式代选** `_best_monopoly_resource` / `_two_most_needed` |
| `ui/hud.gd` | 删 `_dev_grid` 按钮排；+「掷骰子」「打发展卡」按钮；+三级弹窗（选卡 / 垄断单列 / 丰收两列）；`play_dev_pressed` 信号改带参 `(card, r, r1, r2)`；`refresh` 增 `main_phase` / `preroll` 参数 |
| `tools/test_interaction.gd` | +PREROLL 分支（先打 1 张再掷骰，防卡死）；+掷骰前统计与硬断言 |
| `tools/test_dev_dialog.gd`（新） | 56 条 headless 单测 |
| `tools/shot_dev_dialog.gd`（新） | 3 张真渲染截图 |

### 4.3 三个关键设计点

1. **回合起点必须拆**：`begin_turn()` 原本一步做完「重置 → 掷骰 → 产出/7」，人类根本没有掷骰前的时机。拆成 `start_turn()` + `roll_dice()` 后，`begin_turn` 保持原语义给 AI / `run()` / `sim_runner` 用，**AI 路径零改动**。
2. **最容易漏的一步**：`_on_hex_clicked` 放完强盗后原本固定跳主阶段；掷骰前打骑士的话必须**回 `HUMAN_PREROLL` 继续掷骰**，否则这回合骰子永远掷不出来。分流依据是 `ctl.st.dice_rolled`。
3. **`main_phase` 与 `preroll` 必须是两个布尔**：掷骰前玩家能操作（打牌）但不能建造/交易/结束回合，一个 `can_act` 表达不了这种"能点一部分"。

### 4.4 验证（全部真跑）

| 项 | 结果 |
|---|---|
| `test_dev_dialog.gd` | **56/56**，含最关键一条：`begin_turn` 与 `start_turn+roll_dice` 的 30 点骰子序列**逐点一致**（RNG 流未变的直接证据） |
| `sim_runner -- 200` | 与改动前基线**逐项一致**：平均轮数 25.1、胜率 8.5 / 22.0 / 47.5%、终局分 5.54 / 6.59 / 8.01、不变量 0 破坏 |
| `test_interaction -- 6000` | PASS；掷骰前窗口出现 6 次、打卡 3 次（骑士 2 次，其后放强盗 2 次——前置链路真实走通） |
| 其余回归 | test_rules 46/46、test_trade_dialog 24/24、test_seed 全过、verify_topology OK |
| 截图 | 3 张弹窗全部居中且在 720 高视口内 |

---

## 五、当日踩坑汇总

全部已补进 `rule-godot-命令与验证指南_v1.0.md`，下表给出**实际所在章节**，方便回查：

| 坑 | rule 文档位置 | 说明 |
|---|---|---|
| Godot 主 exe 与 `_console.exe` 不是一回事 | §2 本机环境 | `_console.exe` 只是 198KB 启动器，单独拷它跑不起来；主 exe 约 180MB |
| 原生 exe 必须拷进工作区才能执行 | §2 本机环境 | 沙箱拦 D 盘 exe；拷进 `E:/project_godot/` 后 bash 可直接跑 |
| PowerShell 工具在本环境不可用 | §2.3 | 不回显 stdout、原生 exe 一律静默拦截（`$LASTEXITCODE` 为空）、cmd.exe 被禁。跑 Godot 走 bash 工具 |
| headless 与渲染类的分界；分辨率必须 1280×720 | §4.2 | 项目 `stretch=canvas_items` + `aspect=expand`，改窗口只缩放不改视口，坐标全对不上 |
| 脚本崩了不 `quit()` 会挂到超时且丢日志 | §4.3 | 排查要去落盘日志找 `SCRIPT ERROR`；管道里的输出会随进程被杀一起丢 |
| `Array[int]` 赋值必须走强类型引用 | §7.1 | 对 `PlayerState.resources` 赋值，经 Variant（`st.players[0]`）会报 Invalid assignment |
| `content_margin` 默认 0 | §7.2 | StyleBoxFlat 不显式设内边距，内容直接贴边框（当日弹窗丑的根因） |
| 隐藏 Control 的 `size` 不可信 | §7.3 | 用 `get_combined_minimum_size()` 兜底，否则居中算偏 |
| UI 截图只挂 HUD，别加载 `main.tscn` | §7.4 | 开局在布置阶段，目标按钮是灰的；背后垫 `ColorRect` 当浅底 |
| lambda 捕获 int 的 `+=` 不写回外层 | §7.5 | 计数断言永远读 0，要用数组或对象成员。单测第一版栽在这里 |
| 无类型 Array 取出的元素没有类型 | §7.6 | `var r1 := _yop_sel[0]` 报 "Cannot infer the type"，必须 `var r1: int = _yop_sel[0]` |
| 弹窗列表重建要用 `remove_child + free` | §7.7 | `queue_free` 等帧末生效，紧接着算卡片居中高度会把"该删的"也算进去 |
| 截图输出路径别写死 `/tmp/` | 修订记录 | macOS 写法，Windows 存不了图；改用 `user://` 跨平台 |

---

## 六、遗留与说明

- **垄断弹窗明示对手手牌合计**（含 tooltip 拆分到每个对手），单机人机按需求接受这点信息泄露；想关掉只需去掉 `×N` 显示与 tooltip，`Rules.monopoly_yield` 保留给禁用判断用。
- **丰收两列选同种时 UI 直接禁掉银行 <2 的资源**，替代"确定后静默发不出第二张"。
- `test_interaction` 的 `_preroll_step` 每回合抢打 1 张卡再掷骰，既覆盖新链路又保证不卡死（`dev_played_this_turn` 兜底）。
- 工作区根目录留了两个 Godot exe（约 180MB + 198KB）和 6 张截图，是跑验证必需的产物，不是垃圾文件。
- `AGENTS.md` 已同步：命令清单（4 个新脚本）、Definition of done（test_trade_dialog 24 条 / test_dev_dialog 56 条）、架构契约第 4 条改为 `start_turn` + `roll_dice` 且强调"改动必须保证 RNG 顺序不变"。
