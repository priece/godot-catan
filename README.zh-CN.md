# 卡坦岛 · Godot 人机对战

用 **Godot 4.7 / GDScript** 实现的单机**卡坦岛（基础版）**。你与 2–3 个电脑对手对战，
三档难度可混排。不做联网，无任何外部依赖。

[English →](README.md)

![棋盘预览](docs/board_preview.png)

---

## 亮点

- **规则层与渲染层彻底解耦。** `core/` 下全部是 `RefCounted`，不依赖节点与 UI，
  因此可以在无头模式下跑几万局批量对局——AI 的强度用胜率矩阵验证，而不是拍脑袋。
- **三档 AI 真有区别。** 难度差异来自决策质量（评分噪声、前瞻、阻断对手、交易评估、
  强盗打击、弃牌精算），而不是把某个数值调大调小。
- **人类与 AI 共用同一条代码路径。** 两边都实现 `IntentProvider` 接口，
  所以"界面里能玩的"和"批量验收跑的"永远不会跑偏。
- **岛屿生成遵循官方规则。** 6 和 8 从不相邻、相邻地块不同数字——不多不少，就是官方 Almanac 的要求。
- **完整可玩的界面**：手绘六边形棋盘 + 地形插画、点击即建、合法性与买得起双重高亮、
  银行交易、发展卡、全量不截断的事件日志、可选种子的重开面板。

| 初始布置 | 对局中 | 结算 |
|---|---|---|
| ![布置](docs/gameplay_setup.png) | ![对局](docs/gameplay_turn.png) | ![结算](docs/gameplay_over.png) |

---

## 功能一览

| 模块 | 已实现 |
|---|---|
| 玩家 | 1 人类 + 3 电脑（每座位可配难度），预留 5–6 人扩展接口 |
| 棋盘 | 19 地块（森林 / 丘陵 / 牧场 / 麦田 / 山脉 / 沙漠）、54 顶点、72 边 |
| 资源 | 木材、砖块、羊毛、麦子、矿石 |
| 建造 | 道路、村庄、城市、发展卡 |
| 特殊分 | 最长道路（+2）、最大军队（+2） |
| 机制 | 强盗与偷牌、掷 7 弃牌、港口交易（3:1 / 2:1）、玩家间交易 |
| 胜利 | 在自己的回合率先达到 10 分 |
| 界面 | 地形插画棋盘、点击即建、合法+买得起高亮、银行交易网格、发展卡面板、全量事件日志、种子重开面板 |
| 工具链 | 几何断言、规则单测、批量对局、种子测试、渲染截图、模拟点击验收 |

