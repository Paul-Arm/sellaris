# Two live design variants

PR #3 is the merged foundation. This revision keeps the same simulation and adds a local presentation preference:

| | 01 · Pastel / Painterly | 02 · Mission Control |
|---|---|---|
| Bodies | Detailed procedural planets, cloud shells, stars and asteroid belts | Limb-shaded spectral stars, seeded planetary surfaces, gas-giant/accretion rings and crisp labels |
| System space | Dark painted sky, orbital paths, soft pastel grading | Dark potential surface, anti-aliased contours, transported warm light |
| UI | Softer tinted surfaces; system summary visible | Slate panels, warm amber accents, fixed navigation rail, searchable object cards and a contextual system inspector |
| Galaxy | Nebula layers and colored stellar glows | Nebulae hidden, quieter stellar glows and cooler cores |

Select the design in **Settings** or press **F6**. The choice is saved to the existing local `user://settings.cfg`. It does not change saved campaigns or networking state. Camera focus, zoom, tilt, yaw and selected entity survive switching.

## Gravity map

The clean map uses the existing system body's XZ coordinates. Its displayed softened potential is a visual construction: a sum of inverse-distance wells with finite cores. It does not change gravity, ship movement, collision, orbit generation or command targeting. Body markers sit in their potential wells; their projected selection anchors use the identical visual height. Command contexts retain the original world coordinates. The original body inspector and command flow remain available.

## Direct map lighting and cascade reference

Design 02 omits orbital path meshes. Potential contours and the perspective grid remain part of its gravity-field surface.

`MapDirectLight.gdshaderinc` evaluates the angular extent of each circular emitter analytically at each surface fragment (`asin(radius / distance) / PI`). An isolated star therefore has rotationally symmetric illumination without the four-direction cascade reconstruction's petal artifacts. Angular blocker overlap supplies soft shadows. Multiple overlapping partial blockers use multiplicative visibility, an approximation; multiple stars naturally produce superimposed light fields. This remains map-plane direct lighting, not full 3D GI.

`RadianceCascade.gdshader` retains the previous four-cascade implementation as an opt-in research/diagnostic reference (`GravityFieldMap.configure(details, extent, true)`). The live map neither allocates nor samples its viewports. Its 256�256 atlases, analytical ray/circle tests and far-to-near merges can still be compared using the GPU harness. Transport covers up to 32 bodies, stars first; all markers remain visible.

## Verification

Run `GODOT_BIN=/path/to/godot bash tools/check_observatory.sh` for imports, presentation switching, selection/camera preservation, coordinate consistency, cleanup, state isolation and existing gameplay/network regressions.

The screenshot harness `res://tools/observatory_screenshot.tscn` captures matching menus, galaxies and systems in both modes, including the same binary-star fixture. It also verifies projected marker picking, nonzero transported radiance, reduced light behind an opaque planetary blocker and a zero-light empty-map baseline. Images and logs are attached to the PR's Godot Actions run. Compatibility rendering is exercised in CI; Forward+ should also be reviewed on the target GPU.


## Native resolution and dimensional relief (2026-09-05)

The system texture now renders at the final physical pixel size, including the root canvas stretch transform, instead of enlarging a viewport rendered at logical UI dimensions. A TextureRect displays that buffer; input and edge-pan coordinates explicitly map into the same pixel space. MSAA applies to existing and newly created 3D viewports, without resizing the window when changing AA. Display settings report the actual window size and restrict size selection to windowed mode; maximized/fullscreen use the display size. Window requests are constrained to the usable desktop.

The clean field retains its deterministic potential surface and command coordinates. Analytical potential gradients provide directional relief; a derivative-filtered grid adds perspective cues. Direct stellar illumination uses analytic circular emitter coverage; cascade buffers are reserved for diagnostics. Stars use spectral colors and limb shading. Planet patterns use seeded continuous 3D noise, with ice, land, dry, volcanic and gas palettes; gas worlds and black holes have tilted rings. Asteroid belts remain visible. Global bloom is reduced to protect contour and body definition.

