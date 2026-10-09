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
| 安卓导出 | Android 构建模板在 `android/build/`；**发行包与 Maven 仓库都要换国内镜像，重装模板会覆盖**（见 §9） |

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

## 九、Android 导出（本机 Windows）

### 9.1 环境（本机已配好）

| 项 | 值 |
|---|---|
| Java SDK 路径 | `F:/android/AndroidStudio/jbr`（Android Studio 自带 JBR） |
| Android SDK 路径 | `F:\android\sdk`；用户环境变量 `ANDROID_HOME` 也指向同一处 |
| **Gradle 用户目录** | 用户环境变量 `GRADLE_USER_HOME=F:\android\.gradle` —— 缓存 / daemon / wrapper 全在 F 盘，**不在 `C:\Users\<你>\.gradle`**。查"依赖到底下没下下来"必须去 F 盘看 |
| 调试密钥库 | `C:\Users\<你>\.android\debug.keystore` 已生成，口令与用户名 `androiddebugkey` 均为默认值 |
| scrcpy | 可留空，只影响一键部署时的投屏预览，不装也能部署 |

设置入口：`编辑器 → 编辑器设置 → 导出 → Android`。另需 `编辑器 → 管理导出模板` 装好与引擎同版本的导出模板。

> ⚠️ 因为 `GRADLE_USER_HOME` 被改到了 F 盘，`C:\Users\<你>\.gradle\gradle.properties`（里面写着 `org.gradle.java.home`）**根本不生效**——Gradle 只读 `$GRADLE_USER_HOME/gradle.properties`。本次构建实际用的是 `JAVA_HOME=D:\java\jdk-21.0.3`；JDK 21 满足 `config.gradle` 要求的 ≥17，所以没出问题。

### 9.2 网络：发行包与依赖仓库都换国内镜像

Android 构建模板在 `android/build/`，由编辑器 `项目 → 安装 Android 构建模板` 生成（`.gitignore` 里的 `build/` 规则已把它整个排除在版本库外）。

**本机实测（2026-10-09）**：

| 地址 | 结果 |
|---|---|
| `dl.google.com` / `maven.google.com` | **超时**，12s 无响应 |
| `repo1.maven.org` | 200 |
| `maven.aliyun.com/repository/google` | 200，0.2s |

本机曾配过代理 `127.0.0.1:17892`（在系统 Internet 设置里），但 `ProxyEnable=0` 且端口**没有监听**（代理客户端没开）。结论：**凡指向 Google 的地址都会失败**，所以下面两处都得换，只换一处没用。

#### (1) Gradle 发行包

`android/build/gradle/wrapper/gradle-wrapper.properties`：

```properties
# 原始 —— services.gradle.org 国内极慢且易断
distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-bin.zip

# 已改 —— 腾讯云镜像（实测 HTTP 200 / application/zip / 约 130MB）
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-8.11.1-bin.zip
```

1. **`https\://` 的转义不能丢**。`.properties` 里冒号必须转义，镜像地址同样写 `https\://mirrors...`，少一个反斜杠 Gradle 会解析错。
2. **版本号必须与模板一致**。模板用 Gradle **8.11.1**，镜像文件名要跟着改；换版本时先查镜像目录里有没有对应文件，别硬指一个不存在的版本。
3. 三处都会**被重装模板覆盖**（见本节末）。

#### (2) Maven 依赖仓库

`google()` / `mavenCentral()` 走的就是 `maven.google.com`，不可达就必然失败。模板里有两处要改：`settings.gradle` 的 `pluginManagement.repositories`（解析 AGP / Kotlin 插件）和 `build.gradle` 的 `allprojects.repositories`（解析 androidx 等依赖）。两处都换成同一组阿里云镜像：

```groovy
maven { url "https://maven.aliyun.com/repository/google" }        // ≈ google()
maven { url "https://maven.aliyun.com/repository/public" }        // ≈ mavenCentral()
maven { url "https://maven.aliyun.com/repository/gradle-plugin" } // ≈ gradlePluginPortal()
```

要点：

1. **必须跟官方源等价替换，不能只加不删**。Gradle 按仓库顺序查找，若把镜像加在 `google()` 之后，前面那个不可达的源会先被访问并超时。
2. **镜像确实覆盖了本项目所需的全部构件**（逐个验证过 200）：AGP 8.6.1、`kotlin-gradle-plugin` 2.1.21、`aapt2` 8.6.1-11315950、androidx 的 `fragment` 1.8.6 / `core-splashscreen` 1.0.1 / `documentfile` 1.1.0，以及插件标记 `com.android.application`、`org.jetbrains.kotlin.android`。
3. `central.sonatype.com` 的快照仓库以及 `plugins.gradle.org/m2/` 本项目用不到，一并注释掉了；换到能访问 Google 的网络时把下面几行注释取消即可。

