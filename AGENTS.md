# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.

> Code comments and in-game text are in **Chinese**. Documentation is bilingual
> (`README.md` in English, `README.zh-CN.md` in Chinese). Keep it that way.

---

## Project at a glance

A single-player **Catan** (base game) implementation in **Godot 4.7 / GDScript**.
One human player plus 2–3 AI opponents in three difficulty tiers. No networking.

- Engine: Godot **4.7** (developed against 4.7.2 stable), `gl_compatibility` renderer
- Design resolution: **1280×720**, `stretch/mode=canvas_items`, `aspect=expand`
- Main scene: `res://scenes/main.tscn` (already wired to `run/main_scene`, so **F5** runs it)
- ~5.8k lines of GDScript, no addons, no external dependencies

---

## Commands

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot   # macOS
```

### Run the game

```bash
# Editor: import project.godot, then press F5
# Or from the terminal:
$GODOT --path .
```

### Import (needed after adding scripts, to register `class_name`)

```bash
$GODOT --headless --path . --import
```

### Tests — headless is fine

```bash
$GODOT --headless --path . --script res://tools/verify_topology.gd    # 19/54/72 geometry assertions
$GODOT --headless --path . --script res://tools/test_rules.gd         # 46 rule unit tests
$GODOT --headless --path . --script res://tools/test_trade_dialog.gd  # 24 bank-trade-dialog unit tests
$GODOT --headless --path . --script res://tools/test_dev_dialog.gd    # 56 dev-card/turn-split unit tests
$GODOT --headless --path . --script res://tools/test_seed.gd          # seed parsing + official number rules
$GODOT --headless --path . --script res://tools/test_pick.gd          # touch picking, "vertex wins" geometry
$GODOT --headless --path . --script res://tools/test_safe_area.gd     # safe-area insets + board/HUD layout math
$GODOT --headless --path . --script res://tools/test_legend.gd        # legend contents come from Res.COST_*, panel geometry
$GODOT --headless --path . --script res://tools/test_ports.gd         # port badge wording + "centre sits on the edge's perpendicular bisector"
$GODOT --headless --path . --script res://tools/sim_runner.gd -- 500  # 500-game batch, prints win-rate matrix
```

`tools/crop_shot.gd` is not a test but a must-have companion to any visual change: it crops a rectangle
out of a saved screenshot and magnifies it with nearest-neighbour, so you can actually *read* 20 px UI
details (port badges, legend text, vertex anchors) instead of guessing from a full-size image.
It is pure `Image` work, so it **can** run headless — and note that macOS `sips -c` only crops from the
centre, `--cropOffset` is silently ignored, so do not reach for it.

`sim_runner.gd` takes a second argument: `h2h` (1 hard vs 3 medium) or `v` (verbose, dumps one game).
It also asserts two invariants across every game: **resource conservation** (bank + players = 19 cards
per resource) and **state integrity**.

### Tests — headless is FORBIDDEN

These drive the real renderer and will hang (and be killed with exit code 137) under `--headless`:

```bash
$GODOT --path . --resolution 1280x720 --script res://tools/screenshot.gd -- res://scenes/main.tscn /tmp/board.png 30 auto
$GODOT --path . --resolution 1280x720 --script res://tools/shot_dialog.gd
$GODOT --path . --resolution 1280x720 --script res://tools/shot_trade_dialog.gd
$GODOT --path . --resolution 1280x720 --script res://tools/shot_dev_dialog.gd
$GODOT --path . --resolution 1280x720 --script res://tools/shot_help.gd
$GODOT --path . --resolution 1280x720 --script res://tools/test_interaction.gd -- 6000
```

- `screenshot.gd` args: `<scene> <out.png> <wait_frames> <zoom> [auto]`. Append **`auto`** to hand the
  human seat to the AI — without it the game stalls in setup waiting for input and you screenshot an empty board.
- `test_interaction.gd` simulates real clicks through the same signals the UI emits (M2 acceptance).
- `shot_help.gd` pushes a **real** mouse click at the "?" button via `root.push_input` and asserts the
  legend toggles without triggering a board build; it then **moves the board up** so a board vertex
  really falls under the open panel and clicks it — the overlay must swallow that click too. It also
  writes a 2× crop of the top-left corner (`*_zoom.png`) — the button and the legend are both in that
  tiny patch, easy to miss at full size.
- `probe_legend.gd` is a read-only probe: prints the legend's size and what it covers (hexes, vertices,
  port badges). Handy after editing legend copy/rows — cheaper than eyeballing a screenshot.
- `probe_ports.gd` prints, for all 9 port edges, the angle between the **radial** direction and the
  edge's **outward normal**, plus how far the badge would move if you used the wrong one. Run it before
  touching port placement — see trap 16.
- `--resolution` **must match the design resolution (1280×720)** for anything that involves mouse coordinates. See trap 3.

---

## Git / GitHub

`origin` lives on GitHub and this network cannot reach it directly, so **before any
`git clone` / `git fetch` / `git push` follow `docs.local/rule-proxy-ym.md`** (proxy setup,
incl. which proxy is the one for git). Symptom if you skip it: the command hangs with no
output, or dies with `Recv failure: Connection was reset`.

> `docs.local/` is git-ignored and stays local, so that file will **not** exist after a
> fresh clone — ask a teammate for it. Never copy its contents (internal addresses) into
> tracked files such as this one.

---

## Architecture contract

These are load-bearing. Breaking them breaks the project's whole reason for existing
(AI balance must be verifiable by running games unattended).

1. **`core/` never depends on nodes or UI.** Everything there is `RefCounted` / `Resource` and must run
   under `--headless`. This is what makes batch simulation possible.
2. **Humans and AI share the `IntentProvider` interface** (`game/intent_provider.gd`).
   `GameController` does not care whether the opponent is a person or a machine. Adding a difficulty tier
   means adding an `AIController` subclass — it must not require touching the dispatch code.
3. **All legality checks live in `core/rules.gd` and must be pure functions** (no state mutation),
   so AI can run hypothetical lines of play.
4. **`GameController` is step-drivable**: `setup_*` / `start_turn` + `roll_dice` (or the combined
   `begin_turn`) / `apply_action` / `finish_turn` / `advance_player`. The unattended `run()` loop is
   built on this same API, so the interactive game and the batch harness always share one code path.
   Never write a second implementation for tests. ⚠️ `begin_turn` must equal `start_turn` +
   `roll_dice` **including RNG call order** — `test_dev_dialog.gd` asserts the dice sequences match;
   if they diverge, `sim_runner` win rates silently change meaning.
5. **`GameDirector` only decides "whose turn and what interaction is needed"** — it makes no rule
   judgments. Human clicks call `apply_action()` directly, bypassing `IntentProvider`.
6. **The HUD is dumb**: it displays state and emits signals; every decision lives in `GameDirector`.
   Build controls in code — do not hand-write `.tscn` for the panel (its buttons come and go with state).
7. **Board topology is computed once and cached** (`BoardTopology.instance()`). After touching geometry,
   run `tools/verify_topology.gd` (it hard-asserts 19/54/72 plus the degree distributions).
8. **Both `tools/test_rules.gd` and `tools/sim_runner.gd` must be run after any rules-engine change.**

---

## Directory map

```
core/     Pure logic, no Node/UI dependency
          hex_grid.gd          cube/axial coords + corner topology generation
          board_topology.gd    19 hexes / 54 vertices / 72 edges + adjacency, cached
          board.gd             island generation (terrain, numbers, ports, seed)
          game_state.gd        global state snapshot
          player_state.gd      per-player state
          game_controller.gd   turn scheduling / state machine / victory check
          rules.gd             ALL legality checks — pure functions
          longest_road.gd      longest-road DFS
          resources.gd         every constant: resources, terrain, dev cards, ports, costs
