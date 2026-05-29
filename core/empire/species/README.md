# Species Folder Convention

Species are auto-discovered from subfolders in this directory and shown in the main menu empire preset editor.

## Layout

Create species like this:

```text
core/empire/species/<archetype>/<species_id>/
```

Examples:

```text
core/empire/species/organic/humanoid/
core/empire/species/organic/aquatic/
core/empire/species/machine/machine/
```

## Optional Files

- `species.cfg`
- `menu_portrait.png|jpg|jpeg|webp|svg`
- `menu/` with one portrait image inside
- `leaders/` with one or more leader portrait images

## `species.cfg`

Use a `[species]` section for display data and an optional `[traits]` section for trait ids. All keys are optional.

```ini
[species]
display_name="Humanoid"
species_name="Humanoid"
species_plural_name="Humanoids"
species_adjective="Humanoid"
species_visuals_id="organic/humanoid"
name_set_id="humanoid_names"
menu_portrait="menu_portrait.svg"

[traits]
ids=["technical","adaptive"]
```

## Discovery Rules

- Archetypes come from the first folder level, such as `organic` or `machine`.
- Species types come from the species folder name, such as `humanoid`, `aquatic`, or `machine`.
- `species_visuals_id` defaults to `<archetype>/<species_id>`.
- If `menu_portrait` is relative, it is resolved relative to the species folder.
- If `menu_portrait` is not set, the loader looks in `menu/` first, then for `menu_portrait.*`, `portrait.*`, or `menu.*` in the species folder.
- Leader portraits come from all supported images in `leaders/`.
- If there are no leader portraits, the menu portrait is reused as the leader fallback.
- Trait ids are read from `[traits] ids=[...]` and should match definitions in `core/empire/species/traits/traits.cfg`.

## Runtime Use

- `SpeciesLibrary.gd` returns catalog entries for the preset UI.
- `EmpirePresetManager.gd` stores selected species, portrait paths, and empire customization in `user://empire_presets/*.json`.
- `ColonyManager.gd` turns empire records into `SpeciesRuntime` entries when a game starts.
- Colony jobs use species trait ids for habitability, job output, and upkeep modifiers.