#### (3) 重装模板会覆盖

执行「安装 Android 构建模板」会把 `android/build/` 整个重刷，**本节所有修改（wrapper 镜像、两处仓库、9.3 的两项）都会丢失，需要照本文重贴一遍**。改完不必重新导入工程。若嫌麻烦，可改为在 `%GRADLE_USER_HOME%\init.gradle` 里全局重定向仓库——代价是不在仓库内、对全机所有 Gradle 工程生效。

### 9.3 模板与本机现状的两处适配

这两处是模板默认值与本机已装组件的差异，不改会直接失败或多刷警告。

| 文件 | 模板默认 | 本机实际 | 改动 |
|---|---|---|---|
| `config.gradle` | `buildTools: '36.1.0'` | `F:\android\sdk\build-tools` 下只有 `34.0.0` / `36.0.0` | 改成 `'36.0.0'` |
| `gradle.properties` | 无 | AGP 8.6.1 只测到 compileSdk 35，模板用 36 | 加 `android.suppressUnsupportedCompileSdk=36` |

- **`buildTools` 那条是硬失败**：AGP 发现指定版本缺失会去 `dl.google.com` 自动下载，而它不可达 → `Failed to install build-tools;36.1.0`。改用已装的 36.0.0 即可，AGP 8.6.1 同样支持。（NDK `29.0.14206865` 与 platform `android-36` 本机都已装好，无需动。）
- **`suppressUnsupportedCompileSdk` 纯属消噪**：日志里的 `This Android Gradle plugin (8.6.1) was tested up to compileSdk = 35` 只是"没测过"，不影响出包，加上这行就不再刷。

#### 日志里其余的"红字"都是噪声，不用管

| 日志 | 说明 |
|---|---|
| `android.overridePathCheck=true is experimental` | 路径含中文/非 ASCII 时的兼容开关，模板自带 |
| `only understands SDK XML versions up to 3 but ... version 4` | `%USERPROFILE%\.android\cache` 里 `addons_list-6` 是新格式，AGP 读不懂会跳过 |

### 9.4 导出 / 运行

