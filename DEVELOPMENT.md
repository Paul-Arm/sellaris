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
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/galaxy_generator_name_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/anomaly_pool_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/resource_deposit_component_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/empire_anomaly_menu_state_test.gd"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tests/empire_command_drawer_smoke_test.gd"
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
```

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
