extends RefCounted
class_name SystemCombatEffectsRenderer

## Transient combat VFX for the system view (COMBAT_DESIGN.md Phase C).
## Purely cosmetic playback of SpaceManager.combat_events — spawns short-lived
## meshes under the preview's runtime effects root and never touches sim state.

const BEAM_THICKNESS := 0.16
const BEAM_HEIGHT_OFFSET := 0.6
const COLOR_BEAM_MISS := Color(0.55, 0.62, 0.74, 0.5)
const COLOR_BEAM_SHIELD_HIT := Color(0.42, 0.86, 1.0, 0.9)
const COLOR_BEAM_HULL_HIT := Color(1.0, 0.52, 0.3, 0.95)
const COLOR_EXPLOSION := Color(1.0, 0.62, 0.28, 0.95)
const COLOR_SHOCKWAVE := Color(0.78, 0.55, 1.0, 0.85)

var _host: Node3D = null


func bind(host: Node3D) -> void:
	_host = host


func unbind() -> void:
	_host = null


func play_events(events: Array, system_id: String) -> void:
	if _host == null or not _host.is_inside_tree() or system_id.is_empty():
		return
	var effects_root: Node3D = _host.get_runtime_effects_root()
	if effects_root == null:
		return
	var duration := _resolve_effect_duration()

	for event_variant in events:
		if event_variant is not Dictionary:
			continue
		var event: Dictionary = event_variant
		if str(event.get("system_id", "")) != system_id:
			continue
		match str(event.get("type", "")):
			"shot":
				_spawn_beam(effects_root, event, duration)
			"kill":
				_spawn_explosion(effects_root, event, duration)
			"ability":
				_spawn_shockwave_ring(effects_root, event, duration)


func _resolve_effect_duration() -> float:
	var seconds_per_day := 0.25
	var sim_speed := 1.0
	if SimClock != null:
		seconds_per_day = maxf(float(SimClock.get("real_seconds_per_sim_day")), 0.05)
		sim_speed = maxf(float(SimClock.get("sim_speed")), 0.25)
	return clampf(seconds_per_day / sim_speed, 0.12, 0.6)


func _spawn_beam(effects_root: Node3D, event: Dictionary, duration: float) -> void:
	var from_position := SpaceUnitRuntime._variant_to_vector3(event.get("attacker_position", Vector3.ZERO))
	var to_position := SpaceUnitRuntime._variant_to_vector3(event.get("target_position", Vector3.ZERO))
	from_position.y += BEAM_HEIGHT_OFFSET
	to_position.y += BEAM_HEIGHT_OFFSET
	var beam_length := from_position.distance_to(to_position)
	if beam_length <= 0.05:
		return

	var color := COLOR_BEAM_MISS
	if bool(event.get("hit", false)):
		color = COLOR_BEAM_HULL_HIT if int(event.get("hull_damage", 0)) > 0 else COLOR_BEAM_SHIELD_HIT

	var mesh := BoxMesh.new()
	mesh.size = Vector3(BEAM_THICKNESS, BEAM_THICKNESS, beam_length)
	var beam := MeshInstance3D.new()
	beam.name = "CombatBeam"
	beam.mesh = mesh
	beam.material_override = _build_effect_material(color)
	effects_root.add_child(beam)
	beam.position = (from_position + to_position) * 0.5
	beam.look_at_from_position(beam.position, to_position, Vector3.UP)
	_fade_and_free(beam, duration)


func _spawn_explosion(effects_root: Node3D, event: Dictionary, duration: float) -> void:
	var position := SpaceUnitRuntime._variant_to_vector3(event.get("position", Vector3.ZERO))
	position.y += BEAM_HEIGHT_OFFSET
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var explosion := MeshInstance3D.new()
	explosion.name = "CombatExplosion"
	explosion.mesh = mesh
	explosion.material_override = _build_effect_material(COLOR_EXPLOSION)
	effects_root.add_child(explosion)
	explosion.position = position
	explosion.scale = Vector3.ONE * 0.4
	var tween := explosion.create_tween()
	tween.set_parallel(true)
	tween.tween_property(explosion, "scale", Vector3.ONE * 2.8, duration * 1.4)
	tween.tween_property(explosion, "transparency", 1.0, duration * 1.4)
	tween.chain().tween_callback(explosion.queue_free)


func _spawn_shockwave_ring(effects_root: Node3D, event: Dictionary, duration: float) -> void:
	var position := SpaceUnitRuntime._variant_to_vector3(event.get("position", Vector3.ZERO))
	position.y += BEAM_HEIGHT_OFFSET
	var radius := maxf(float(event.get("radius", 4.0)), 1.0)
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	var ring := MeshInstance3D.new()
	ring.name = "CombatShockwave"
	ring.mesh = mesh
	ring.material_override = _build_effect_material(COLOR_SHOCKWAVE)
	effects_root.add_child(ring)
	ring.position = position
	ring.scale = Vector3.ONE * 0.3
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3.ONE * radius, duration * 1.6)
	tween.tween_property(ring, "transparency", 1.0, duration * 1.6)
	tween.chain().tween_callback(ring.queue_free)


func _fade_and_free(node: MeshInstance3D, duration: float) -> void:
	var tween := node.create_tween()
	tween.tween_property(node, "transparency", 1.0, duration)
	tween.tween_callback(node.queue_free)


static func _build_effect_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = 1.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
