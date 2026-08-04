# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

City Critters — cozy multiplayer life-sim built with **Godot 4.7** (GDScript, tabs for indentation). Players work minigame jobs around a critter city, earn currency, and will eventually decorate housing, fish, and befriend NPCs. Design source: `City_Critters_GDD.pdf`. A visual systems overview lives at `docs/game_systems.pdf`.

Godot binary on this machine: `/home/bilal_ahmad/Documents/Godot_v4.7-stable_linux.x86_64` (referred to as `godot` below).

## Commands

```bash
# Smoke tests — run after any change:
godot --headless --path . -s check_jobs.gd        # expect "ALL CHECKS PASSED"
godot --headless --path . -s check_npcs.gd        # expect "ALL NPC CHECKS PASSED" (clock/sky/nav/schedules/dialogue)

# After adding/renaming a class_name or new resources, rebuild the import/class cache once,
# or headless runs will parse-fail on the new class:
godot --headless --path . --import

# Visual verification (no test framework — render a screenshot and Read the PNG):
godot --path . -s <script.gd> --resolution 900x600 --rendering-method gl_compatibility
# where script.gd extends SceneTree, sets things up on frame >= 2 in _process,
# then saves root.get_viewport().get_texture().get_image().save_png(...) and quit(0)
```

There is no lint step; the editor/engine parse is the check. **GDScript warnings behave as errors here** — see Gotchas.

## Architecture

### Autoloads (project.godot `[autoload]`)
- `SteamManager` (`Steam_Multiplayer/steam.gd`) — boots Steam API (GodotSteam); degrades gracefully when Steam absent, so the game always runs solo.
- `Multiplayer` (`Steam_Multiplayer/network_manager.gd`) — Steam lobby host/join/browse; on session start loads the world (`scenes/city/town.tscn`).
- `MultiplayerGlobal`, `MultiplayerManager` — character-selection state; alternate ENet backend.
- `GameManager` — scene changes.
- `CurrencySystem` → `PlayerData` — single wallet. Jobs never touch `PlayerData.currency` directly; they call `CurrencySystem.earn()`, which saves and emits `currency_changed` (HUD listens).
- `PlayerData` — currency, cosmetics, NPC rapport; persists to `user://player.cfg`.
- `JobStats` — lifetime per-job stats fed by `job_base.end_job`; persists to `user://job_stats.cfg`. Both saves are **skipped when headless** so tests don't pollute real saves — but windowed test runs DO save.
- `GameClock` — canonical in-game time (`hour` float, `day`, signals `time_changed`/`hour_changed`/`day_changed`; 20 real minutes = 1 game day; persists to `user://clock.cfg`, headless-skipped). If the world has a Sky3D node in the `"sky3d"` group (Demo.scn does), the clock disables Sky3D's own time and pushes `current_time` every frame — GameClock is the single time source. NPC schedules and the HUD clock label listen to it. The `addons/sky_3d` copy was hand-fixed (removed a broken `WeatherController` reference); don't blindly re-download it.

### Job system (`scripts/jobs/`)
All four jobs (Food Service, Retail, Delivery, Corporate) extend `job_base.gd`, which owns the shift lifecycle: `start_job()` → `_on_job_tick()` → `end_job()` pays `_earned` once via `CurrencySystem` and records the summary in `JobStats`. A new job overrides `_on_job_started/_on_job_tick/_on_job_ended/_build_summary`, calls `_award(pay)` for good play, and sets `job_type` in `_init` — currency, stats, and the stats screen then work with no extra wiring.

Each logic node lives inside a physical station scene (`scenes/jobs/*.tscn`): `FoodServiceStand`, `RetailStore`, `DeliveryDepot` (+ city-wide `DeliveryPoint` mailboxes found via the `"delivery_points"` group), `CorporateDesk` (a `JobStation` that opens an overlay UI instead). Stations gate their interactables: only clock-in is armed off-shift; `job_started`/`shift_ended` arm/disarm everything else.

Entry point for all world interaction is `InteractionArea` (`scripts/interaction/interaction_area.gd`) — a "press E" Area3D that arms only for the local authority player and has a `set_active()` gate.