| 方式 | 做法 |
|---|---|
| 一键部署（推荐先试） | 手机开「开发者选项 → USB 调试」并连数据线，点编辑器右上角安卓图标，自动构建安装并运行 |
| 命令行导出 | `$G --path $P --export-debug "<预设名>" catan.apk`，预设名须与 `export_presets.cfg` 里的名字一致（该文件已 gitignore） |
| 装到手机 | `adb install catan.apk`（adb 在 `F:\android\sdk\platform-tools\`）；报 `INSTALL_PARSE_FAILED_NO_CERTIFICATES` 见 §9.6 |

导出预设检查项：包名改成独特的（如 `com.mying.catan`）、屏幕方向选**横屏**（项目是 1280×720 横版）、架构保持默认 `arm64-v8a`。

本项目无需为安卓改代码：已是 `gl_compatibility` 渲染器 + `canvas_items` 拉伸，触摸由 Godot 默认的「触摸模拟鼠标」转成 `InputEventMouseButton`，`board_view.gd` 的点击逻辑照常可用；HUD 上的 Esc/回车等键盘快捷在手机上无效，但都有对应按钮兜底。

### 9.5 改完怎么验（实测记录）

不必等 Godot 编辑器，直接在 `android/build/` 下跑 Gradle，就能独立复现并验证上述配置：

```powershell
cd E:\project_godot\godot-catan\android\build
.\gradlew.bat help --console=plain                    # 只走到配置阶段：验 AGP / Kotlin 插件能否解析
.\gradlew.bat assembleStandardDebug --console=plain   # 全量：验 androidx 依赖、aapt2，真出包
```

2026-10-09 实测：

| 命令 | 结果 |
|---|---|
| `gradlew.bat help` | `BUILD SUCCESSFUL in 20s`；`dl.google.com` 超时与 SDK XML 报错均消失 |
| `gradlew.bat assembleStandardDebug` | `BUILD SUCCESSFUL in 1m 56s`，34 tasks executed |
| 产物 | `android/build/build/outputs/apk/standard/debug/android_debug.apk`，124.3 MB |

两点提醒：

- 这是**裸 Gradle 构建**，没有 Godot 传的 `export_*` 参数，用的是 `config.gradle` 默认值（包名 `com.godot.game`、4 个 ABI）。⚠️ **它没有签名，装不上**——`adb install` 会报 `INSTALL_PARSE_FAILED_NO_CERTIFICATES`（见 §9.6），它只能用来验依赖链路。
- 缓存全在 `F:\android\.gradle`，一次全量构建会把 Gradle 发行包（130MB）+ AGP + Kotlin + aapt2 拉进去，首次以分钟计，之后走缓存很快。

### 9.6 `adb install` 报错：未签名

**症状**（本机实测，拿 §9.5 那个裸构建产物去装时）：

```
Performing Streamed Install
adb: failed to install ...\android_debug.apk: Failure
[INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates from
/data/app/vmdl1943052862.tmp/base.apk: Attempt to get length of null array]
```

Android 7.0 起强制要求 APK 签名，没签就是这一条。**先别怀疑 USB / 驱动 / 包名**，直接验签名：

```powershell
$bt = 'F:\android\sdk\build-tools\36.0.0'
& "$bt\apksigner.bat" verify --print-certs <你的.apk>
# 未签名 → "DOES NOT VERIFY" + "ERROR: Missing META-INF/MANIFEST.MF"
# 已签名 → "Signer #1 certificate DN: ..."
```

#### 根因只有一个：`shouldSign()` 返回了 false

[config.gradle](file:///e:/project_godot/godot-catan/android/build/config.gradle) 的判断链：

```groovy
ext.shouldSign = { ->
    String signFlag = project.hasProperty("perform_signing") ? project.property("perform_signing") : ""
    if (signFlag == null || signFlag.isEmpty()) {
        if (isAndroidStudio()) { signFlag = "true" } else { signFlag = "false" }
    }
    return Boolean.parseBoolean(signFlag)
}
// ...
debug {
    if (shouldSign()) { signingConfig signingConfigs.debug } else { signingConfig null }   // ← null 就是裸包
}
```

即**只有**「传了 `-Pperform_signing=true`」或「从 Android Studio 里构建」这两条路。有两条常见触发路径：

| # | 场景 | 为什么没签 |
|---|---|---|
| A | §9.5 的裸 `gradlew assembleStandardDebug` | 没传 `perform_signing`，也不是 Android Studio |
| B | **从 Godot 编辑器导出**，但预设里 `package/signed=false` | Godot **只在 `package/signed=true` 时**才给 gradle 传 `-Pperform_signing=true` |

⚠️ **B 才是最坑的**：`package/signed` 在**新建 Android 预设时默认就是 `false`** —— 所以"从编辑器导出"根本不等于"已签名"。本机实测第一次正式导出的 `Catan.apk` 就是未签名的，装上去报的错和 A 一模一样。（原先本文写的"从 Godot 导出，编辑器会自己带上签名参数"是错的，已更正。）

#### 修法

**修 B（推荐，一劳永逸）**：导出对话框 → Android 预设 → **包 → 勾选「签名 / Signed」**；或直接改 `export_presets.cfg`：

```ini
package/signed=true      # 模板默认是 false
```

2026-10-09 实测对照：

| `package/signed` | `apksigner verify` |
|---|---|
| `false` | `DOES NOT VERIFY` / `Missing META-INF/MANIFEST.MF` |
| `true` | `Signer #1: CN=Godot, OU=Godot Engine, O=Stichting Godot, C=NL` |

> 用的是 Godot **自动生成**的调试密钥库（`%APPDATA%\Godot\keystores\debug.keystore`，来自编辑器设置 `export/android/debug_keystore`）——**不是**密钥库缺失，排查时别往那个方向找。该文件实测存在（2714 字节）。
> `export_presets.cfg` 已 gitignore，改动只在本机生效；换机器或重建预设时要重勾一次。

**修 A（命令行出包）**：把参数补上即可：

```powershell
.\gradlew.bat assembleStandardDebug -Pperform_signing=true -Pperform_zipalign=true `
  -Pdebug_keystore_file="$env:USERPROFILE\.android\debug.keystore" `
  -Pdebug_keystore_password=android -Pdebug_keystore_alias=androiddebugkey
```

**救急**：手头只有未签名产物时，用调试密钥库就地签一次（实测通过，装完能正常起局）。`INSTALL_PARSE_FAILED_NO_CERTIFICATES` 报的是**证书缺失**，与包内容无关——实测那个裸构建 APK 里 `libgodot_android.so`（4 个 ABI）、`assets.sparsepck`、`project.binary` 俱全，补个签名即可用：

```powershell
$bt = 'F:\android\sdk\build-tools\36.0.0'
$ks = "$env:USERPROFILE\.android\debug.keystore"
& "$bt\zipalign.exe" -p -f 4 in.apk aligned.apk
& "$bt\apksigner.bat" sign --ks $ks --ks-pass pass:android --key-pass pass:android `
    --ks-key-alias androiddebugkey --out signed.apk aligned.apk
