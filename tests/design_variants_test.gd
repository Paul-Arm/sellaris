extends Node

const PREVIEW := preload("res://scene/StarSystem/StarSystemPreview.tscn")

func _ready() -> void:
	assert(SettingsManager.normalize_design("bogus") == "pastel")
	assert(SettingsManager.normalize_design(13) == "pastel")
	SettingsManager.set_design_variant("pastel", false)
	var preview: StarSystemPreview = PREVIEW.instantiate()
	add_child(preview)
	var details := fixture()
	var original := details.duplicate(true)
	preview.set_system_details(details)
	var ids := _ids(preview)
	assert(ids.size() == 4)
	preview.camera_rig.configure_view(Vector3(4, 0, 7), 140.0, -42.0, 18.0)
	preview.call("_restore_selection", ids.back())
	var selected := preview.get_selected_selection_id()
	for i in range(3):
		SettingsManager.set_design_variant("clean", false)
		assert(_ids(preview) == ids, "Design switch must preserve selectable IDs")
		assert(preview.get_selected_selection_id() == selected, "Selection must survive")
		assert(preview.camera_rig.position.is_equal_approx(Vector3(4, 0, 7)), "Camera focus must survive")
		assert(is_equal_approx(preview.camera_rig.get("_camera_distance"), 140.0))
		var field := preview.get_node("Pivot/Bodies/GravityFieldMap") as GravityFieldMap
		assert(field.body_records.size() == 4)
		assert(field.cascade_views.size() == 4)
		assert(preview.find_children("", "SubViewport", true, false).size() == 4, "Switching must not accumulate buffers")
		for body in field.body_records:
			var marker := field.get_node("Marker_%s" % body["id"]) as Node3D
			assert(marker.position.is_equal_approx(body["position"]), "Markers must use real selectable coordinates")
		SettingsManager.set_design_variant("pastel", false)
		assert(preview.find_children("", "SubViewport", true, false).is_empty(), "Pastel releases the cascade buffers")
		assert(_ids(preview) == ids)
		assert(preview.get_selected_selection_id() == selected)
	assert(details == original, "Presentation must not mutate system records")
	SettingsManager.set_design_variant("clean", false)
	preview.clear_preview()
	assert(preview.get_node("Pivot/Bodies").get_child_count() == 0)
	preview.free()
	SettingsManager.set_design_variant("pastel", false)
	print("PASS: design switch, selection/camera preservation, coordinates, buffer cleanup and state isolation")
	get_tree().quit(0)

func _ids(preview: StarSystemPreview) -> Array[String]:
	var result: Array[String] = []
	for selectable: SystemSelectableComponent in preview.get("_selectables"):
		result.append(selectable.selection_id)
	result.sort()
	return result

static func fixture() -> Dictionary:
	return {
		"id": "design-test", "name": "Asterion", "seed": 7331,
		"has_full_intel": true,
		"stars": [
			{"id": "star-a", "name": "Asterion A", "kind": "star", "star_class": "G", "scale": 1.4, "orbit_radius": 12.0, "orbit_angle": 0.5, "is_primary": true},
			{"id": "star-b", "name": "Asterion B", "kind": "star", "star_class": "K", "scale": 0.75, "orbit_radius": 24.0, "orbit_angle": 3.3}
		],
		"orbitals": [
			{"id": "world-a", "name": "Eidolon", "type": "planet", "planet_type": "terran", "size": 1.6, "orbit_radius": 44.0, "orbit_angle": 2.4, "seed": 45},
			{"id": "world-b", "name": "Nacre", "type": "planet", "planet_type": "ice", "size": 1.3, "orbit_radius": 65.0, "orbit_angle": 5.7, "seed": 97}
		],
		"space_renderables": {}, "owner_name": "Cygnan Accord",
		"system_summary": {"star_count": 2, "star_class": "G / K", "planet_count": 2}
	}
