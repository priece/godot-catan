# 2026-10-09 开屏（splash）改造（a）：引擎启动画面换成海岛图 + Android 12 安全区圆形图标

> 与 `project-2026.10.9.a.md` 的关系：那篇是当日四块**交互**改造的落地归档，本文是同日另一条独立线——**启动画面**。
> 与 `rule-godot-命令与验证指南_v1.0.md` 的关系：那篇讲"怎么跑 Godot 验证"，本文只讲"开屏改了什么、为什么、怎么证明没改坏"。
> **本次未导出 APK**（按需求只改资源与配置，真机效果待下次导出后确认）。

---

## 零、要点速览

**现象**：APK 启动时先出现一个**被放大的 logo**，紧接着又出现 **Godot 机器人图标**，然后才进游戏。

**根因**：这是**两层互相独立**的开屏，由完全不同的地方控制，改一处不会影响另一处。

| 顺序 | 画面 | 谁画的 | 由谁控制 |
|---|---|---|---|
| ① | 被放大的 App 图标 | **Android 系统**（Android 12+ 强制插一层） | 导出预设 `splash_screen/icon`；为空时按回落链 → `launcher_icons/adaptive_foreground` → `launcher_icons/main` → 项目 `application/config/icon` |
| ② | Godot 机器人 logo | **Godot 引擎** | 项目设置 `application/boot_splash/*`；原项目这三项一个都没写，引擎回落到**编译进引擎的内置 logo** |
| ③ | 游戏主场景 | 项目自身 | `run/main_scene` |

**改动落点**：

| # | 改动 | 文件 | 是否入库 |
|---|---|---|---|
| 一 | 资源拼写修正：`logo_slash.png` → `logo_splash.png` | `assets/` | ✅ |
| 二 | 引擎开屏换成海岛整图 + 同色背景 | `project.godot` | ✅ |
| 三 | 新增 Android 12 安全区圆形图标（派生资源） | `assets/logo_splash_icon.png` | ✅ |
| 四 | Android 导出预设两项（见第四章） | `export_presets.cfg` | ❌（该文件被 `.gitignore` 忽略） |

---

## 一、资源改名（拼写修正）

`assets/logo_slash.png` → `assets/logo_splash.png`（`slash` 是笔误，应为 `splash`）。

处理细节：

- 同时改名 `.import` 文件，并把其中的 `path` / `source_file` / `dest_files` 三处路径一起改掉；
- 跑 `--headless --import` 重新导入后，Godot 按新文件名重新算了缓存哈希（`logo_splash.png-d43d4143….ctex`），并**回写**了 `.import`；
- 旧缓存 `.godot/imported/logo_slash.png-*.ctex` / `.md5` 已删除；全仓 grep `logo_slash` 已无残留。

> 原图规格：**500×500、完全不透明**（探针 A 通道全 255），天空/海面铺满整张，没有透明边。

---

## 二、引擎开屏：换成海岛整图（`project.godot`）

`[application]` 下新增三项：

```ini
boot_splash/image="res://assets/logo_splash.png"
boot_splash/bg_color=Color(0.364706, 0.737255, 0.996078, 1)
boot_splash/stretch_mode=1
```

| 项 | 取值 | 说明 |
|---|---|---|
| `boot_splash/image` | `res://assets/logo_splash.png` | **只支持 PNG**（Godot 4.7 的 `PROPERTY_HINT_FILE` 就是 `*.png`，非 PNG 会打印 `The only supported format is PNG.`） |
| `boot_splash/bg_color` | `#5DBCFE` | 从原图**左上角实际采样**（R93 G188 B254），让背景与画面天空无缝 |
| `boot_splash/stretch_mode` | `1` = Keep | 500×500 原尺寸居中，不拉伸；`Cover` 在 16:9 上会把太阳和岛顶裁掉 |

效果：② 那一屏从"Godot 机器人"变成海岛图，且背景同色，不再突兀。

---

## 三、新增 Android 12 安全区圆形图标

### 3.1 为什么不能直接把整图塞进去

Android 12+ 的系统开屏会把图标**按圆形遮罩裁剪**，且可视圆只有容器直径的 **2/3**。500×500 全幅图直接当图标，四角（太阳、岛屿边缘）会被切掉——这正是原来"放大且被裁"的观感来源。

### 3.2 产物

`assets/logo_splash_icon.png`：**432×432、透明底**，把画面裁成**直径 288px 的圆**（432 × 2/3），圆外全透明。太阳、三棵棕榈、小岛、海面都落在圆内。

### 3.3 生成方式

Windows PowerShell + `System.Drawing`（GDI+），非手工绘制：

```powershell
$m = New-Object System.Drawing.Drawing2D.Matrix($sx, 0.0, 0.0, $sy, [float]$off, [float]$off)
$brush = New-Object System.Drawing.TextureBrush($src, [System.Drawing.Drawing2D.WrapMode]::Clamp)
$brush.Transform = $m
$g.FillEllipse($brush, $off, $off, $safe, $safe)   # safe=288, off=72
```

`FillEllipse` + `TextureBrush` 让圆边**抗锯齿**（探针：边界处 alpha 有 191/231/247 的渐变过渡，不是硬边）。

**性质**：这是**派生资源**，唯一源是 `logo_splash.png`；原图换了必须重新生成。

