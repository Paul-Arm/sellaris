# Sellaris Project Structure

Sellaris is a Godot 4.6.1 prototype for a Stellaris-like galaxy map, star-system view, and early empire simulation. The current active flow is menu -> galaxy setup -> game scene; the older monolithic galaxy scene is still present for reference but is no longer the startup path.

## Active Scene Flow

1. `project.godot` starts at `res://scene/MainMenue/MainUI.tscn`.
2. `scene/MainMenue/MainUI.gd` hosts the landing page, empire presets, settings, music controls, and multiplayer placeholder page.
3. Singleplayer opens `scene/GennerateMenue/GennerateMenue.tscn`.
4. `scene/GennerateMenue/GennerateMenue.gd` collects seed, star count, minimum system distance, galaxy shape, hyperlane density, and the starting empire preset.
5. Generate instantiates `scene/game/GameScene.tscn` and passes those settings into `GameScene.configure()`.
6. `scene/game/GameScene.gd` wires the runtime systems, bootstraps galaxy state, empires, economy, colonies, space units, and the interactive views.

The folder names `MainMenue` and `GennerateMenue` keep their historical spelling because scene and preload paths depend on them.

## Main Folders

- `autoload/`: Global managers for music, settings, simulation time, empires, presets, economy, colonies, and space units.
- `core/economy/`: Resource definitions, bundles, colony runtime data, pop units, species runtime data, jobs, buildings, deposits, and colony host components.
- `core/space/`: Data-oriented unit classes, live units, fleets, movement, construction, exploration, and station build components.
- `core/empire/`: Empire runtime data, presets, species catalog discovery, portraits, and species traits.
- `core/anomaly/`: Deterministic anomaly definitions, body components, discovery state, and research outcome helpers.
- `scene/MainMenue/`: Authored startup menu and its split UI systems for setup, species, settings, and empire presets.
- `scene/GennerateMenue/`: Galaxy setup scene that launches the active game scene.
- `scene/game/`: Active game scene, view router, UI controller, runtime system, simulation system, colony modal, and space entity panel.
- `scene/galaxy/`: Galaxy generator, state container, map view, map renderers, territory rendering, system names, and the older `galaxy.tscn` path.
- `scene/StarSystem/`: Full system view, preview renderer, selectable components, procedural planets, custom system resource types, and body detail panels.
- `scene/UI/`: Shared galaxy HUD, bottom category bar, debug panels, music controller, and command drawer UI.
- `assets/stations/modular_space_station/`: Generated modular station kit and showcase scene.
- `tests/`: Headless SceneTree tests and smoke-test scenes.
- `tools/`: Godot scripts for generating and validating modular station assets.
- `Planets/` and `PixelPlanets-main/`: Planet shader assets and the vendored PixelPlanets source used as visual reference/material.

## Runtime Surface

- `GalaxyGenerator.gd` builds named systems, shapes (`spiral`, `ring`, `elliptical`, `clustered`), hyperlanes, star profiles, system summaries, bodies, deposits, and initial anomaly records.
- `GalaxyState.gd` owns system records, ownership, intel levels, detail overrides, hyperlane graph, anomaly state, and runtime snapshots.
- `GameSceneRuntimeSystem.gd` coordinates generation, active empire selection, fog-of-war, surveying, anomaly research, colonization, construction, resource syncing, and runtime view refreshes.
- `GameViewRouter.gd` swaps between `GalaxyMapView.tscn` and `SystemView.tscn`.
- `GalaxyMapView.gd` renders the galaxy, labels, hyperlanes, territories, runtime ship/fleet/station markers, selection rings, and hyperlane move routes.
- `SystemView.gd` opens the interactive 3D system preview, body detail panel, build menu, colony actions, anomaly research, and local runtime selection.

## Data Conventions

- Resource types live as `.tres` definitions under `core/economy/resources/`.
- Jobs and buildings are data-driven through `core/economy/jobs/jobs.cfg` and `core/economy/buildings/buildings.cfg`.
- Species are auto-discovered from `core/empire/species/<archetype>/<species_id>/`.
- Species traits live in `core/empire/species/traits/traits.cfg` and are copied into runtime species by the preset/colony flow.
- Custom star-system resources use `CustomStarSystem`, `CustomSystemStar`, and `CustomSystemOrbital` from `scene/StarSystem/`.
- Runtime save data is exposed through `GameSceneRuntimeSystem.get_runtime_snapshot()`, which includes galaxy, space, economy, and colony snapshots.

## Notes

- The active game scene uses modular systems under `scene/game/systems/`; keep new gameplay orchestration there unless the older `scene/galaxy/galaxy.gd` path is being deliberately revived.
- The PixelPlanets directory is vendored source material. Prefer changing project-owned files outside that directory unless updating the vendor import itself.
- Headless development and test commands are documented in `DEVELOPMENT.md`.
