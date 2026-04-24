extends RefCounted
class_name GameSceneState

const GALAXY_GENERATOR_SCRIPT: Script = preload("res://scene/galaxy/GalaxyGenerator.gd")
const GALAXY_STATE_SCRIPT: Script = preload("res://scene/galaxy/GalaxyState.gd")
const EMPIRE_FACTORY_SCRIPT: Script = preload("res://scene/galaxy/EmpireFactory.gd")

var seed_text: String = ""
var generated_seed: int = 0
var star_count: int = 900
var galaxy_radius: float = 3000.0
var min_system_distance: float = 48.0
var spiral_arms: int = 4
var galaxy_shape: String = "spiral"
var hyperlane_density: int = 2
var ownership_bright_rim_enabled: bool = true
var ownership_core_opacity: float = 0.0
var custom_systems: Array[Resource] = []
var system_positions: Array[Vector3] = []
var system_records: Array[Dictionary] = []
var hyperlane_links: Array[Vector2i] = []
var hyperlane_graph: Dictionary = {}
var generation_settings: Dictionary = {}
var selected_starting_empire_id: String = ""
var selected_starting_empire_preset_name: String = ""
var systems_by_id: Dictionary = {}
var system_indices_by_id: Dictionary = {}
var empire_records: Array[Dictionary] = []
var empires_by_id: Dictionary = {}
var active_empire_id: String = ""
var debug_reveal_galaxy: bool = false
var selected_system_id: String = ""
var hovered_system_id: String = ""
var pinned_system_id: String = ""
var is_generating: bool = false
var empire_picker_requires_selection: bool = true
var galaxy_presentation_visibility: Dictionary = {}
var system_panel_snapshot_cache: Dictionary = {}
var system_panel_snapshot_token: int = 0
var sim_speed_display_steps: Array[float] = [0.5, 1.0, 2.0, 4.0]
var sim_speed_actual_steps: Array[float] = [0.25, 0.5, 1.0, 2.0]
var sim_speed_index: int = 0
var sim_paused: bool = false
var runtime_visual_refresh_queued: bool = false
var generator: RefCounted = GALAXY_GENERATOR_SCRIPT.new()
var galaxy_state: RefCounted = GALAXY_STATE_SCRIPT.new()
var empire_factory: RefCounted = EMPIRE_FACTORY_SCRIPT.new()
