# Catan — Godot Human vs. AI

A single-player implementation of **Catan (base game)** built with **Godot 4.7 / GDScript**.
You play against 2–3 AI opponents in three difficulty tiers. No networking, no external dependencies.

[中文说明 →](README.zh-CN.md)

![Board preview](docs/board_preview.png)

---

## Highlights

- **Rules engine fully decoupled from the renderer.** Everything under `core/` is `RefCounted` with no
  node or UI dependency, so tens of thousands of games can be simulated headlessly. AI strength is
  verified by win-rate matrices, not by vibes.
- **Three genuinely different AI tiers.** The difficulty gap comes from decision quality — scoring noise,
  look-ahead, threat blocking, trade evaluation, robber targeting, discard arithmetic — not from
  tweaking a number in a config.
- **One code path for humans and AI.** Both implement the same `IntentProvider` interface, so the
  interactive game and the batch harness can never drift apart.
- **Official board generation rules.** 6 and 8 are never adjacent, and no two adjacent hexes share a
  number — exactly as the official Almanac requires (and nothing more).
- **A real, playable UI**: hand-painted hex board with terrain artwork, click-to-build with legality
  highlighting, bank trading, development cards, a full untruncated event log, and a restart panel with
  seed control.
- **One layout, three shapes.** Desktop keeps the pixel-exact 1280×720 baseline; wider windows pin the
  panel to the right edge and centre the board in what is left; a phone turns the whole thing into
  portrait — board on top, info area spanning the width below, event log collapsed into a button and a
  full-screen dialog. Phone safe areas (notch, home bar) are respected, and orientation is locked to
  portrait on handhelds only.

| Setup phase | Mid-game | Game over |
|---|---|---|
| ![Setup](docs/gameplay_setup.png) | ![Turn](docs/gameplay_turn.png) | ![Over](docs/gameplay_over.png) |

---

## Features

| Area | Implemented |
|---|---|
| Players | 1 human + 3 AI (difficulty per seat), 5–6 player extension slot reserved |
| Board | 19 hexes (forest / hills / pasture / fields / mountains / desert), 54 vertices, 72 edges |
| Resources | Wood, brick, wool, grain, ore |
| Building | Roads, settlements, cities, development cards |
| Bonus points | Longest road (+2), largest army (+2) |
| Mechanics | Robber & stealing, discard on 7, maritime trade (3:1 / 2:1 ports), domestic trade |
| Victory | First to 10 victory points on your own turn |
| UI | Terrain-illustrated board, click-to-build, legality + affordability highlighting, folded `?` legend (terrain → resource, build → cost), bank-trade dialog, dev card panel, full event log, restart dialog with seed |
| Layout | Desktop (1280×720) · wide windows · phone portrait, auto-detected; phone safe-area insets; portrait locked on handhelds only |
| Touch | Vertex-first picking — a tap inside a highlighted vertex can never fire a road; the open legend swallows its own clicks |
| Tooling | Geometry assertions, rule unit tests, batch simulation, seed tests, layout math tests, render screenshots, simulated-click acceptance test |