**尚未实现**（见[开发进展](#开发进展)）：玩家间交易界面、弃牌 / 垄断 / 丰收年由玩家自选、
动画与音效、教程、存档回放、设置页。

---

## 环境要求

- **Godot 4.7**（开发环境为 4.7.2 stable）。标准版即可，不需要额外模块或插件。
- 使用 `gl_compatibility` 渲染后端，集显与较老的机器也能跑。

---

## 快速开始

```bash
git clone git@github.com:priece/godot-catan.git
cd godot-catan
```

用 Godot 导入 `project.godot` 打开项目，直接按 **F5** 运行即可——
主场景已写入 `run/main_scene`，不需要额外配置。

也可以命令行启动：

```bash
# macOS
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Linux / Windows
godot --path .
```

首次启动会花一点时间导入地形贴图。

---

## 怎么玩

**初始布置阶段。** 依次放置两座村庄和两条道路。合法位置会有高亮：
点高亮的**顶点**放村庄，点高亮的**边**修道路。

**轮到你时。** 骰子是自动掷的。之后可以：

| 操作 | 怎么做 |
|---|---|
| 修路 | 点高亮的边 |
| 建村庄 | 点高亮的顶点 |
| 升级城市 | 点自己已有的村庄 |
| 买发展卡 | **买发展卡** 按钮 |
| 打出发展卡 | **发展卡** 面板里点对应按钮 |
| 银行 / 港口交易 | **银行交易** 网格，点一下即完成交换 |
| 结束回合 | **结束回合** 按钮 |
| 移动强盗 | 掷出 7 或打出骑士后，点目标地块 |
| 换一张棋盘重开 | **重开一局** → 输入或选种子 → **确定** |

右侧面板依次列出每位玩家的名字、分数、资源数量与当前状态，下面是**事件日志**。
日志**从不截断**——本次会话开始以来的每一条都保留，标题上显示累计条数。

**几点说明。** 青色边框表示"既合法又买得起"（只判合法是不够的，可能点下去钱不够）。
按 **Esc** 关闭重开面板。重开面板的输入框只收数字：输入种子后按回车或点**确定**；
**随机一局** / **沿用本局** 是两个快捷方式。

---

## 电脑对手

三档难度，各座位可自由混排。差异体现在行为，而不是数值：

| 决策点 | 简单 | 标准 | 困难 |
|---|---|---|---|
| 初始放置 | 评分 + 大噪声，20% 纯随机 | 纯评分最优 | 评分 + 阻断对手关键点 + 港口 + 前瞻 |
| 建造优先级 | 可负担集合里随机 | 按分数效率：城 > 村 > 发展卡 > 路 | 多步规划，锁定冲最长路 / 最大军队 |
| 资源管理 | — | 维持建造所需平衡 | 精算缺口，为冲刺预留资源 |
| 玩家间交易 | 50% 随机接受 | 等价评估，接受利己交易 | 主动套利，识别对手缺口，绝不资敌 |
| 强盗放置 | 随机地块 | 对手的高产出地块 | 精准打击领先者，封锁其关键数字 |
| 偷牌对象 | 随机 | 手牌最多的玩家 | 分数最高 / 疑似囤牌的玩家 |
| 弃牌 | 随便弃 | 弃最不急需的 | 保住建造组合 |

困难 AI 每回合还会判定**制胜路线**——铺路流（最长路是最常见的制胜路径）、
发展卡流、扩张流（第 3 座村庄的建成时间与胜负相关性最强）——并随对手拿到奖励而动态修正。

因为规则引擎能无头运行，AI 强度是可以量化的：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/sim_runner.gd -- 500
```

它会打印按难度分组的胜率矩阵，并对每一局强制校验两条不变量：
**资源守恒**（银行 + 所有玩家 = 每种资源恒 19 张）与**状态完整性**。

---

## 岛屿生成

生成规则遵循**官方 CATAN Almanac**（"Number Tokens – Fully-Random" 一节）：

- 地形地块**洗牌后随机摆放**——官方规则书对地形/资源的相邻关系**没有任何限制**。
- **6 和 8 不能相邻。** 两者各 5 pip，两个红数字挨在一起会形成一个能在前三回合就决定胜负的产区。
  这条**任何模式下都必须满足**。
- **相邻两个地块不能是同一个数字**（均衡模式）。

生成使用拒绝采样，并且**失败会显式报错**（`push_error`），绝不静默产出一张违规的盘。
这条规则另有 `Board.self_check()` 兜底（每局批量对局都会调用），以及 `tools/test_seed.gd` 的专门断言。

棋盘是确定性的：同一个种子必然生成同一座岛。可以在重开面板里改种子，
也可以在检查器里改 `BoardView` / `GameDirector` 上的 `seed_value`。

---

## 项目结构

```
core/     纯逻辑层——不依赖 Node/UI，可在无头模式下运行
          hex_grid.gd · board_topology.gd · board.gd · game_state.gd · player_state.gd
          game_controller.gd · rules.gd · longest_road.gd · resources.gd
ai/       ai_base.gd · evaluation.gd · ai_easy.gd · ai_medium.gd · ai_hard.gd
game/     game_director.gd（回合与交互调度）· intent_provider.gd · human_intent.gd
ui/       board_view.gd（_draw 手绘棋盘）· hud.gd（全代码搭建的面板）· palette.gd
scenes/   main.tscn
tools/    8 个命令行脚本：测试、批量对局、截图
assets/   terrain/（游戏用的缩略图）· terrain_src/（原图，不让 Godot 导入）
docs/     预览图与对局截图
```

### 验证工具

| 脚本 | 可 headless | 用途 |
|---|---|---|
| `verify_topology.gd` | 是 | 断言 19 地块 / 54 顶点 / 72 边及度数分布 |
| `test_rules.gd` | 是 | 46 项规则单元测试 |
| `test_seed.gd` | 是 | 种子解析 + 官方数字摆放规则 |
| `sim_runner.gd` | 是 | 批量对局、胜率矩阵、守恒不变量 |
| `screenshot.gd` | **否** | 渲染棋盘到 PNG，含自检 |
| `shot_dialog.gd` | **否** | 驱动重开面板并截图 |
| `test_interaction.gd` | **否** | 模拟人类点击打完整局（M2 验收） |

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://tools/verify_topology.gd
$GODOT --headless --path . --script res://tools/test_rules.gd
$GODOT --headless --path . --script res://tools/test_seed.gd
$GODOT --headless --path . --script res://tools/sim_runner.gd -- 500

# 以下三个**不能**加 --headless，且必须带 --resolution 1280x720
$GODOT --path . --resolution 1280x720 --script res://tools/test_interaction.gd -- 6000
$GODOT --path . --resolution 1280x720 --script res://tools/shot_dialog.gd
$GODOT --path . --resolution 1280x720 --script res://tools/screenshot.gd -- \
    res://scenes/main.tscn /tmp/board.png 30 auto
```

如果你是 AI 助手或新加入的贡献者，请先读 **[AGENTS.md](AGENTS.md)**（英文）——
里面写了架构铁律、编码约定，以及一份**已经在本项目里真实踩过的 Godot 坑清单**
（主题覆盖静默失效、程序化赋值不触发 `text_changed`、`--resolution` 不改视口、
`--headless` 下 `frame_post_draw` 卡死等等）。

---

## 开发进展

**已完成**：P0 脚手架 · P1 棋盘拓扑 · P2 规则引擎 · P3 AI 三档 · P4 棋盘渲染 · P5 玩家交互。

**已达成的里程碑**：**M1** —— 规则引擎（可批量跑对局且无非法状态）；
**M2** —— 人类能完整打完一局（对手为 3 个电脑）。

**待做（M3）**：玩家间交易界面、弃牌 / 垄断 / 丰收年由玩家自选、动画与音效、
教程、存档与回放、设置页。

完整设计方案与验收数据见 **[DESIGN.md](DESIGN.md)**。

---

## 许可

项目目前**没有添加许可证文件**，因此默认保留所有权利。如果希望复用，欢迎先开 issue 沟通。

*「卡坦岛 / Catan」是 CATAN GmbH 的商标。本项目为非官方、非商业的爱好者实现。*
