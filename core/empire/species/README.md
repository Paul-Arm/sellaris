# Species Folder Convention

Species are auto-discovered from subfolders inside this directory.

## Layout

Create species like this:

`core/empire/species/<archetype>/<species_id>/`

Example:

`core/empire/species/organic/humanoid/`

## Optional files

- `species.cfg`
- `menu_portrait.png|jpg|webp|svg`
- `menu/` with one portrait image inside
- `leaders/` with one or more leader portrait images

## `species.cfg`

Use a `[species]` section. All keys are optional.

```ini
[species]
display_name="Humanoid"
species_name="Humanoid"
species_plural_name="Humanoids"
species_adjective="Humanoid"
species_visuals_id="organic/humanoid"
name_set_id="humanoid_names"
menu_portrait="menu_portrait.svg"
```

## Discovery rules

- Archetypes come from the first folder level, like `organic` or `machine`.
- Species types come from the species folder name, like `humanoid` or `aquatic`.
- If `menu_portrait` is not set, the loader looks for `menu_portrait.*`, `portrait.*`, `menu.*`, or the first image in `menu/`.
- Leader portraits come from all images in `leaders/`.
- If there are no leader portraits, the menu portrait is reused as a fallback.
