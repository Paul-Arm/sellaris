# Research System

Draft-based empire research: each **domain** (discipline) deterministically
offers a weighted hand of technologies; picking one starts a project that
drains the shared `research` resource stockpile day by day. Completions build
**momentum** on the tech's tags (related techs draft more often and start
cheaper), and external events grant **inspirations** (one-shot discounts and
draft boosts). All content is data-driven for mod support.

## Files

- `domains.cfg` - the disciplines (deck definitions).
- `techs/*.cfg` - every file in this directory is loaded and merged. Mods add
  techs by dropping a new `.cfg` file here; files are read in alphabetical
  order and later files override earlier section ids (a warning is logged).
- `ResearchCatalog.gd` - loading, validation, eligibility, deterministic
  drafts, and cost quotes.
- `ResearchEmpireState.gd` - per-empire runtime state (snapshot-friendly).
- `ResearchAdvisor.gd` - deterministic option scoring for AI empires.
- `autoload/ResearchManager.gd` - orchestration, day-tick progress, effects.

Runtime registration (e.g. from a mod's autoload) is also supported:

```gdscript
ResearchManager.register_domain_dict("biotech", {"display_name": "Biotechnik", "sort_key": 40})
ResearchManager.register_tech_dict("gene_forges", {
    "domain": "biotech",
    "cost": 150.0,
    "tags": ["biotech", "food"],
    "effects": [{"type": "monthly_resources", "resources": {"food": 4.0}}],
})
```

## Domain format (`domains.cfg`)

```ini
[industry]
display_name="Industrie & Materie"
description="..."
color="#d9954a"
sort_key=10
base_slots=1                      ; parallel projects without slot techs
draft_size=3                      ; options per draft
tier_requirements=[0, 2, 5]       ; completed techs in the domain per tier
momentum_weight_bonus_bp=1200     ; draft weight bonus per momentum level
momentum_discount_bp=300          ; cost discount per momentum level
momentum_discount_cap_bp=3000     ; cap for the momentum discount
```

## Tech format (`techs/*.cfg`)

```ini
[orbital_extraction_rigs]
display_name="Orbitale Foerderplattformen"
description="..."
domain="industry"                 ; required, must exist
tier=1                            ; gated by the domain's tier_requirements
cost=260.0                        ; decimal research units (milliunits at load)
min_days=45                       ; hard minimum duration (daily intake cap)
weight=900                        ; base draft weight (0 = never drafted)
sort_key=0
tags=["industry", "matter"]       ; momentum/inspiration matching
rarity="common"                   ; "common" | "rare" (UI highlight)
requires=["efficient_extraction"] ; hard tech prerequisites
exclusive_group=""                ; completing one tech locks the group
max_level=1                       ; 0 = infinitely repeatable
repeat_cost_growth_bp=2500        ; cost growth per repeat level
effects=[...]                     ; see below
ai_hints={"roles": {"economy": 1.1}}
```

### Effect types

| Type | Payload | Result |
| --- | --- | --- |
| `unlock_component` | `component_id` | Unlocks a ship component (`SpaceManager.unlock_ship_component`) |
| `unlock_building` | `building_id` | Unlocks a colony building gated via `requires_tech` in `buildings.cfg` |
| `grant_resources` | `resources={"energy": 40.0}` | One-time stockpile grant |
| `monthly_resources` | `resources={...}` | Registers a permanent economy source (kind `research_tech`) |
| `modifier` | `key`, `value_bp` | Accumulates a per-empire modifier; query via `ResearchManager.get_modifier_bp()` |
| `research_slot` | `domain` ("" = all), `amount` | Additional parallel project slots |
| `custom` | `effect_id`, free payload | Emits `tech_effect_requested(empire_id, tech_id, effect)` for game code/mods |

Building gating: add `requires_tech="<tech_id>"` to a section in
`core/economy/buildings/buildings.cfg` and unlock it with an
`unlock_building` effect carrying the building id.

## Mechanics reference

- **Progress**: each day every active project drains
  `min(remaining, ceil(total_cost / min_days), stockpile)` research milliunits
  via the EconomyManager. Banked research helps, but a project never finishes
  faster than `min_days`. Domains drain in alphabetical order.
- **Drafts** are seeded with
  `"<galaxy_seed>:<empire_id>:<domain_id>:<serial>:draft"`, so they are
  reproducible per save and refresh after every pick and completion.
- **Momentum**: +1 per tag of every completed tech. Discounts and weight
  bonuses are configured per domain (see above).
- **Inspirations**: `ResearchManager.add_inspiration(empire_id, tags,
  discount_bp, weight_bonus_bp, source, expires_in_days)`. The best matching
  inspiration is consumed when a matching project starts. Anomalies grant them
  through the `research_inspiration` outcome (see `core/anomaly/AnomalyPool.gd`).
- **Tiers**: tier N unlocks once `tier_requirements[N]` techs of the domain
  are completed; the list extends linearly past its end.

## AI support

`ResearchAdvisor.rank_options(options, context, persona)` scores the option
dictionaries returned by `ResearchManager.get_draft_options()` -
deterministically, with human-readable `reasons`. Convenience wrappers:

- `ResearchManager.rank_draft_options(empire_id, domain_id, persona)`
- `ResearchManager.auto_pick_project(empire_id, domain_id, persona)`
- `ResearchManager.auto_pick_all(empire_id, persona)`

Personas are plain dictionaries (role weights plus knobs like
`cost_aversion`, `discount_affinity`, `specialist_affinity`,
`bottleneck_relief`), so future AI empire profiles can live in data files.
The default context feeds `EconomyManager.get_bottleneck_resource()` so
advisors favor techs that relieve the current shortage.

## Tests

- `tests/research_catalog_test.gd` - loading, mod registration, eligibility,
  deterministic drafts, quotes, state snapshots.
- `tests/research_advisor_test.gd` - deterministic scoring and personas.
- `tests/research_manager_smoke_test.tscn` - end-to-end loop against the
  live autoloads.
