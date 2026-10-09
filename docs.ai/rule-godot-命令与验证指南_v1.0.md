# Godot 使用指南（本机执行 + 验证流程）

> **本文定位**：`AGENTS.md` 是命令与架构的权威来源（macOS 写法为主），本文补的是**本机 Windows 环境怎么真把这些命令跑起来**——exe 在哪、能不能执行、headless 与渲染类的分界、改完代码该跑哪些、以及今天踩过的坑。
> 性质：长期规范（`rule-`，变体 B）。配套阅读：`AGENTS.md`（命令清单 / 架构契约）、`project-2026.10.8.a.md`（项目落地记录）。

---

## 一、结论先行

| 事项 | 结论 |
|---|---|
| 跑 Godot | **用 bash 工具**，不要用 PowerShell 工具（原因见 §2.3） |
| 用哪个 exe | 主程序 `Godot_v4.7.2-stable_win64.exe`（约 180MB）。`_console.exe` 只有 198KB，是启动器，**单独拷它跑不起来** |
| 新拉代码 / 新增带 `class_name` 的脚本 | 先跑一次 `--import`，否则类解析不到 |
| 语法检查 | `--headless --check-only --script res://ui/hud.gd` |
| 改逻辑 | 跑 headless 单测（见 §4 验收基线） |
| 改 UI 排版 | 必须**真渲染截图**看一眼，headless 验不出排版 |
| 截图类脚本 | **不能加 `--headless`**，且分辨率必须 `--resolution 1280x720` |

---

## 二、本机环境

### 2.1 exe 位置

官方包在 `D:\app\Godot_v4.7.2-stable\`，含两个文件：

| 文件 | 大小 | 说明 |
|---|---|---|
| `Godot_v4.7.2-stable_win64.exe` | 约 180MB | **主程序**，所有命令都用它 |
| `Godot_v4.7.2-stable_win64_console.exe` | 198KB | 启动器，依赖主 exe 同目录；不是独立可执行体 |

### 2.2 沙箱限制：exe 必须拷进工作区

直接跑 `D:\app\...` 会被沙箱静默拦截（表现为**退出码 1、无输出、重定向文件都没建**，`$LASTEXITCODE` 为空）。

**解法**：把**两个** exe 一起拷到 `E:/project_godot/`（只拷 console 那个没用），之后在 bash 里直接跑：

```bash
cd E:/project_godot
./Godot_v4.7.2-stable_win64.exe --version
# 4.7.2.stable.official.ed1daf0bf
```

> 拷进工作区是绕过执行限制，不是项目依赖——这两个 exe 不在 git 里，也不该提交。

### 2.3 为什么不用 PowerShell 工具

本会话实录（与 `rule-powershell-避坑指南` 一致）：

| 现象 | 说明 |
|---|---|
| PowerShell 工具**完全不回显 stdout**（连 `Get-Date` 都看不到） | 只能靠"落盘 + 用 Read 读"间接取结果 |
| 原生 exe 一律静默拦截 | `$LASTEXITCODE` 为空，退出码 1，输出文件不创建 |
| `cmd.exe` 被工具直接禁止 | 报 "cmd.exe cannot be used from the PowerShell tool" |
| bash 工具执行同路径 exe 报 `No such file or directory`（exit 127） | 同样是执行拦截，不是文件不存在（`ls` 能列出） |

结论：**Godot 相关命令一律走 bash 工具**，输出用 `2>&1 | tail -N` 看；长任务用 `> file.log 2>&1` 落盘再读。

---

## 三、首次导入（新增脚本前必做）

`.godot/` 目录不存在时（新克隆、或换机器），必须先导入一次，注册 `class_name` 全局类表：

```bash
cd E:/project_godot
./Godot_v4.7.2-stable_win64.exe --headless --path E:/project_godot/godot-catan --import
```

判据：输出出现 `reimport` / `loading_editor_layout` 两段的 `[ DONE ]`，退出码 0。之后新增带 `class_name` 的脚本也要再导一次。

---

## 四、命令速查

### 4.1 可 headless 跑（快，无渲染）

```bash
cd E:/project_godot   # 后续命令都在这个目录，exe 已拷到这里
G=./Godot_v4.7.2-stable_win64.exe
P=E:/project_godot/godot-catan