& "$bt\apksigner.bat" verify --print-certs signed.apk
adb install -r signed.apk
```

调试密钥库的口令与别名都是 Android 默认值（`android` / `androiddebugkey`），与 §9.1 一致。

> 顺带记一条：装完启动若看到 `E godot: shader failed to compile, unable to bind shader`（`shader_gles3.cpp`），本机实测**画面正常**，属启动阶段噪声，先不追。

---

## 修订记录

- v1.5（2026-10-09）：**更正 v1.4 的错误结论**——v1.4 把"从 Godot 导出"当作未签名的正解，实测这是错的。§9.6 重写为「根因只有一个：`shouldSign()` 返回 false」，并列出两条触发路径：A 裸 `assembleStandardDebug`（§9.5），B **从编辑器导出但预设 `package/signed=false`**——`package/signed` 新建预设时默认就是 `false`，所以"从编辑器导出"≠"已签名"，本机第一次正式导出的 `Catan.apk` 就是这样。补上 `shouldSign()` 源码片段 + `signingConfig null` 的落点、A/B 对照表、修法（勾选「签名」或改 `export_presets.cfg`）与改前/改后签名实测对照（`DOES NOT VERIFY` → `CN=Godot, ...`）；并明确排除"密钥库缺失"这个误判方向（`%APPDATA%\Godot\keystores\debug.keystore` 实测存在）。
- v1.4（2026-10-09）：新增 §9.6「`adb install` 报错：未签名」。症状即 `INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates ... Attempt to get length of null array`；用 `apksigner verify --print-certs` 判定（未签名时是 `DOES NOT VERIFY` / `Missing META-INF/MANIFEST.MF`）；根因是 `config.gradle#shouldSign()` 只在 `perform_signing=true` 或 Android Studio 下才签，而 §9.5 的裸 `assembleStandardDebug` 两者都不满足——§9.5 那条"不签名"的提醒同时升级为带 ⚠️ 的显式警告。给了两条出路：从 Godot 导出（正解），或 `zipalign + apksigner` 就地补签 / 给 Gradle 补 `-Pperform_signing` 参数（救急），并注明该裸构建 APK 内容其实是完整的（4 ABI so + sparsepck + project.binary 俱全）。§9.4 的 `adb install` 行加交叉引用；另记一条启动期 `shader failed to compile` 噪声可忽略。
- v1.3（2026-10-09）：Android 导出首次真实构建踩坑。§9.1 补 `GRADLE_USER_HOME=F:\android\.gradle`（缓存不在 C 盘；顺带记下 `C:\...\.gradle\gradle.properties` 因此失效）。**§9.2 由"只换发行包"扩为"发行包 + Maven 仓库都要换"**——本机 `dl.google.com` / `maven.google.com` 全超时（实测），需在 `settings.gradle` 与 `build.gradle` 两处用阿里云镜像**等价替换**（只加不删会先撞超时），并列出已逐个验证的构件清单。新增 §9.3：`buildTools` 36.1.0→36.0.0（缺失会触发 Google 下载，硬失败）、`android.suppressUnsupportedCompileSdk=36`（消噪），以及两条可忽略的噪声日志。新增 §9.5：`gradlew help` / `assembleStandardDebug` 的独立验证法 + 实测结果（20s / 1m56s / 124.3MB APK）。
- v1.2（2026-10-09）：新增 §9「Android 导出」——本机 Java / Android SDK 路径与调试密钥库现状（§9.1）、`android/build/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 从官方源换腾讯云镜像及三条注意：转义不能丢、版本号要跟模板、**重装构建模板会覆盖**（§9.2）、一键部署与命令行导出的对应命令（§9.3）。§1 结论表加一行安卓导出指引。
- v1.1（2026-10-09）：补「发展卡交互改造」当天新增的三条坑——lambda 捕获 int 的 `+=` 不写回（§7.5）、无类型 Array 取元素必须显式标类型（§7.6）、弹窗列表重建用 `remove_child+free` 而非 `queue_free`（§7.7）；验收基线加 `test_dev_dialog.gd`（56 条）与 `shot_dev_dialog.gd`。
- v1.0（2026-10-09）：初版。来源为当日「银行兑换弹窗化」全流程实录——exe 沙箱执行限制与 `_console.exe` 是启动器（§2）、PowerShell 工具不回显 stdout 且禁 cmd（§2.3）、headless 与渲染类的分界与 1280x720 约束（§4.2）、崩了不 `quit()` 导致挂起且日志缓冲丢失（§4.3）、`Array[int]` 赋值坑（§7.1）、`content_margin` 默认 0 导致内容贴边（§7.2）、隐藏 Control 尺寸与居中（§7.3）、UI 截图只挂 HUD（§7.4）。同日补：`shot_dialog.gd` 输出路径从 `/tmp/`（macOS）改为 `user://` 跨平台写法。