---

## 四、本地导出预设（不入库）

`export_presets.cfg` 被 `.gitignore` 第 7 行忽略（可能含签名口令），**不在版本库内**，因此这两项只能在编辑器的 Android 导出预设里填：

| 导出项 | 取值 | 说明 |
|---|---|---|
| `splash_screen/icon` | `res://assets/logo_splash_icon.png` | 第 ③ 项的圆图，喂给 Android 系统开屏 |
| `splash_screen/background_color` | `Color(0.364706, 0.737255, 0.996078, 1)` | 与 `boot_splash/bg_color` 同色，两层衔接不跳色 |

> ⚠️ 这两个选项在 Godot 4.7 里被归类为**高级选项**，导出对话框默认**不显示**，需要先打开右上角的高级选项（源码：`_is_advanced_option()` 对这四个 `splash_screen/*` 直接 `return advanced_options_enabled`）。
> ⚠️ `splash_screen/disable_godot_boot_splash` **保持 false**：本次要的就是让 ② 显示自定义海岛图，勾上反而会把引擎开屏整块去掉。

最终时间线：**天空蓝底 + 圆形海岛图标（系统）→ 整张海岛图居中（引擎）→ 游戏**，三层背景同色 `#5DBCFE`。

---

## 五、踩坑记录

1. **`application/boot_splash/image` 默认为空，不是 `res://icon.svg`**。读 Godot 4.7 `main/main.cpp` 的 `setup_boot_logo()` 确认：路径为空 → 直接 `memnew(Image(boot_splash_png))` 用**编译进引擎的内置 logo**。所以"项目里没写 boot_splash 却看到 Godot 图标"是预期行为，不是资源丢失。
2. **`boot_splash/image` 只吃 PNG**（同文件的 `PROPERTY_HINT_FILE` 为 `*.png`）。
3. **`splash_screen/background_color` 的默认 `Color(0,0,0,1)` 是"未设置"哨兵**。`_fix_themes_xml()` 里 `if (color == Color())` 走 `@mipmap/icon_background`，否则才用你给的颜色。**想真正指定背景色必须写一个非纯黑值**。
4. **`splash_screen/icon` 的回落链**在 `load_icon_refs()` 里：用户指定 → adaptive foreground → 主图标 → 项目 `config/icon`。留空不等于"没有开屏图标"，而是回落到 App 图标。
5. **PowerShell GDI+ 的 `Matrix.Translate(..., Prepend)` 乘法顺序与直觉相反**。第一版写 `Scale()` 后再 `Translate(Prepend)`，实际得到 `M = S×T`，纹理被平移了 41.5px，导致圆右侧被切平（探针 `y=216` 轮廓为 `[72..329]`，应为 `[72..360]`）。改成**显式构造矩阵** `Matrix(sx,0,0,sy,off,off)` 后恢复对称圆形。
6. **`android/build/` 下 1GB 的内容大部分是被忽略的**：`.gitignore` 的 `build/`（任意层级）已覆盖 `android/build/build/` 的 854MB 构建中间产物。整个 `android/` 里真正未被忽略的只有 `android/.build_version` 一个文件——这就是 `git status` 里那个 `?? android/` 的来源。**已通过整目录忽略处理，见第七章第 2 条。**

---

## 六、验证

| 项 | 命令 / 方法 | 结果 |
|---|---|---|
| 资源改名后能重新导入 | `--headless --import` | ✅ 重新导入 `logo_splash.png`、`logo_splash_icon.png`，无 ERROR/WARNING |
| 引擎开屏路径可解析 | `--headless --quit-after 5` | ✅ 无 `Non-existing or invalid boot splash` 等报错 |
| 圆图是真圆（不是方形/偏心） | 逐行扫描 alpha>8 的轮廓 | ✅ `y=216 → x[72..359]`、`y=90 → [145..286]`、`y=300 → [99..332]`，左右对称、符合半径 144 的圆 |
| 圆图圆外透明、圆内不透明 | 采样 `(2,2)` / `(216,216)` / `(430,430)` | ✅ 四角 A=0，圆心 A=255，边界 A≈191~247（抗锯齿） |
| 资源改名无残留 | 全仓 grep `logo_slash` | ✅ 无匹配 |

**未做**：导出 APK（按需求）。真机三层开屏的实际观感待下次导出确认。

---

## 七、遗留 / 待办

1. **确认 `export_presets.cfg` 里第四章那两项已填**。该文件不入库，无法通过 git 追溯，只能靠本机确认。
2. ~~`android/` 未跟踪~~ **已处理**：`.gitignore` 在 Godot 段新增 `android/`（附原因注释），整棵 `android/` 连同 `android/.build_version` 一并忽略，`git status` 已干净。验证：`git check-ignore -v -- android android/.build_version android/build/res` 三行均命中 `.gitignore:11:android/`。这样也避免了以后误用 `git add -A` 把 213MB 构建模板塞进仓库。
3. **`launcher_icons/*` 仍为空**：App 图标继续回落到 `icon.png`。若想让桌面图标也走"安全区"样式，需要另出一套 192×192 主图标 + 432×432 自适应前景/背景。
4. **真机验证**：若圆外仍被切，把生成脚本的安全区系数从 `2/3` 调到 `0.6` 重新生成即可。