**Not implemented yet** (see [Status](#status)): player-to-player trade UI, choosing for
discard / monopoly / year-of-plenty, animations and sound, tutorial, save/load, settings page.

---

## Requirements

- **Godot 4.7** (developed against 4.7.2 stable). Standard build — no modules or addons required.
- The `gl_compatibility` renderer is used, so it runs on integrated GPUs and older hardware.

---

## Getting started

```bash
git clone git@github.com:priece/godot-catan.git
cd godot-catan
```

Open the project in Godot (import `project.godot`), then press **F5** — the main scene is already set
as `run/main_scene`, so nothing else is needed.

From the terminal instead:

```bash
# macOS
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Linux / Windows
godot --path .
```

The first launch may take a moment while Godot imports the terrain textures.

### Landscape vs. portrait

The window shape decides the layout, so there is nothing to configure:

- **Landscape** (any window with width > height) — board on the left, the panel pinned to the right edge.
- **Portrait** (width < height) — board on top, info area spanning the full width beneath it.

To preview the phone layout on a desktop, launch with a portrait resolution:

```bash
./portrait_start.sh                 # macOS / Linux → window 720×1280
./portrait_start.sh -- auto         # the AI takes the human seat (auto demo)
PORTRAIT_RES=1080x1920 ./portrait_start.sh
portrait_start.bat                  # Windows, same flags
```

Both launchers only pass `--resolution <WxH>` with **W < H** — that is the signal `BoardView` keys off.

---

## How to play

**Setup phase.** Place two settlements and two roads. Legal spots are highlighted; click a highlighted
vertex to place a settlement, then a highlighted edge for the road.

**On your turn.** If you hold a playable development card, the turn pauses *before* the roll: play one
card (or none), then press **掷骰子**. With nothing to play the dice are rolled for you. Production
always comes first — only then can you build or trade:

| Action | How |
|---|---|
| Roll the dice | **掷骰子** button — shown only when the turn pauses before the roll |
| Play a development card | **打发展卡** panel — before *or* after the roll, one per turn |
| Build a road | Click a highlighted edge |
| Build a settlement | Click a highlighted vertex |
| Upgrade to a city | Click one of your existing settlements |
| Buy a development card | **买发展卡** button |
| Trade with the bank / a port | **兑换** → pick what you give on the left, what you get on the right → **确定** |
| End your turn | **结束回合** button |
| Move the robber | When you roll a 7 or play a Knight, click the target hex |
| Read the legend | The **?** button in the top-left; terrain → resource on the left, build → cost on the right |
| Read / scroll the log | Right-hand panel in landscape; **查看日志** button + dialog in portrait |
| Restart with a new board | **重开一局** → type or pick a seed → **确定** |

The info panel lists every player's name, victory points, resource counts and current status, followed
by the **event log** — on the right in landscape, spanning the width below the board in portrait. The
log is never truncated: every event since the session started is kept, and the title shows the running
total. In portrait it lives behind the **查看日志** button in a full-screen dialog.

**Notes.** Cyan outlines mark legal *and affordable* placements (legality alone is not enough — you may
not be able to pay). The **?** legend is collapsed by default, it is **modal** — one tap anywhere
(board, the panel itself, the right-hand info panel) closes it — and the tap that closes it never
builds anything. Press **Esc** to close any dialog. The restart dialog accepts
digits only: type a seed and press Enter or click **确定**, or use **随机一局** / **沿用本局** for the
two shortcuts.

**Road Building card.** Its two roads are *free*: they may be placed on **any empty edge**, without
connecting to your existing network (and the second need not touch the first) — this is the official
ruling, not a bug. Once placed, that road is yours, so a settlement can be built on its endpoint. Paid
roads still have to extend your own network.

---

## AI opponents

Three tiers, freely mixable across seats. The differences are behavioural, not numeric:

| Decision | Easy | Medium | Hard |
|---|---|---|---|
| Initial placement | Score + heavy noise, 20% fully random | Best pure score | Score + blocking opponents + ports + look-ahead |
| Build priority | Random among affordable | VP efficiency: city > settlement > dev card > road | Multi-step planning, commits to longest road / largest army |
| Resource management | — | Keeps construction balance | Computes exact shortfalls, reserves for the endgame push |
| Domestic trade | 50% random accept | Evaluates equivalence, accepts profitable trades | Actively seeks arbitrage, never feeds the leader |
| Robber placement | Random hex | Opponent's high-production hex | Hits the leader, blocks their key number |
| Steal target | Random | Player with the most cards | Highest-scoring / suspected hoarder |
| Discard | Arbitrary | Dumps the least needed | Preserves construction combos |

Hard AI also picks a **winning strategy each turn** — road rush (longest road is the most common
winning path), development-card rush, or expansion (the timing of your 3rd settlement correlates most
strongly with victory) — and revises it as opponents claim bonuses.

Because the rules engine runs headlessly, AI strength is measured:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/sim_runner.gd -- 500
```

This prints a win-rate matrix by difficulty and asserts two invariants for every game: resource
conservation (bank + all players = 19 cards per resource) and state integrity.

---

## Board generation

Generation follows the **official CATAN Almanac** ("Number Tokens – Fully-Random"):

- Terrain hexes are **shuffled and placed at random** — the official rulebook imposes no adjacency
  restriction on terrain or resources.
- **6 and 8 are never adjacent.** Both are 5-pip numbers; adjacent reds create a production corner that
  decides games in the first three rounds. This holds in every mode.
- **No two adjacent hexes share a number** (balanced mode).

Generation uses rejection sampling and **fails loudly** (`push_error`) rather than silently emitting an
invalid board. The rule is additionally asserted by `Board.self_check()` — which every simulated game
calls — and by `tools/test_seed.gd`.

Boards are deterministic: the same seed always yields the same island. Set the seed in the restart
dialog, or the `seed_value` export on `BoardView` / `GameDirector` in the inspector.

---

## Project structure

```
core/     Pure logic — no Node/UI dependency, headless-runnable
          hex_grid.gd · board_topology.gd · board.gd · game_state.gd · player_state.gd
          game_controller.gd · rules.gd · longest_road.gd · resources.gd
ai/       ai_base.gd · evaluation.gd · ai_easy.gd · ai_medium.gd · ai_hard.gd
game/     game_director.gd (turn/interaction orchestration) · intent_provider.gd · human_intent.gd
ui/       board_view.gd (_draw() board) · hud.gd (code-built panel) · layout.gd (landscape/portrait math)
          palette.gd · safe_area.gd (display cutout insets)
scenes/   main.tscn
tools/    23 CLI scripts: tests, batch simulation, screenshots, probes
assets/   terrain/ (used) · resource.src/ (originals, not imported)
docs/     preview and gameplay screenshots
portrait_start.sh / .bat   launch in a portrait window (phone layout preview)
```

### Verification tools

| Script | Headless? | Purpose |
|---|---|---|
| `verify_topology.gd` | yes | Asserts 19 hexes / 54 vertices / 72 edges and the degree distributions |
| `test_rules.gd` | yes | 62 rule unit tests (incl. the free-road ruling for the Road Building card) |
| `test_seed.gd` | yes | Seed parsing + the official number-placement rules |
| `test_pick.gd` | yes | Touch picking: a tap inside a highlighted vertex must never fire a road |
| `test_layout.gd` | yes | Landscape / portrait split math — and that the desktop baseline stays byte-for-byte untouched |
| `test_safe_area.gd` | yes | Phone safe-area insets + board/HUD layout math (desktop origin must stay (510, 360)) |
| `test_legend.gd` | yes | Legend: build costs must come from `Res.COST_*`, panel stays inside the viewport and off the hexes |
| `test_ports.gd` | yes | Port badges: one glyph each (`?` / 木砖羊麦矿), and each badge centre must sit on its edge's perpendicular bisector |
| `test_trade_dialog.gd` | yes | Bank-trade dialog unit tests |
| `test_dev_dialog.gd` | yes | Dev-card / turn-split unit tests |
| `sim_runner.gd` | yes | Batch games, win-rate matrix, conservation invariants |
| `screenshot.gd` | **no** | Renders the board to a PNG with a self-check |
| `shot_dialog.gd` | **no** | Drives the restart dialog and captures it |
| `shot_trade_dialog.gd` | **no** | Captures the bank-trade dialog |
| `shot_dev_dialog.gd` | **no** | Captures the dev-card dialog |
| `shot_help.gd` | **no** | Clicks the "?" legend button, captures open/closed + a simulated phone safe area; also clicks a board vertex sitting under the open panel |
| `shot_portrait.gd` | **no** | Portrait pass: injects a safe area, asserts board / panel / content rects, clicks the log button, closes with Esc, captures two PNGs |
| `test_interaction.gd` | **no** | Simulates human clicks through a full game (M2 acceptance) |
| `probe_legend.gd` / `probe_seed.gd` / `probe_ports.gd` | yes | Read-only probes: legend geometry / seed scans / port-badge offset angles |
| `probe_display.gd` | yes | Read-only probe: window vs. viewport size, `content_scale_size` landing frame, orientation detection |
| `crop_shot.gd` | yes | Crops and magnifies a rectangle of a saved screenshot (macOS `sips` cannot crop off-centre) |

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

$GODOT --headless --path . --script res://tools/verify_topology.gd
$GODOT --headless --path . --script res://tools/test_rules.gd
$GODOT --headless --path . --script res://tools/test_seed.gd
$GODOT --headless --path . --script res://tools/test_pick.gd
$GODOT --headless --path . --script res://tools/test_layout.gd
$GODOT --headless --path . --script res://tools/test_safe_area.gd
$GODOT --headless --path . --script res://tools/test_legend.gd
$GODOT --headless --path . --script res://tools/test_ports.gd
$GODOT --headless --path . --script res://tools/sim_runner.gd -- 500

# Crop + magnify a rectangle of an already-saved screenshot (handy for 20px UI details)
$GODOT --headless --path . --script res://tools/crop_shot.gd -- /tmp/board.png 185 210 135 265 3 /tmp/crop.png

# These must NOT be run with --headless, and need --resolution 1280x720
$GODOT --path . --resolution 1280x720 --script res://tools/test_interaction.gd -- 6000
$GODOT --path . --resolution 1280x720 --script res://tools/shot_dialog.gd
$GODOT --path . --resolution 1280x720 --script res://tools/shot_help.gd
$GODOT --path . --resolution 1280x720 --script res://tools/screenshot.gd -- \
    res://scenes/main.tscn /tmp/board.png 30 auto

# Portrait pass: the window must be taller than it is wide
$GODOT --path . --resolution 720x1280 --script res://tools/shot_portrait.gd -- auto
```

If you are an AI agent or a new contributor, read **[AGENTS.md](AGENTS.md)** first — it documents the
architecture contract, the conventions, and a list of Godot-specific traps that have already caused
real bugs here (silent theme-override failures, `text_changed` not firing on programmatic assignment,
`--resolution` not changing the viewport, `frame_post_draw` hanging under `--headless`, and more).

---

## Recent updates

**2026-10 — phone portrait + interaction fixes**

| Change | Detail |
|---|---|
| Portrait layout (P0–P2) | `ui/layout.gd` holds the portrait-only math; board on top, info area spanning the full width below, log collapsed into **查看日志** + full-screen dialog. Landscape branches are untouched — the desktop board origin is still exactly (510, 360). Handheld orientation is locked to portrait; desktop windows are unaffected. |
| Portrait launchers | `portrait_start.sh` (macOS/Linux) and `portrait_start.bat` (Windows) — window shape is the only switch. |
| Wide-screen layout | The panel is pinned to the viewport's right edge and the board centres in the remaining area, so ultrawide windows no longer stretch the gap. |
| Legend folded into **?** | Top-left button, collapsed by default, two columns (terrain → resource, build → cost). Costs are read from `Res.COST_*`, never copied into the UI. It is a **modal overlay**: any tap — board, info panel or the legend itself — closes it, and the closing tap is swallowed, so reading help can never build a village. |
| Phone safe area | Real display cutout / home-bar insets, applied per orientation to the board, top-left buttons, legend and the HUD *content* box (the background still runs to the screen edge). |
| Touch picking | `Pick.ANY` is **vertex-first**: a tap that lands inside a highlighted vertex can never turn into "build a road" on the edge behind it. |
| Bank trade dialog | **兑换** opens a dialog: pick what you give on the left (amount = your best ratio, port bonuses included), what you get on the right. Option buttons are disabled when you cannot pay. |
| Development cards | Can be played before *or* after the roll (one per turn) — the pre-roll window now accepts them and the Knight → robber flow works there too. |
| Port badges | One glyph each — `?` for 3:1, 木 / 砖 / 羊 / 麦 / 矿 for 2:1 — centred on the edge's perpendicular bisector rather than the radial direction. |
| Road Building ruling | The two free roads may go on any empty edge (official ruling: no network connection needed, and they need not touch each other); a settlement can be built on an isolated free road's endpoint. Paid roads still must extend your network. `test_rules.gd` grew to 62 assertions pinning all of it. |

---

## Status

**Done**: P0 scaffolding · P1 board topology · P2 rules engine · P3 three AI tiers · P4 board rendering ·
P5 player interaction · portrait P0–P2 (layout math, HUD, render verification).

**Milestones reached**: **M1** — the rules engine (batch-simulated without illegal states) and
**M2** — a human playing a complete game against three AIs.

**In progress (M3)**: player-to-player trading UI, letting the human choose for discard / monopoly /
year-of-plenty; portrait P3 — dialog width adaptation, soft-keyboard avoidance, back-button handling,
real-device pass. **Planned**: animations and sound effects, tutorial, save & replay, settings page.

Full design document and acceptance data: **[DESIGN.md](DESIGN.md)** (Chinese).

---

## License

No license file has been added yet, so this repository is currently **all rights reserved** by default.
If you intend to reuse it, please open an issue to discuss.

*Catan is a trademark of CATAN GmbH. This is an unofficial, non-commercial fan project.*