$G --headless --path $P --import                                    # 导入 / 注册 class_name
$G --headless --path $P --check-only --script res://ui/hud.gd       # 只做语法编译检查
$G --headless --path $P --script res://tools/verify_topology.gd     # 几何断言
$G --headless --path $P --script res://tools/test_rules.gd          # 规则单测 46 条
$G --headless --path $P --script res://tools/test_trade_dialog.gd   # 兑换弹窗单测 24 条
$G --headless --path $P --script res://tools/test_seed.gd           # 种子与号码分布
$G --headless --path $P --script res://tools/sim_runner.gd -- 200   # 批量对局 + 不变量
```

`sim_runner.gd` 第二参数：`h2h`（1 困难 vs 3 中等）/ `v`（verbose 单局）。跑 500 局耗时较长，日常回归用 200 足够。

### 4.2 必须真渲染（不能 `--headless`）

```bash
$G --path $P --resolution 1280x720 --script res://tools/shot_dialog.gd
$G --path $P --resolution 1280x720 --script res://tools/shot_trade_dialog.gd
$G --path $P --resolution 1280x720 --script res://tools/screenshot.gd -- res://scenes/main.tscn /tmp/board.png 30 auto
$G --path $P --resolution 1280x720 --script res://tools/test_interaction.gd -- 6000
$G --path $P                                                        # 直接跑游戏
```

| 约束 | 原因 |
|---|---|
| 去掉 `--headless` | headless 下 `RenderingServer.frame_post_draw` / `root.get_texture()` 拿不到画面，脚本会挂住被 kill（exit 137） |
| 分辨率必须 `1280x720` | 项目 `stretch=canvas_items` + `aspect=expand`，改窗口只缩放不改视口，坐标全对不上 |
| 脚本内的输出路径用 `user://` | `AGENTS.md` 里 `screenshot.gd` 示例用的 `/tmp/board.png` 是 macOS 写法；**写死 `E:/xxx` 更糟**——别人 clone 后没有 E 盘，`save_png` 直接失败。仓库内的 `shot_dialog.gd` / `shot_trade_dialog.gd` / `shot_dev_dialog.gd` 统一用 `user://`，并 `print(ProjectSettings.globalize_path(path))` 打印真实位置 |

### 4.3 输出怎么抓

| 场景 | 写法 | 说明 |
|---|---|---|
| 看末尾几行 | `... 2>&1 \| tail -15` | 日常够用 |
| 长任务 | `... > x.log 2>&1`（相对当前目录，别写死盘符），再用 Read 读 | 200 局模拟、截图脚本 |
| ⚠️ 脚本崩了又不 `quit()` | 会一直挂到超时被 SIGTERM，**stdout 缓冲丢失** | 此时看落盘的 log 文件，里面通常有 `SCRIPT ERROR` 与堆栈 |

---

## 五、验证三档（按改动类型选）

| 档 | 命令 | 能验什么 | 验不了什么 |
|---|---|---|---|
| 1. 语法 | `--check-only --script <文件>` | 解析/编译错误 | 任何运行时行为 |
| 2. 逻辑 | headless 单测（`tools/test_*.gd`） | 规则、信号、按钮可用态、状态机 | 排版、居中、颜色、可见性 |
| 3. 视觉 | 真渲染截图脚本 | 卡片是否居中、有没有超出视口、高亮是否生效 | 逻辑正确性 |

**改 UI 的正确姿势**：三档都过。第 3 档别省——`_center_card` 用隐藏态 `card.size` 算高度这类问题，单测查不出来，只有渲染后看 `pos/size` 和截图才暴露。

---

## 六、新增 `tools/*.gd` 测试脚本的模板

项目约定：`extends SceneTree` + `_initialize()` + 结束必须 `quit()`。

```gdscript
extends SceneTree

var _pass := 0
var _fail := 0

func _initialize() -> void:
	print("=== xxx 单元测试 ===")
	_run_tests.call_deferred()   # 需要 await 帧时走延迟调用

func _run_tests() -> void:
	for i in 3:
		await process_frame        # 等 _ready 里的 await 落地
	# ... 断言 ...
	print("通过 %d · 失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)   # 不调 quit 会挂到超时被 kill

func _ok(cond: bool, name: String, detail: String = "") -> bool:
	if cond:
		_pass += 1
		print("  [ok]   %s" % name)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])
	return cond

# 造局面的标准套路（照抄 test_rules.gd）
func _fresh_game(n: int, seed_value: int) -> GameController:
	var configs: Array = []
	var providers: Array = []
	for i in n:
		configs.append({"is_ai": true, "difficulty": 1})
		providers.append(AIMedium.new(i))
	var ctl := GameController.new()
	ctl.new_game(configs, seed_value, true, providers)
	return ctl
```

截图脚本另需：`RenderingServer.frame_post_draw.connect(_on_frame)` 驱动分步动作，用 `root.get_texture().get_image().save_png(path)` 存图。路径用 `const OUT := "user://xxx"`（跨平台、不污染仓库），**不要写死盘符路径**；日志里打印 `ProjectSettings.globalize_path(path)` 方便找图。

---

## 七、踩坑实录

### 7.1 GDScript：类型化数组属性必须走强类型引用

`PlayerState.resources` 声明为 `Array[int]`。经 Variant 赋值**不做隐式转换**：

```gdscript
st.players[0].resources = [4, 3, 0, 0, 0]      # ✗ Invalid assignment ... type 'Array'
var p0: PlayerState = st.players[0]
p0.resources = [4, 3, 0, 0, 0]                 # ✓
```