Research reviewed:
- [Holographic Radiance Cascades, Freeman/Sannikov/Margel, May 2025](https://arxiv.org/abs/2505.02041): a 2D radiance-transfer method. A future replacement for the flatland transport, requiring a different interval reconstruction; this change does not claim to implement HRC.
- [Split Radiance Cascades, Freeman/Sannikov, July 2026](https://arxiv.org/abs/2607.20384): sparse world-space probes and ray splitting for 3D diffuse GI. An architectural follow-up for full scene GI, rather than a shader switch for this static map.

Validation: `res://tests/render_resolution_test.tscn` checks native buffers, effective settings, MSAA and real forwarded body clicks at 1280�720, 1920�1080 and 2560�1440, plus effective resolution and control state in windowed, maximized and fullscreen modes. `res://tests/design_variants_test.tscn` checks camera/selection preservation and resource cleanup. `res://tools/observatory_screenshot.tscn` renders both designs and verifies lit probes, occlusion and the empty-map baseline on the GPU.

The follow-up GPU test `res://tests/map_light_symmetry_test.tscn` checks 64 angles at eight radii against analytic light energy, plus blocker and empty-map baselines. Design-switch tests assert zero orbital path meshes in Clean and preserved paths in Pastel.


## Compact Field interface and pointer routing

Design 02 now uses native UI coordinates, 13px base text, restrained panel borders and compact control spacing. The system header, resource bar, command dock, menu navigation and inspectors use available window space; resource names/net values collapse into tooltips according to the budget per resource. Main menu content has a maximum width; long editors/settings/lobbies scroll inside their page. Body inspection is a right-hand card rather than a large centered preview. Planet/star shaders use smooth globes, readable terminators and subtle rims without procedural terrain patterns.

The system texture receives mouse input through `gui_input` and transforms local positions to render pixels. This bypasses the full-screen Control consuming events before the old unhandled-input router. The subviewport handles input locally. Right press starts a possible camera gesture; right release issues a command only when the pointer did not drag. Releases over other UI also end dragging. Wheel zoom and middle-drag panning remain available.

`res://tests/system_pointer_ui_test.tscn` sends window-level input via `Input.parse_input_event`, covering wheel, right-drag, right-click versus commands, middle-drag, release over UI, real body picking and inspector/system-info bounds at 960�540, 1280�720 and 1920�1080. `res://tests/clean_menu_layout_test.tscn` checks all four menu pages at 960�540. Captures are under `tools/screenshots/clean_ui_*.png` and `clean_menu_960_*.png`.


## Mission Control interface

Design 02 has its own UI components in `scene/UI/atlas/`: a main menu with top navigation, a fixed in-game navigation rail and economy strip, searchable operations cards, a system object index and a settings sidebar with Display / Audio / Map pages. Operations cards call the existing colony, station and fleet actions. Empire sections retain their gameplay controllers inside the new panel. The main menu's empire form changes its column count with available width; long pages scroll. The system index yields to the body inspector and its Objects button returns to the index.

The warm accent is shared by active navigation, actions and field contours. The perspective grid is restrained. The original design remains available, with borrowed controls and layout properties restored on switching. Shared modals block the system camera as well as the galaxy camera. Window mode and resolution labels reflect the actual OS window, including manual window changes.

`res://tests/atlas_navigation_test.tscn` verifies category panels at 1280x720 and 960x540, search, real colony/research/ship designer actions, settings tabs, modal camera blocking, object inspection, return to the galaxy and design restoration. `res://tests/clean_menu_layout_test.tscn` covers the four menu pages at 960x540. `res://tests/system_pointer_ui_test.tscn` covers real input events through 1920x1080. Rendered captures live in `tools/screenshots/`.


## Spacetime exits and luminous bodies

Mission Control now displays denser potential contours and cool, restrained stellar illumination. Clean planets use a luminous pearl/mint/ice/lavender palette with seeded broad surface variations and subtle gas bands; planetary ring meshes are removed. Black-hole accretion rings remain. Stellar marker radius is 3.7 times scale (previously 2.7), with the linked potential wells growing accordingly.

System detail presentation includes actual neighboring hyperlane destinations and their normalized galaxy XZ directions. Unknown destinations retain an uncharted label. Clean maps place exits outside the body region and apply compact local potential wells there, with outward cyan traces, arrowheads and destination labels. These do not affect simulation coordinates, body anchors or movement. The Routes filter and offscreen edge tags focus a connection in the camera. Initial framing and Recenter include more of the system.

The navigation integration test checks the actual graph endpoints, direction vectors and route focus. Design tests cover exit deformation outside body anchors, removal of planet rings, camera/selection preservation and cleanup; the real-input test passes at 960x540, 1280x720 and 1920x1080. GPU previews include a binary system with two hyperlane exits.


## Transparent spacetime and persistent route controls

The clean spacetime pass now draws only additive potential contours and hyperlane traces. The filled floor and perspective grid are removed; the pass never writes depth and fades radially before the mesh boundary. Empty regions reveal the scene background without a rectangular surface or body occlusion.

Hyperlane buttons remain visible when their projected destination enters the view, and clamp to the safe screen bounds when outside it. The floating topbar groups resources into compact cards and keeps the date, simulation status, pause and speed controls together. Resource deltas collapse into tooltips at narrow widths; the resource section can scroll while time controls remain available.

`res://tests/spacetime_transparency_test.tscn` compares GPU captures with and without the field: contours must be visible, most pixels must retain the background, and all outer edge pixels must remain unchanged. Navigation tests assert persistent route controls and topbar bounds at 960x540 and 1280x720. Window-level pointer tests pass through 1920x1080.


## Atmospheric clean systems

Clean systems now retain the per-system procedural sky with blue/violet nebula clouds and two restrained background star layers. The sky is directional and infinite, so it adds atmosphere without reintroducing a visible plane. The pastel sky parameters are preserved when switching designs.

Stars output HDR white cores with spectral tint and a soft rose-tinted corona. Camera-facing additive aura shaders use circular falloff to zero before their quad edges, write no depth, and breathe subtly with a seeded phase. Planets receive weaker tinted halos; hyperlane wells receive cyan halos. Potential contours brighten and take on the local stellar aura color around wells while their gaps remain transparent. Bloom is increased for clean systems, with no full-scene bloom pedestal.

GPU captures were reviewed for single and binary systems. The transparency regression passes with 9,586 changed pixels of 65,536 and no changed boundary pixels; design switching preserves camera, selection, command coordinates and effect cleanup. The existing GPU light transport and occlusion checks also pass.


The clean background now uses its own `GalacticSky.gdshader`: a tilted silver-blue galactic band with dark dust lanes and two fine star populations. Its directional structure is stationary and seeded per system. The previous blue-violet cloud background is replaced; stellar glow and spacetime effects are preserved. The original pastel sky remains separate. Single/binary GPU previews and the design-switch regression pass.