ai/       ai_base.gd (shared scoring + IntentProvider impl), ai_easy/medium/hard.gd, evaluation.gd
game/     game_director.gd (turn/interaction orchestration), intent_provider.gd, human_intent.gd
ui/       board_view.gd (_draw() board painting), hud.gd (right-hand panel, code-built), palette.gd,
          safe_area.gd (DisplayServer safe-area → viewport insets, shared by board + HUD)
scenes/   main.tscn — root Main → BoardView (Node2D), HUD (CanvasLayer), GameDirector (Node)
tools/    20 CLI scripts — headless tests (verify_topology / test_rules / test_seed / test_pick /
          test_safe_area / test_legend / test_ports / test_trade_dialog / test_dev_dialog / sim_runner),
          render-dependent (screenshot / shot_dialog / shot_trade_dialog / shot_dev_dialog /
          shot_help / test_interaction), probes (probe_seed.gd / probe_legend.gd / probe_ports.gd),
          crop_shot.gd (screenshot crop+zoom)
assets/   terrain/ (imported, downscaled) and resource.src/ (all originals, .gdignore'd)
docs/     board_preview.png and gameplay screenshots
DESIGN.md Full design document (Chinese) — the authoritative reference
```

---

## Conventions

- **Colors**: increase = red, decrease = green (Chinese market convention). Player colors live in
  `UIPalette.PLAYER`; **player names do not** — they come from `GameDirector.AI_LABELS`.
  Changing colors/names means editing *both*, or the board and the panel disagree.
- **Player pieces**: blue = you, red/orange/green = the three AI seats.
- **Highlight color is cyan** (`BoardView.HL_COLOR`): green vanishes against forest/pasture terrain,
  white vanishes against desert/fields.
- **Highlighting must check both "legal" and "affordable"**. `Rules.valid_*` only checks legality —
  using it alone lets the player click spots they cannot pay for.
- **The event log is never truncated.** Keep every line; the panel title shows the total count.
  Auto-scroll only when the player is already at the bottom. Detect "new content" via
  (line count + last line text) — comparing an array reference to itself always reports "unchanged".
- **Restarting keeps the log** (`GameDirector._session_log`): it only ever grows.
- **Tunables are `@export`** so they can be tweaked in the inspector (seed, zoom, origin, display flags).
- **Phone safe area is measured, not hardcoded** (`SafeArea.insets()` → `Vector4(left, top, right, bottom)`
  in *viewport* pixels). Get it from `DisplayServer.get_display_safe_area()` and let the board / HUD inset
  by it; the `MIN_*` fallback margins apply **only on mobile** so desktop layout stays pixel-identical.
  Never park a control at a raw `x = 14` — that is exactly where a left-side camera cutout sits in
  landscape. Layout math that consumes insets is kept in static pure functions
  (`BoardView.board_origin_for` / `HUD.content_rect`) so it can be unit-tested headless.
- **The terrain legend is collapsed by default** behind the top-left "?" button (`BoardView.help_center()`),
  which turns into "×" while open. The panel is a **two-column overlay**: left = terrain swatch + terrain
  name + the resource it yields, right = 修路 / 村落 / 城市 / 发展卡 and what each costs. Its width is
  **measured from the strings at runtime** (`BoardView.legend_size()`), never hardcoded.
  The cost numbers come straight from `Res.COST_*` — **never re-type them into the UI**.
  The panel background may run to the screen edge, but its *content* must stay inside the safe area.
- **Port badges carry a single glyph**: `?` for a generic 3:1 harbour, otherwise one character of the
  resource short name (木/砖/羊/麦/矿, taken from `UIPalette.RES_SHORT` — never re-typed here).
  The ratio itself is omitted on purpose: veterans know it, and text on the badge just eats space.
  `BoardView.port_marker_pos()` places a badge at the edge midpoint offset along the edge's
  **outward normal**; see trap 16 for why the radial direction is wrong.
- **Anything drawn on top of the board must also swallow input.** The legend covers the top-left sea and
  can reach a pickable vertex on a short viewport; `BoardView._hit_legend()` consumes the click, otherwise
  tapping the legend builds a settlement underneath it ("点帮助却建了座村庄").
- **Artwork**: all originals live in `assets/resource.src/` (read-only, `.gdignore`d so Godot never
  imports them). Derived, downscaled copies go in `assets/<type>/` for the game to use.
- **UI palette**: as of the current design, 4 player colors are blue/red/orange/green and names are
  `蓝方 / 小红 / 小橙 / 小绿`.

---

## Traps that have already bitten us

Read this section before debugging anything UI- or generation-related.

1. **`add_theme_*_override` only has six prefixes**: `color` / `constant` / `font` / `font_size` /
   `icon` / `stylebox`. There is **no `add_theme_font_color_override`**. Calling a non-existent name
   produces **no compile error** — it emits one `SCRIPT ERROR` line at runtime and is then silently
   skipped, so the override just never applies. Verify by reading the resolved value:
   `ctrl.has_theme_color_override("font_color")` + `ctrl.get_theme_color("font_color")`.

2. **Assigning `LineEdit.text` programmatically does NOT emit `text_changed`** (verified: the signal
   does not fire). Real keystrokes do. So any "process input as you type" logic (filtering, validation,
   enabling buttons) can only be tested by feeding real `InputEventKey`s through `root.push_input(ev)`.
   Assigning `.text` in a test gives you a fake result. Related: **`Control.gui_input` is a signal,
   not a method** — calling it directly fails to parse.

3. **`--resolution` changes the window, not the viewport.** The project's design resolution is 1280×720
   with `stretch/mode=canvas_items`, so passing e.g. `--resolution 1152x648` yields a 1152×648 window
   with a still-1280×720 viewport: the GUI lays out at 1280×720 and is then scaled to fit.
   Synthetic mouse events are delivered in **window** coordinates and converted by the scale factor,
   so clicking (640, 361) can land on a control at (711, 401) — "I clicked A but B fired".
   → **Any test involving mouse coordinates must use `--resolution 1280x720`.**

4. **Any script awaiting `RenderingServer.frame_post_draw` must not run with `--headless`.**
   The signal never fires, the main loop spins forever, and the process gets killed — exit code 137
   with nothing in the log but the version banner. That looks like "no output", not like an error.
   Affected: `screenshot.gd`, `shot_dialog.gd`, `shot_trade_dialog.gd`, `shot_dev_dialog.gd`,
   `test_interaction.gd`.

5. **After changing a signal's parameter list, grep the whole repo for `.emit(`.**
   Production code gets updated and test scripts silently do not; the symptom is
   `Method expected N argument(s), but called with M`.

6. **Board generation follows the official CATAN rules — and only those.** From the official Almanac
   ("Number Tokens – Fully-Random"): the red numbers **6 and 8 must never be adjacent**, and **no two
   adjacent hexes may share the same number**. There is **no official rule against adjacent identical
   terrain/resources** — "no adjacent same resource" is a fan/tournament balancing preference, not an
   official rule. Do not reintroduce it; `tools/test_seed.gd` asserts in reverse that adjacent
   same-terrain hexes *do* occur, precisely so that re-adding the constraint fails loudly.

7. **Never let generation fail silently.** The previous implementation used shuffle-and-retry and,
   after exhausting its retries, simply kept the last candidate — **41% of boards violated the
   intended constraint and nothing was logged**. Failures must `push_error` and must be covered by an
   assertion (`Board.self_check()` is called for every game by `sim_runner.gd`).

8. **Static board rendering uses `_draw()`** — never build a node tree for the 19 hexes / 54 vertices /
   72 edges. Hex textures are painted with `draw_polygon(points, colors, uvs, texture)`.

9. **Hex UVs must be derived from the polygon's own bounding box in pixel space.** Mixing world-space
   `hex_center` with pixel-space vertices yields absurd UVs that render as a flat washed-out colour,
   which is very hard to spot by eye.

10. **Screenshot self-checks must run inside the `frame_post_draw` callback.** Reading a node's
    properties immediately after `add_child()` returns pre-`_ready` values.

11. **Never delete the `.workbuddy/` directory.** It is this project's accumulated notes, not a cache.
    It is intentionally git-ignored, so it will not be pushed.

12. **Touch picking must be "vertex wins", never "nearest wins".** `Pick.ANY` originally chose between a
    vertex and an edge by *distance* — a mouse-only rule. A road is a segment radiating from a vertex,
    so as a finger slides along the road direction the distance to that segment barely grows: "the road
    is nearer" is always true, and tapping a settlement kept building a road instead (found on Android).
    `_nearest_any` now returns the vertex **whenever the tap lands inside an already-highlighted
    vertex's radius**; the edge does not compete at all. Two things make the enlarged radius safe:
    `PICK_VERTEX_R = 0.40` (≈25 px at `px_per_unit = 62` — sized for a fingertip, not a cursor), and the
    official rule that settlements must be ≥2 edges apart, which guarantees an edge never has a
    highlighted vertex at *both* ends — so no road loses more than one end of its hit area.
    `tools/test_pick.gd` locks this in: it sweeps the hit zone of all 54 vertices (5184 sample points)
    and asserts nothing there can fire an edge, plus that all 72 road midpoints stay clickable.

13. **Do not guess macOS system colours from memory — ask the OS:**
    `swift -e 'import AppKit; print(NSColor.systemRed.usingColorSpace(.sRGB)!)'`.
    (The red used for player "小红" is `systemRed` = `#FF383C`.)

14. **macOS notes**: `timeout` does not exist; a harmless `rename_error` on headless shutdown can be
    ignored; Godot rewrites the header comments of `project.godot` (this is normal).

15. **A safe-area inset that is applied on desktop silently rewrites every screenshot baseline.**
    `DisplayServer.get_display_safe_area()` returns the whole screen on desktop, so the *measured* inset
    is 0 there — but a naive `max(measured, MIN_MARGIN)` would hand the desktop a 18 px margin anyway and
    shift `board_origin` from (510, 360) to (518, 360), invalidating every previously captured reference
    image. The fallback margins are therefore gated behind `OS.has_feature("mobile")`, and
    `tools/test_safe_area.gd` asserts the desktop origin stays exactly (510, 360).

16. **A port badge is offset along the edge's outward *normal*, not the *radial* direction.**
    The old code used `mid + mid.normalized() * PORT_OUT` ("board centre → edge midpoint"). Those two
    only agree when an edge happens to be perpendicular to the radius; on the island's coastal port
    edges they differ by **23.4° or 49.1°**, which slid the badge off its edge by up to **0.38 world
    units (~24 px)** — it reads as "the harbour isn't lined up with its edge". `BoardView.port_marker_pos()`
    takes the edge's perpendicular, flips it away from the board centre, and
    `tools/test_ports.gd` asserts the lateral offset is **< 0.002**. `tools/probe_ports.gd` prints the
    per-edge angles if you ever want to see the damage.

---

## Definition of done

Before considering a change complete, run these and make sure they are green:

| Command | Expected |
|---|---|
| `verify_topology.gd` | `TOPOLOGY OK` |
| `test_rules.gd` | `通过 46 · 失败 0` / PASS |
| `test_trade_dialog.gd` | `通过 24 · 失败 0` / PASS |
| `test_dev_dialog.gd` | `通过 56 · 失败 0` / PASS（含 begin_turn 与 start_turn+roll_dice 骰子序列一致） |
| `test_seed.gd` | all checks pass |
| `test_safe_area.gd` | `通过 18 · 失败 0` / PASS（含桌面棋盘原点仍为 (510, 360)） |
| `test_legend.gd` | `通过 36 · 失败 0` / PASS（花费取自 `Res.COST_*`，面板不越出视口 / 不压地块） |
| `test_ports.gd` | `通过 51 · 失败 0` / PASS（牌面一个字，牌心横向偏移 < 0.002；不压地块、不重叠） |
| `sim_runner.gd -- 30` | `不变量：棋盘异常 0 · 资源守恒破坏 0 · 状态完整性破坏 0` and `M1 验收结果：PASS` |
| `test_interaction.gd -- 6000` | `M2 验收结果：PASS` |
| `shot_dialog.gd` | `--- 结果：PASS ---` |
| `shot_help.gd` | 点击后 `legend_open=true`、点面板亦 `误落子 0 次`，PNG written |
| `screenshot.gd` | board self-check passes, `地形贴图: 6/6 已加载`, PNG written |

Also: if you changed a rule, an AI heuristic, or generation logic, **report the numbers**
(win rates, violation counts) — do not just say "it works".

---

## Current state

- **Done**: P0 scaffolding · P1 topology · P2 rules engine · P3 three AI tiers · P4 board rendering ·
  P5 player interaction.
- **Milestones**: **M1** (rules engine) and **M2** (a human playing a full game against 3 AIs) both accepted.
- **Not done (M3)**: player-to-player trading UI, letting the player choose for discard / monopoly /
  year-of-plenty, animations & sound, tutorial, save/load, settings page.
- Full design and acceptance data: **`DESIGN.md`** (Chinese).