症状：脚本在第一行赋值就崩，又因 `quit()` 未执行而挂到超时——排查时**先去落盘日志里找 SCRIPT ERROR**。

### 7.2 StyleBoxFlat 的 content_margin 默认是 0

不显式设 `content_margin_*`，PanelContainer 的内容会**直接贴着边框**，看上去像没做排版。弹窗卡片统一走 `_card_style(pad)` 设内边距（两个弹窗共用一份，改一处即可）。同样注意：加内边距后卡片宽度要把左右 padding 算进去，否则说明文字被挤到换行溢出。

### 7.3 隐藏 Control 的 size 不可信

浮层/弹窗默认 `visible=false`，取到的 `size` 可能是 0，按它算居中会错。用最小尺寸兜底：

```gdscript
var h := maxf(maxf(card.size.y, card.get_combined_minimum_size().y), 150.0)
card.size = Vector2(width, h)
card.position = ((vp - card.size) * 0.5).round()
```

另：`CenterContainer` 会把子节点压到最小尺寸导致内容被挤没；`anchor=0.5 + grow_offsets` 在普通 Control 父节点下不生效——老老实实按视口算左上角。

### 7.4 只挂 HUD 做 UI 截图，别加载 main.tscn

`main.tscn` 开局处于布置阶段，目标按钮（如「兑换」）是灰的，得先摆完房子。UI 截图脚本直接 `root.add_child(HUD.new())` + 造一个局面喂 `refresh()` 即可，快且可控；背后加一个 `ColorRect` 当浅底，否则截出来大片透明。

### 7.5 GDScript lambda 捕获的 int：`+=` 不写回外层

```gdscript
var rolled := 0
sig.connect(func(): rolled += 1)   # ✗ 断言里永远读到 0
```

lambda 捕获标量后，`+=` 改的是闭包内的值，外层变量不变。要计数就用容器：`var rolled := [0]` + `rolled[0] += 1`（修改容器内容是共享的）。

### 7.6 无类型 Array 取出的元素没有类型

```gdscript
var sel := [-1, -1]          # 无类型 Array
var r1 := sel[0]             # ✗ Parse Error: Cannot infer the type
var r1: int = sel[0]         # ✓ 显式标类型
```

同理，遍历无类型 Array 时 `var card: Control = c` 先落类型再做算术，否则 `(vp.x - card.size.x)` 这类表达式全报 "Cannot infer the type"。

### 7.7 弹窗列表重建要用 remove_child + free，别用 queue_free

`queue_free` 要等这一帧结束才生效；重建列表后紧接着算卡片高度做居中，那些"该删掉"的按钮还挂在树上，高度按旧的算，居中就偏了。`box.remove_child(c); c.free()` 立即生效（只要不在该节点的信号回调里 free 它自己就安全）。

---

## 八、验收基线（改完必须绿）

| 命令 | 期望输出 |
|---|---|
| `verify_topology.gd` | `TOPOLOGY OK` |
| `test_rules.gd` | `通过 46 · 失败 0` / PASS |
| `test_trade_dialog.gd` | `通过 24 · 失败 0` / PASS |
| `test_seed.gd` | 全部通过 |
| `sim_runner.gd -- 200` | `不变量：棋盘异常 0 · 资源守恒破坏 0 · 状态完整性破坏 0` + `M1 验收结果：PASS` |
| `test_interaction.gd -- 6000` | `M2 验收结果：PASS`（需渲染） |
| `test_dev_dialog.gd` | `通过 56 · 失败 0` / PASS |
| `shot_dialog.gd` / `shot_trade_dialog.gd` / `shot_dev_dialog.gd` | `--- 结果：PASS ---`（需渲染） |

改了规则引擎或 AI，还要**报数字**（胜率、违规计数），不能只说"跑通了"。

---

## 修订记录

- v1.1（2026-10-09）：补「发展卡交互改造」当天新增的三条坑——lambda 捕获 int 的 `+=` 不写回（§7.5）、无类型 Array 取元素必须显式标类型（§7.6）、弹窗列表重建用 `remove_child+free` 而非 `queue_free`（§7.7）；验收基线加 `test_dev_dialog.gd`（56 条）与 `shot_dev_dialog.gd`。
- v1.0（2026-10-09）：初版。来源为当日「银行兑换弹窗化」全流程实录——exe 沙箱执行限制与 `_console.exe` 是启动器（§2）、PowerShell 工具不回显 stdout 且禁 cmd（§2.3）、headless 与渲染类的分界与 1280x720 约束（§4.2）、崩了不 `quit()` 导致挂起且日志缓冲丢失（§4.3）、`Array[int]` 赋值坑（§7.1）、`content_margin` 默认 0 导致内容贴边（§7.2）、隐藏 Control 尺寸与居中（§7.3）、UI 截图只挂 HUD（§7.4）。同日补：`shot_dialog.gd` 输出路径从 `/tmp/`（macOS）改为 `user://` 跨平台写法。
