# Development Notes

## Godot Console

Use the Godot 4.6.1 console editor for headless checks:

```powershell
$env:GODOT_CONSOLE = "C:\Users\paulp\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris"
```

## Run Tests

SceneTree tests run with `--script`:

```powershell
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/celestial_visual_determinism_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/galaxy_generator_name_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/anomaly_pool_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/resource_deposit_component_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/empire_anomaly_menu_state_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/empire_command_drawer_smoke_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/ship_design_compiler_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/component_unlock_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/research_catalog_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/research_advisor_test.gd"
```

Node-based smoke tests run through their `.tscn` wrappers:

```powershell
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/space_unit_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/space_exploration_component_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/builder_ship_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/resource_collector_economy_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/colony_host_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/construction_progress_preview_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/exploration_scan_particles_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/star_system_preview_deposit_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/space_entity_details_panel_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/system_body_details_panel_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/unit_upkeep_economy_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/combat_resolution_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/combat_determinism_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/combat_ui_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/ship_designer_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/research_manager_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/research_modal_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/notification_center_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/ship_set_smoke_test.tscn"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" "res://tests/celestial_visual_smoke_test.tscn"
```

Note: SceneTree `--script` tests compile before the autoloads are registered, so they cannot reference autoload singletons (`EconomyManager`, `SpaceManager`, ...) directly; tests that need autoloads run as node-based `.tscn` smoke tests instead. Fresh checkouts/worktrees need one `--import` run before tests so the script class cache exists.

## Celestial Visuals

Planets, stars, black holes and asteroid belts in the system view are real 3D
meshes with live spatial shaders (`scene/StarSystem/procedural_planets/`).

- Seed flow: system seed -> `_get_orbital_seed` / `_get_star_seed` /
  `_get_belt_seed` -> `build_visual_config()` (one local RNG, fixed draw order
  documented in each file — append new draws, never reorder) -> shader
  uniforms. Same seed always reproduces the same body.
- Shader rule: every planet surface pattern is a pure function of the
  model-space unit direction plus seeded uniforms (see
  `shaders/celestial_common.gdshaderinc`). Shader `TIME` only drives cosmetic
  motion (spin handled via node rotation, gas band drift, star boil, pulses).
- Lighting: `render_mode unshaded` + per-material sun uniforms
  (`sun_mode`/`sun_direction`/`sun_position`). `StarSystemPreview` switches
  bodies to point-light mode at the primary star; the body details panel and
  colony modal use the fixed default direction. Note: unshaded mode ignores
  `EMISSION` — HDR glow values go through `ALBEDO`.
- Backdrop: `scene/StarSystem/SystemSkyBackdrop.gdshader` (sky shader; starfield
  + nebula wisps, `seed_offset` set per system by `StarSystemPreview`). It is
  self-contained because `fwidth()` from the shared include is unavailable in
  the sky stage.
- Star prominences are true 3D: half-torus arc tubes
  (`CelestialMeshLibrary.get_prominence_arc()`) anchored on the star sphere
  with seeded orientations, shaded by `shaders/StarPlasmaArms.gdshader`
  (grow/collapse lifecycle, plasma flow, vertex flame wobble); the arm group
  rotates slowly around the star. Normal stars only — neutron stars use beam
  cones, black holes the accretion disk.
- Future extension point: `ProceduralPlanetVisual.build_surface_material()` is
  the single config->shader mapping. A colony-view texture baker can render
  the same surface function through a UV->direction equirect wrapper for
  pixel-identical results.
- Visual check: render per-body screenshots (windowed, not headless) with
  `& $env:GODOT_CONSOLE --path "O:\Spiele\sellaris" "res://tools/celestial_visual_screenshot.tscn"`
  — output lands in `tools/screenshots/`.

## Asset Tools

Regenerate and validate the modular station kit with:

```powershell
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tools/generate_modular_station_assets.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tools/validate_modular_station_assets.gd"
```

## Current Startup Path

- Main scene: `res://scene/MainMenue/MainUI.tscn`
- Galaxy setup scene: `res://scene/GennerateMenue/GennerateMenue.tscn`
- Active game scene: `res://scene/game/GameScene.tscn`
- Older monolithic galaxy scene: `res://scene/galaxy/galaxy.tscn`
