# Sellaris Project Structure

This project is a Godot 4.6 prototype for generating and viewing procedural galaxies.

## Structure

- `project.godot`: Main Godot project configuration. The startup scene is the main menu.
- `scene/MainMenue/`: Files for the main menu scene.
- `scene/MainMenue/MainMenue.tscn`: Main menu UI scene.
- `scene/MainMenue/MainMenue.gd`: Main menu controller that collects generator settings and opens the galaxy scene.
- `scene/MainMenue/MainMenueBG.gdshader`: Animated background shader used by the main menu.
- `scene/galaxy/`: Files for the galaxy scene and its supporting scripts.
- `scene/galaxy/galaxy.tscn`: 3D galaxy viewer scene.
- `scene/galaxy/galaxy.gd`: Galaxy scene controller that generates stars, hyperlanes, and scene state.
- `scene/galaxy/GalaxyCameraController.gd`: Camera movement, zoom, edge pan, and drag pan behavior.
- `scene/galaxy/GalaxyGenerator.gd`: Shared galaxy generation logic for layout, system details, and hyperlane creation.
- `scene/galaxy/CustomStarSystem.gd`: Resource definition for custom handcrafted star systems.
- `button.gd`: Standalone script in the project root. It is currently outside the scene-specific folders.
- `icon.svg`: Project icon.

## Scene Flow

1. The project starts in `scene/MainMenue/MainMenue.tscn`.
2. `MainMenue.gd` gathers the seed, star count, shape, and hyperlane density.
3. The menu instantiates `scene/galaxy/galaxy.tscn` and passes the selected settings.
4. `galaxy.gd` uses `GalaxyGenerator.gd` to build the galaxy layout and render the results.

## Notes

- The `scene/` directory is now organized by scene so each scene keeps its own files together.
- The galaxy folder also contains shared gameplay scripts that are tightly coupled to galaxy generation.
- Godot resource paths in `project.godot`, `.tscn`, and `.gd` files were updated to match the new folder layout.
