# Modular Space Station Kit

Godot-native 3D station modules for the star-system view and debug/showcase use. The scenes are generated project assets, not runtime procedural output.

## Scenes

- `station_hub_core.tscn`: Central six-port command hub.
- `corridor_segment.tscn`: Straight docking arm oriented along the X axis.
- `habitation_dome_module.tscn`: Detailed civilian/science dome with side docking neck, projected hex lattice, rim domes, and clamp-ring detail.
- `industrial_tank_cluster.tscn`: Clustered storage tanks with a feed pipe.
- `defense_turret_module.tscn`: Small armed outpost module with twin barrels.
- `solar_array_module.tscn`: Utility spine with a clear docking axis and two connected solar wings.
- `comms_spire_module.tscn`: Antenna/sensor spire module.
- `station_assembly_showcase.tscn`: Example station assembled from the kit.

## Usage Notes

- Assets are built from `MeshInstance3D` primitives with metallic hull materials and cyan emissive trims.
- Instance the hub, rotate corridor segments in 90 or 60 degree increments, then attach utility modules at corridor ends.
- Docking collars share the same rough scale. A corridor endpoint about `2.4` units from its origin lines up with hub and module ports.
- The habitation dome is more detailed for close camera passes; use simpler modules when many stations will be visible at once.
- The solar module keeps the front docking axis clear and places panels behind the service bus on a connected crossboom.

## Regeneration

```powershell
$env:GODOT_CONSOLE = "C:\Users\paulp\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe"
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tools/generate_modular_station_assets.gd"
```

## Validation

```powershell
& $env:GODOT_CONSOLE --headless --path "O:\Spiele\sellaris" --script "res://tools/validate_modular_station_assets.gd"
```