### Player (`Player/Scripts/`)
`player_controller.gd` (CharacterBody3D) + a LimboHSM state machine (`state_machine.gd`, states in `States/`: idle/walk/run/run_jump). Movement is **root motion**: the AnimationTree's clip displacement becomes velocity each tick — don't set velocity from input directly. Input with a forward component ("forward fan") rotates the model toward travel direction and plays the forward clip; pure side/back input strafes camera-locked. `CarryComponent` (via `player.get_carry()`) holds carried job items. `set_busy(true)` freezes movement/camera for overlay UIs. Networking: only the authority peer simulates; proxies have physics off and replay `NetAnimSync` vars replicated by `MultiplayerSynchronizer`. Player joins the `"player"` group in `_ready`.

### UI wiring is group-based, not reference-based
- `MapMarker` (`scripts/ui/map_marker.gd`) — child of any Node3D, self-joins `"map_markers"`; `set_objective(true)` adds `"map_objective"`. The `Minimap` control scans these groups every frame — drop a marker under anything and it appears on the map.
- HUD (`scenes/ui/hud/hud.tscn`) — currency label + notifications + `JobStatsScreen` (toggled by the `job_stats` input action, J) + `NPCScheduleDebug` (F3 = per-NPC schedule status panel, H = advance GameClock one hour, F4 = spectator camera that orbits each NPC in turn and exits after the last). Instanced in town.tscn, st_guy_blockout.tscn, AND Demo.scn (added by repack). The Minimap draws a game-clock label ("12:00") above the map square.
- Job overlays (`food_service_ui.gd`, `corporate_ui.gd`) build their UI trees in code; the .tscn files stay trivial on purpose.

### Worlds
`scenes/city/town.tscn` (main map; buildings assembled by parametric `@tool` scripts `ModularBuilding`/`CityStreet`) and `scenes/city/st_guy_blockout.tscn` (CSG-only village generated from a watabou map). Each world contains job stations, delivery points, Minimap + HUD instances, and a `MultiplayerSpawner` + `PlayerSpawnManager` that spawns one player per peer (or one local player when offline).

NPCs (`scripts/npcs/npc_base.gd` + `scenes/npcs/npc.tscn`): talk/gift/rapport + GameClock schedules. Movement = NavigationAgent3D path following + root motion (AnimationTree Transition "idle"/"walk", same root_motion_track as the player; walk ≈ 0.73 m/s). Demo.scn contains a baked `NavRegion` (NavigationRegion3D, baked offline from static colliders via a repack script — rebake after changing town geometry).

Early skeletons awaiting content: hobbies (`scripts/hobbies/`), housing grid placement (`scripts/housing/`).

## Gotchas (each of these has cost real debugging time)

- **Warnings are errors.** `var x := call_returning_variant()` (Variant-inferred declaration) is a parse FAILURE. Use explicit types: `var x: Node = ...`.
- **A subclass `@export` must not reuse a parent export name** — `base_pay` in a `job_base` subclass is a parse error ("member already exists"). Rename (`delivery_pay`) or assign the parent var in `_init`.
- **`godot -s script.gd` (SceneTree scripts):** autoload identifiers (`CurrencySystem`, `JobStats`, ...) do NOT resolve at compile time in the script itself — fetch with `root.get_node("/root/Name")`. Autoloads also don't exist during `_init` (touching one hangs the run); do work on frame ≥ 1 in `_process(_d) -> bool` (must return a value; `return true` quits).
- **Signal connections must accept ALL emitted args** or the handler silently never runs.
- **CSGPolygon3D extrudes along local -Z**; place the node origin at the feature top or geometry ends up underground.
- **tscn `Transform3D`** serializes basis ROWS: `Transform3D(xx, xy, xz, yx, ..., origin)`.
- **GDScript lambdas capture by value** — test helpers that capture signal results must mutate a boxed array/dict, not reassign a local.
- Centered code-built `PanelContainer`s need `grow_horizontal/vertical = GROW_DIRECTION_BOTH` or they hang bottom-right of the anchor.
