# Two live design variants

PR #3 is the merged foundation. This revision keeps the same simulation and adds a local presentation preference:

| | 01 · Pastel / Painterly | 02 · Clean / Gravity Field |
|---|---|---|
| Bodies | Detailed procedural planets, cloud shells, stars and asteroid belts | Smooth luminous star markers, restrained planet markers and labels |
| System space | Dark painted sky, orbital paths, soft pastel grading | Dark potential surface, anti-aliased contours, transported warm light |
| UI | Softer tinted surfaces; system summary visible | Neutral surfaces, square corners; summary available through System info |
| Galaxy | Nebula layers and colored stellar glows | Nebulae hidden, quieter stellar glows and cooler cores |

Select the design in **Settings**, in a system's header, or press **F6**. The choice is saved to the existing local `user://settings.cfg`. It does not change saved campaigns or networking state. Camera focus, zoom, tilt, yaw and selected entity survive switching.

## Gravity map

The clean map uses the existing system body's XZ coordinates. Its displayed softened potential is a visual construction: a sum of inverse-distance wells with finite cores. It does not change gravity, ship movement, collision, orbit generation or command targeting. Body markers sit in their potential wells; their projected selection anchors use the identical visual height. Command contexts retain the original world coordinates. The original body inspector and command flow remain available.

## Radiance cascades

`scene/StarSystem/design/RadianceCascade.gdshader` implements four **2D map-space radiance cascades**, not a blur of the finished screenshot:

- Each 128×128 atlas stores directional radiance and transmittance. Probe grids are 64², 32², 16² and 8²; directions per probe are 4, 16, 64 and 256.
- Intervals grow by four while probe spacing doubles. Analytical ray/circle intersections find emissive stars and opaque planetary occluders.
- A far-to-near merge averages four angular intervals and interpolates the next cascade's four neighboring probes. The potential-surface shader integrates cascade zero to illuminate the map and its contours.
- Four ordered one-shot viewport renders run when a clean system map is built. The buffers remain idle afterwards and are freed on a system/design change. The map uses a fixed mesh budget of approximately 74,000 triangles.

This is a bounded flatland emitter/occluder solution for the tactical map. It is **not full 3D multi-bounce GI** for ships and planets. Standard probe interpolation can leak light near occluder edges. The transport and well uniforms cover 32 bodies, with stars first; all body markers remain visible in unusually larger systems. Runtime ships, projectiles and moving effects are not included in the static lighting bake. Black-hole colors represent an artistic accretion glow.

Algorithm reference: [Alexander Sannikov's Radiance Cascades paper](https://github.com/Raikiri/RadianceCascadesPaper/blob/main/RadianceCascades.tex). The shaders here are a project-specific implementation, without copied shader code or reference-image assets.

## Verification

Run `GODOT_BIN=/path/to/godot bash tools/check_observatory.sh` for imports, presentation switching, selection/camera preservation, coordinate consistency, cleanup, state isolation and existing gameplay/network regressions.

The screenshot harness `res://tools/observatory_screenshot.tscn` captures matching menus, galaxies and systems in both modes, including the same binary-star fixture. It also verifies projected marker picking, nonzero transported radiance, reduced light behind an opaque planetary blocker and a zero-light empty-map baseline. Images and logs are attached to the PR's Godot Actions run. Compatibility rendering is exercised in CI; Forward+ should also be reviewed on the target GPU.
