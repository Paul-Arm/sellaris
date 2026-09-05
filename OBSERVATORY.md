# Observatory revision

This revision gives the active Godot game a consistent visual language and replaces the multiplayer placeholder with a real direct-connect lobby.

## Play and connect

Open `project.godot` with Godot 4.6.1 or a compatible newer Godot 4 release. Run the normal main scene. Singleplayer still follows the existing galaxy setup and campaign flow.

For the lobby, run two instances of the same revision:

1. Open Multiplayer, enter a callsign and choose **Host lobby**.
2. On the second instance, enter the host's LAN/private VPN IP and choose **Join lobby**. Use `127.0.0.1` when both instances run on one machine.
3. Both instances show the server-owned roster. **Mark ready** synchronizes readiness. **Disconnect** frees the slot. The default transport is UDP port **24560**, configurable in the form.

The lobby supports six commanders, protocol matching, slot reuse, a ten-second connection/registration timeout, host disconnect feedback and clean transport teardown. Launching singleplayer closes an existing lobby.

**A connected lobby is not yet a synchronized multiplayer campaign.** Campaign launch is intentionally unavailable. The current managers expose direct mutable operations, and simply synchronizing a galaxy seed would produce divergent games. The UI states the current scope explicitly.

## Visual direction

- `scene/UI/theme/ObservatoryTheme.tres`: shared surfaces, typography sizes, input and selection states, visible keyboard focus and semantic title/caption/primary variants. Applied as the project theme, including dynamically created UI.
- `ObservatoryStyle.gd`: common colors for existing modal and HUD style factories. Warning, resource and empire colors retain their meanings.
- Menus: cinematic procedural planetary backdrop, cleaner product copy, selected navigation, expedition setup and a scrolling lobby roster. A 1600×900 logical canvas scales to smaller windows and expands on wider displays.
- Galaxy: darker background, muted nebulae, finer hyperlanes and less saturated star cores. Existing fog-of-war and ownership behavior remain intact.
- System view: continuous light falloff, deep planetary nights, narrow terminators, smaller ocean glints, quieter sky and less washed-out postprocessing. Surface seeds and their RNG draw order are unchanged.
- Ships: the new `observatory` set is active on startup. It has faceted alloy hulls, distinct military hull sizes, a sensor ring on science vessels, construction arms/cargo on builders and ring stations. Separate hull and illumination surfaces preserve MultiMesh instancing. Existing sets remain selectable through `ShipSetRegistry`.
- HUD: a static full-width command rail replaces continuously animated chrome. Resource states, research, ship design, colony management, body/entity panels and notifications share the new style.

The procedural shader and geometry assets are project-owned and require no external texture download.

## Gameplay fix

Body-targeted station construction now passes `commit_cost: true` at the player-facing runtime boundary. Ownership is checked before issuing the order. The existing SpaceManager payment path rejects unaffordable builds and charges accepted ones exactly once. Low-level debug/test builders retain their explicit options.

## Verification

On Linux, with Godot available:

```sh
GODOT_BIN=/path/to/godot bash tools/check_observatory.sh
```

The suite imports the project, checks lobby validation and geometry budgets, runs existing deterministic celestial, construction, ship, research and drawer tests, and launches separate host/client processes to exercise real ENet registration, readiness and disconnect cleanup. A station-cost regression checks exact debits, ownership, duplicate rejection and insufficient funds.

Windowed screenshot harness:

```sh
godot --path . res://tools/observatory_screenshot.tscn
```

The `Godot prototype checks` PR workflow performs these checks and attaches logs/screenshots as `godot-review`. Screenshots use the compatibility renderer on the CI machine; Forward+ visual review on the target GPU remains useful for bloom and spatial shader quality.

## Next multiplayer milestone

1. Introduce typed gameplay commands with server-side ownership, intel, cost and target validation. All UI actions must route through the same interface.
2. Assign empire IDs from lobby slots on the host and replicate a complete initial state, including clock, research, design/unlock state and deterministic counters.
3. Advance simulation only on the host; replicate versioned deltas, acknowledgements and resynchronization snapshots. Filter hidden intel before sending it.
4. Add reconnect, loading barriers and multi-client campaign regression tests before exposing campaign launch.

Networking API reference: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
