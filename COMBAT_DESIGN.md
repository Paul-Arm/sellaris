# Combat & Ship Component System — Design Plan

Status: **All phases (A–D) implemented**. Phase A: components, designs, unlocks, design-based costs/upkeep, int hull migration (`core/space/design/`). Phase B: deterministic combat core (`core/space/combat/CombatSystem.gd`) — stances, auto-engage, battle lifecycle, day-tick rounds, manual abilities (shockwave), event log, snapshot support. Phase C: combat frontend — event-driven VFX in the system view (`scene/StarSystem/SystemCombatEffectsRenderer.gd`: beams, explosions, shockwave rings), battle ring indicators on the galaxy map, and combat UI in the entity details panel (shield/armor/stance/battle facts, stance toggle for units and fleets, manual ability buttons with cooldown/pending state). Phase D: ship designer UI (`scene/game/ShipDesignerModal.gd`, opened from the empire command drawer's "Schiffsdesign" category) — hull picker, slot dropdowns filtered by unlocks/applicability, live compiled stats + translated validation errors, save/rename/set-default/delete; shipyard stations list one build button per design in the entity details panel. This document is the agreed target design for combat, ship components, and the ship designer.

Phase A deviations from the original plan:
- Hull fields keep their names (`max_hull_points`/`current_hull_points`) but are now `int` — the `*_sp` rename was skipped to limit churn across panels/renderers.
- Per-unit upkeep economy sources already existed (`unit:<unit_id>`, kind `space_unit_upkeep`); Phase A switched their amounts to compiled design upkeep instead of adding a new aggregated source.
- Ship production runs through `SpaceManager.get_ship_build_options()` / `request_build_ship()` on shipyard stations (basic + stellar station carry a `builder_component` with build tag `ship`); ship build orders commit design costs by default.

Follow-up additions (post Phase D):
- **Notification system** (`scene/UI/NotificationCenter.gd`): reusable right-edge stack with importance levels 1–4 (1–3 auto-expire after configurable real-time lifetimes, 4 persists until dismissed), per-card dismiss, optional embedded custom Controls, and click actions routed by `GameSceneUiController._on_notification_activated` (`open_system`, `select_space_entity`). Combat events post notifications for the active empire in `GameSceneRuntimeSystem._post_combat_notifications` (battle started lvl 3, own ship lost lvl 4, enemy kill lvl 2, battle ended lvl 2).
- **Fleet combat menu** (`scene/UI/BattleOverviewPanel.gd`): reusable battle view (aggregated per-empire hull/shield bars, member list, event-log tail) embedded by `SpaceEntityDetailsPanel` whenever the clicked unit/fleet is in a battle; refreshes with the existing per-tick selection panel refresh.
- Debug spawner gained a "Spawn Enemy Fleet" button that spawns armed corvettes (default designs via `bootstrap_empires`) for a non-player empire.

Phase D notes:
- The designer edits a draft (`compile_ship_design_draft`/`validate_ship_design_draft` on `SpaceManager`) and only persists through `create_ship_design`/`update_ship_design`, so invalid loadouts can never be saved.
- Default designs cannot be deleted; designs referenced by live units cannot be deleted either (`remove_ship_design` refuses both).
- `get_ship_build_options()` now returns one entry per saved design (class fallback only when an empire has no design for a buildable hull), so shipyard build menus are design-driven.

Phase C notes:
- `SpaceManager.combat_events` is routed through `GameSceneRuntimeSystem._on_space_combat_events`: it forwards events to the open system view (which filters by its current system) and queues the shared runtime visual refresh (galaxy markers + panels).
- Combat VFX are transient meshes under the system preview's runtime effects root, tweened over roughly one real-time sim day and cleared automatically on runtime refreshes — gameplay state is never read back from them.
- Galaxy battle indicators are a lazily created `MultiMeshInstance3D` on `GalaxyMapView` fed from the battle registry during `render_runtime_placeholders()`.

Phase B deviations from the original plan:
- Hit rolls hash a **battle-local round counter** instead of the global day serial, so combat stays deterministic regardless of SimClock state (and is reproducible in headless tests that drive `_on_sim_day_tick` directly).
- Passive stance only gates battle *initiation* and pursuit movement; once a unit is pulled into a battle, armed members return fire regardless of stance. Unarmed members flee in-system; the emergency hyperlane jump for cornered civilians is deferred (fleeing already escapes via the disengage radius when the drive is fast enough).
- Combat movement (closing to weapon range, fleeing) repositions units once per day without setting `movement_state` — Phase C interpolates visuals from the combat event stream instead.
- One battle per system; new hostiles entering the system join the existing battle. The battle ends when no armed member has a hostile within `auto_engage_radius * 1.5`.

## 1. Goals & Principles

1. **Deterministic backend, cosmetic frontend.** All combat decisions run in the `SimClock` day tick with integer math and seeded/hashed rolls (same pattern as `ResourceDepositComponent`). The frontend only interpolates between tick states and plays back an event log — it never makes gameplay decisions. This keeps the door open for lockstep/server-authoritative multiplayer and replays.
2. **One vessel abstraction.** "Ship" always means the abstract case: ships, stations, and later creatures share the same component/slot/design model. Components declare their own applicability (e.g. drives require mobility), so stations simply never mount drives.
3. **Data-driven content.** Component definitions live in a `.cfg` file like `jobs.cfg`/`buildings.cfg`. Slot layouts live on the unit class. New weapons/shields/abilities are content, not code.
4. **Commands, not direct calls.** Manual ability triggers (e.g. shockwave button) are queued as commands and executed on the next day tick. This establishes the command-queue pattern needed for multiplayer and the AI.

## 2. Component Model

New definition type: `ShipComponentDefinition` (`core/space/design/ShipComponentDefinition.gd`), loaded from `core/space/design/ship_components.cfg`.

Every component has **passive stats**; some additionally have an **ability** (auto or manual):

```ini
[basic_laser]
display_name="Basic Laser"
slot_kind="weapon"
slot_size="medium"            ; schema supports small/medium/large, v1 content uses medium only
unlock_tier=0                  ; tier 0 = unlocked for every empire at game start
allowed_unit_kinds=["ship", "station"]
requires_mobility=false
build_cost={"alloys": 40.0}
monthly_upkeep={"energy": 1.0}
build_time_days_add=4
stats={}                       ; passive stat contributions (see stat keys below)
weapon={
  "damage": 12,                ; integer structure points per hit
  "cooldown_days": 2,
  "range": 14.0,               ; system-local units, quantized for combat checks
  "accuracy_bp": 8500,         ; basis points, vs target evasion_bp
  "shield_damage_bp": 10000,   ; 100% vs shields
  "armor_penetration_bp": 0
}

[basic_shield_emitter]
slot_kind="defense"
unlock_tier=0
stats={"shield_add": 60, "shield_regen_per_day": 4}

[basic_armor_plating]
slot_kind="defense"
unlock_tier=0
stats={"armor_add": 8}        ; flat damage reduction per hit, after shields

[basic_drive]
slot_kind="drive"
unlock_tier=0
requires_mobility=true         ; only mountable on hulls with a mobility component
stats={"cruise_speed": 22.0, "evasion_bp": 500, "combat_speed": 9.0}

[shockwave_emitter]            ; example tier-1 manual active
slot_kind="utility"
unlock_tier=1
stats={}
ability={
  "trigger": "manual",         ; "auto" abilities fire by rule inside combat resolution
  "effect_id": "shockwave",    ; resolved against a small scripted-effect registry
  "cooldown_days": 30,
  "radius": 10.0,
  "params": {"damage": 25, "stun_days": 2}
}
```

Component categories ("aktiv/passiv" mapping):

| Kind | Behavior |
|---|---|
| Passive | Only `stats` — hull/shield/armor/speed/evasion/sensor contributions. |
| Active (auto) | Weapons and auto-abilities used by the combat resolver (`weapon` block or `ability.trigger="auto"`). |
| Active (manual) | `ability.trigger="manual"` — exposed as a UI button, queued as a command, executed next tick. |

Stat keys (all integers or basis points except speeds/ranges): `hull_add`, `shield_add`, `shield_regen_per_day`, `armor_add`, `evasion_bp`, `cruise_speed`, `combat_speed`, `auto_engage_radius_add`, `sensor_range_add`.

### Applicability

- `requires_mobility=true` → only valid on hulls whose class has a mobile `SpaceUnitMobilityComponent` (drives).
- `allowed_unit_kinds` → restrict to `ship` / `station` / `creature`.
- Slot kind + size must match the slot being filled.

**Drive ownership change:** hull speed moves from `SpaceUnitMobilityComponent.cruise_speed` into the drive component's stats. The mobility component keeps the capability flags (`is_mobile`, `can_join_fleets`, `uses_hyperlanes`); the drive determines *how fast*. Mobile hulls mark their drive slot `required=true`, so a design without a drive does not validate.

## 3. Slot Layouts per Hull

Reuses the existing `SpaceUnitClass.component_slots` schema (`slot_id`, `slot_kind`, `required`, `metadata`). New slot kinds: `weapon`, `defense`, `utility` (alongside the existing `drive`, `construction`, `science`, `addon`). `metadata.size` carries the slot size.

Initial layouts:

| Hull | Slots |
|---|---|
| **Corvette** (new, `unit_kind=ship`, `category=combat`) | 2× weapon, 1× defense, 1× utility, 1× drive (required) |
| Science Ship | 1× defense, 1× utility, 1× drive (required), science (existing) |
| Builder Ship | 1× defense, 1× utility, 1× drive (required), construction (existing) |
| Station / Stellar Station | 2× weapon, 2× defense, 2× utility |
| Sammelstation (collector) | 1× weapon, 1× defense, 1× utility |

Bigger combat hulls (frigate, cruiser, …) come later and only need new class entries + slot lists — no new code.

## 4. Ship Designs

New layer between unit class and unit runtime, kept inside `SpaceManager` as an owned module (no new autoload): `core/space/design/ShipDesignCatalog.gd`.

- `ShipDesignRuntime`: `design_id`, `empire_id`, `class_id`, `display_name`, `slot_assignments: {slot_id → component_id}`, `revision`.
- `DesignCompiler` validates (slot kind/size match, applicability, required slots filled, all components unlocked for the empire) and compiles cached `DesignStats`:
  - `max_hull_sp`, `max_shield_sp`, `shield_regen_sp`, `armor_sp`, `evasion_bp`
  - `cruise_speed`, `combat_speed`
  - `auto_engage_radius`
  - `weapons: Array` (resolved weapon blocks with slot ids)
  - `abilities: Array` (auto + manual)
  - `build_cost`, `build_time_days`, `monthly_upkeep` (= hull base + sum of components)
- **Default designs**: at bootstrap each empire gets auto-generated designs from tier-0 components ("Corvette Mk I", default station loadouts). Construction orders reference a `design_id`; bare `class_id` falls back to the empire's default design for that class.
- Designs are part of the `SpaceManager` snapshot.

### Integer combat stats

`max_hull_points: float` on `SpaceUnitClass` is migrated to integer **structure points (sp)**. All combat quantities (hull, shield, armor, damage) are `int`. This is a prerequisite for deterministic combat and a small breaking change to do *before* combat lands.

## 5. Unlocks

Tech doesn't exist yet, so unlocks get a thin abstraction that a future tech tree plugs into:

- Per-empire unlock set, stored with the empire record and included in snapshots: `unlocked_component_ids`.
- Bootstrap: every empire gets all `unlock_tier=0` components (basic weapons, shields, drives — per requirement "Zu Beginn starten alle mit basic Waffen, Schilden und Antrieben").
- API on `SpaceManager`/empire state: `is_component_unlocked(empire_id, component_id)`, `unlock_component(empire_id, component_id)` (emits signal → designer UI refresh).
- Anomaly research outcomes can call `unlock_component` immediately; the tech tree later becomes the main driver.

## 6. Unit Runtime Extensions

`SpaceUnitRuntime` gains:

- `design_id`
- `current_hull_sp`, `current_shield_sp` (int)
- `stance`: `"aggressive"` | `"passive"` (default by category: combat → aggressive, civilian/support → passive)
- `auto_engage_radius` (from design stats; utility components can extend it)
- `weapon_cooldowns: {slot_id → days_remaining}`, `ability_cooldowns: {slot_id → days_remaining}`
- `battle_id` (empty when not in combat)
- `pending_ability_commands: Array[Dictionary]` (manual triggers queued from the UI)

Stance is settable per unit and per fleet (fleet setter fans out to members).

## 7. Battle Lifecycle (deterministic core)

New module `core/space/combat/CombatSystem.gd` (RefCounted, owned and ticked by `SpaceManager._on_sim_day_tick` **after** movement/hyperlane resolution).

### Hostility (stub until diplomacy exists)

`HostilityPolicy`: default **free-for-all** — every other empire is hostile. Configurable at galaxy setup (e.g. "peaceful sandbox" toggle for testing). Later replaced by a diplomacy/war state without touching the combat resolver.

### Detection & engagement

Per system that contains units of ≥2 mutually hostile empires:

- **Aggressive** units engage any hostile unit inside their `auto_engage_radius` → opens a new battle or joins the system's existing battle.
- **Passive** units never initiate. They join a battle only when fired upon (return fire); civilians instead attempt to flee (move away, then emergency hyperlane jump out after `FLEE_DELAY_DAYS`).

### Round resolution — one round per sim day

Stellaris-style: battles run across several in-game days; at 4× game speed they resolve quickly in real time. Per day tick, in this fixed order (units always iterated sorted by `unit_id`):

1. **Apply queued manual ability commands** (sorted by command id), respecting cooldowns; emit ability events.
2. **Target selection** — deterministic: nearest hostile in weapon range, tiebreak by lowest `unit_id`; retarget on target death/disengage.
3. **Combat movement** — mobile units close to weapon range at `combat_speed`; stations are static.
4. **Weapon fire** — each weapon off cooldown fires at the unit's target if in range. Hit roll: stable hash `(galaxy_seed, battle_id, day_serial, attacker_id, slot_id) % 10000` vs `accuracy_bp − target.evasion_bp`. Damage pipeline: shields (× `shield_damage_bp`) → remaining minus `armor` flat reduction (modified by `armor_penetration_bp`) → hull.
5. **Shield regen** for units not hit this round.
6. **Deaths** — `current_hull_sp ≤ 0` → unit destroyed via `remove_unit` (cleans fleets, economy sources, colonies), kill event emitted.
7. **Battle end** — one side has no combat-capable units left, or all remaining hostiles are outside mutual engage range (disengaged/fled).

### Determinism rules

- Integer math for all damage/HP; basis points for percentages (matches `EconomyManager` conventions).
- Range/radius checks on **quantized positions**: `int(round(local_position * 1000))` per axis, integer squared-distance comparison. No raw float comparisons in combat decisions.
- All randomness via stable hashes of sim identifiers — no `RandomNumberGenerator` state in combat.
- Every battle appends to a per-day **event log** (`Array[Dictionary]`); hashing the log enables determinism regression tests and, later, multiplayer desync detection.

## 8. Manual Actives — UI → Command → Sim

```
UI button (details panel / battle bar)
  → GameSceneRuntimeSystem.request_unit_ability(unit_id, slot_id, target?)
  → SpaceManager.queue_unit_ability_command(...)   ; appended, validated (owner, cooldown)
  → executed next day tick (battle step 1)
  → ability event in combat log → VFX + cooldown overlay in UI
```

No immediate state mutation from the UI — this is the first real command-queue path and the template for migrating other orders later (multiplayer/AI groundwork).

## 9. Frontend (interpolation & playback only)

- `SpaceManager`/`CombatSystem` emits `combat_events(batch: Array[Dictionary])` per day tick: `shot`, `hit`, `shield_hit`, `miss`, `kill`, `ability`, `battle_started`, `battle_ended` — each with unit ids and positions.
- **SystemView**: beams/projectiles tweened between the units' interpolated positions over the real-time span of the sim day (`get_interpolated_local_position` already exists); shield flash on `shield_hit`; explosion + marker removal on `kill`; shockwave ring on `ability`.
- **GalaxyMapView**: battle indicator on systems with active battles.
- **Battle UI**: aggregated side hull/shield bars, per-unit readout in `SpaceEntityDetailsPanel` (hull/shield/armor, stance toggle, manual ability buttons with cooldown).
- Game speed/pause behave like everything else — visuals stretch with the day length; pausing freezes playback.

## 10. Economy Integration

- Design `build_cost`/`build_time` replace the bare class costs in construction orders (`can_afford`/`commit_cost` flow unchanged).
- **Fixes the upkeep gap**: on spawn, each unit's design `monthly_upkeep` is registered as an `EconomyManager` source (aggregated per empire as one `unit_upkeep` source updated on spawn/death, to keep source counts low). Destroyed units stop costing upkeep automatically.

## 11. Initial Content

- **Tier 0 (everyone starts with):** `basic_laser`, `basic_shield_emitter`, `basic_armor_plating`, `basic_drive`.
- **Tier 1 (proves the unlock path):** `pulse_laser_mk2`, `deflector_mk2`, `ion_drive_mk2`, `shockwave_emitter` (manual AoE).
- **New hull:** Corvette. Buildable by stations: station classes get a `builder_component` with `buildable_tags=["ship"]` (shipyard role), reusing the existing construction-project pipeline.
- Existing hulls (science/builder/stations) get slot layouts and default designs so upkeep/designs apply uniformly.

## 12. Implementation Phases & Tests

Each phase is shippable and headless-testable in the existing `tests/` style.

**Phase A — Components & Designs (no combat yet)**
Component definitions + loader, new slot kinds on classes, design catalog + compiler, default designs, unlock stub, hull → int migration, design-based build costs, unit upkeep economy source.
Tests: `ship_design_compiler_test.gd` (validation rules + compiled stats), `component_unlock_test.gd`, `unit_upkeep_economy_smoke_test.tscn`.

**Phase B — Combat Core**
Stances + auto-engage detection, battle lifecycle, deterministic round resolution, deaths, fleeing civilians, hostility stub, combat event log.
Tests: `combat_resolution_test.gd` (scripted 2v1, assert exact outcome), `combat_determinism_test.gd` (same seed → identical event-log hash across two runs).

**Phase C — Combat Frontend**
Event-driven VFX in SystemView, galaxy battle indicators, battle UI, stance toggle, manual ability buttons (command path included).
Tests: `combat_events_smoke_test.tscn` (events render without errors), panel smoke test extension.

**Phase D — Ship Designer UI**
Designer scene: hull picker → slot grid → component palette (filtered by unlocked + applicability) → live stats preview → save/clone designs per empire. Construction menus list designs instead of classes.
Tests: designer smoke test; design persistence in runtime snapshot.

## 13. Decisions Assumed (flag if you disagree)

1. **One combat round per sim day** (Stellaris-like, multi-day battles) — no sub-day combat clock.
2. **Free-for-all hostility** until diplomacy exists.
3. **Component data in `.cfg`** (matches jobs/buildings), not `.tres`.
4. **No new autoload** — design catalog and combat system are modules owned by `SpaceManager`.
5. **Slot sizes** exist in the schema from day 1 but v1 content uses a single size.
6. **Hull HP becomes int** (structure points) as part of Phase A.
