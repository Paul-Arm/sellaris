extends RefCounted
class_name SystemSelectableComponent

const PICK_MODE_POINT: String = "point"
const PICK_MODE_ORBIT_RING: String = "orbit_ring"
const INVALID_PICK_SCORE: float = INF
const RING_SAMPLE_COUNT: int = 24

var selection_id: String = ""
var selection_kind: String = ""
var title: String = ""
var subtitle: String = ""
var body_text: String = ""
var pick_mode: String = PICK_MODE_POINT
var pick_priority: int = 0
var space_transform: Transform3D = Transform3D.IDENTITY
var anchor_local_position: Vector3 = Vector3.ZERO
var screen_pick_radius: float = 18.0
var highlight_radius: float = 2.0
var highlight_color: Color = Color(0.92, 0.96, 1.0, 0.95)
var ring_center_local: Vector3 = Vector3.ZERO
var ring_radius: float = 0.0
var ring_pick_tolerance: float = 14.0


func get_anchor_world_position() -> Vector3:
	return space_transform * anchor_local_position


func build_popup_state(camera: Camera3D, viewport_rect: Rect2) -> Dictionary:
	if camera == null:
		return {}

	var anchor_world_position: Vector3 = get_anchor_world_position()
	if camera.is_position_behind(anchor_world_position):
		return {}

	var screen_position: Vector2 = camera.unproject_position(anchor_world_position)
	if not viewport_rect.grow(96.0).has_point(screen_position):
		return {}

	return {
		"selection_id": selection_id,
		"selection_kind": selection_kind,
		"title": title,
		"subtitle": subtitle,
		"body_text": body_text,
		"screen_position": screen_position,
	}


func get_pick_score(camera: Camera3D, viewport_rect: Rect2, screen_position: Vector2) -> float:
	if camera == null:
		return INVALID_PICK_SCORE

	match pick_mode:
		PICK_MODE_ORBIT_RING:
			return _get_orbit_ring_pick_score(camera, viewport_rect, screen_position)
		_:
			return _get_point_pick_score(camera, viewport_rect, screen_position)


func _get_point_pick_score(camera: Camera3D, viewport_rect: Rect2, screen_position: Vector2) -> float:
	var anchor_world_position: Vector3 = get_anchor_world_position()
	if camera.is_position_behind(anchor_world_position):
		return INVALID_PICK_SCORE

	var projected_anchor: Vector2 = camera.unproject_position(anchor_world_position)
	if not viewport_rect.grow(screen_pick_radius).has_point(projected_anchor):
		return INVALID_PICK_SCORE

	var pick_distance_sq: float = projected_anchor.distance_squared_to(screen_position)
	var max_distance_sq: float = screen_pick_radius * screen_pick_radius
	if pick_distance_sq > max_distance_sq:
		return INVALID_PICK_SCORE
	return pick_distance_sq


func _get_orbit_ring_pick_score(camera: Camera3D, viewport_rect: Rect2, screen_position: Vector2) -> float:
	if ring_radius <= 0.0:
		return INVALID_PICK_SCORE

	var projected_points: Array[Vector2] = []
	var expanded_rect: Rect2 = viewport_rect.grow(ring_pick_tolerance * 2.0)

	for sample_index in range(RING_SAMPLE_COUNT):
		var angle: float = float(sample_index) * TAU / float(RING_SAMPLE_COUNT)
		var local_ring_point := ring_center_local + Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)
		var world_ring_point: Vector3 = space_transform * local_ring_point
		if camera.is_position_behind(world_ring_point):
			continue

		var projected_point: Vector2 = camera.unproject_position(world_ring_point)
		if not expanded_rect.has_point(projected_point):
			continue
		projected_points.append(projected_point)

	if projected_points.size() < 3:
		return INVALID_PICK_SCORE

	var best_distance_sq: float = INVALID_PICK_SCORE
	for point_index in range(projected_points.size()):
		var segment_start: Vector2 = projected_points[point_index]
		var segment_end: Vector2 = projected_points[(point_index + 1) % projected_points.size()]
		var segment_distance_sq: float = _distance_sq_to_segment(screen_position, segment_start, segment_end)
		if segment_distance_sq < best_distance_sq:
			best_distance_sq = segment_distance_sq

	var tolerance_sq: float = ring_pick_tolerance * ring_pick_tolerance
	if best_distance_sq > tolerance_sq:
		return INVALID_PICK_SCORE
	return best_distance_sq


static func _distance_sq_to_segment(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment_delta: Vector2 = segment_end - segment_start
	var segment_length_sq: float = segment_delta.length_squared()
	if segment_length_sq <= 0.0001:
		return point.distance_squared_to(segment_start)

	var projection_ratio: float = clampf((point - segment_start).dot(segment_delta) / segment_length_sq, 0.0, 1.0)
	var closest_point: Vector2 = segment_start + segment_delta * projection_ratio
	return point.distance_squared_to(closest_point)
