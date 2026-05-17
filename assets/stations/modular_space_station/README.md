# Modular Space Station Kit

Godot-native 3D station modules for the Stellaris-like star-system view.

## Scenes

- `station_hub_core.tscn` - central six-port command hub.
- `corridor_segment.tscn` - straight docking arm, oriented along the X axis.
- `habitation_dome_module.tscn` - large round glass-dome civilian/science module with a side docking neck, projected hex lattice, and two sub-domes.
- `industrial_tank_cluster.tscn` - clustered storage tanks with feed pipe.
- `defense_turret_module.tscn` - small armed outpost module with twin barrels.
- `solar_array_module.tscn` - clear-docking utility spine with two large connected solar wings.
- `comms_spire_module.tscn` - antenna/sensor spire module.
- `station_assembly_showcase.tscn` - example station assembled from the kit.

## Usage Notes

The assets are built from `MeshInstance3D` primitives with metallic hull materials and cyan emissive trims. They are intentionally modular: instance the hub, rotate corridor segments in 90 or 60 degree increments, then attach utility modules at the ends. The habitation dome is intentionally more detailed for close camera passes, using a larger continuous rounded glass shell with a projected hex lattice, clamp ring details, two smaller rim domes, and a dedicated side access neck for corridor connections.

Docking collars are visually centered around the same rough scale, so a corridor endpoint at about `2.4` units from its origin lines up well with hub and module ports. The solar module keeps the front docking axis clear and places its large panels behind the service bus on a connected crossboom.

Regenerate the pack with:

```powershell
C:\Users\paulp\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --path O:\Spiele\sellaris --script res://tools/generate_modular_station_assets.gd
```
