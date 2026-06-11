extends SceneTree

const SHIP_COMPONENT_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipComponentCatalog.gd")
const SHIP_DESIGN_CATALOG_SCRIPT: Script = preload("res://core/space/design/ShipDesignCatalog.gd")

const TEST_EMPIRE_ID := "empire_unlock_test"
const OTHER_EMPIRE_ID := "empire_unlock_other"


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Component unlock test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var component_catalog: ShipComponentCatalog = SHIP_COMPONENT_CATALOG_SCRIPT.new()
	component_catalog.load_definitions()

	var tier0_ids := component_catalog.get_component_ids_for_tier(0)
	var tier1_ids := component_catalog.get_component_ids_for_tier(1)
	_expect(tier0_ids.has("basic_laser"), "tier 0 should include basic_laser", failures)
	_expect(tier0_ids.has("basic_shield_emitter"), "tier 0 should include basic_shield_emitter", failures)
	_expect(tier0_ids.has("basic_drive"), "tier 0 should include basic_drive", failures)
	_expect(tier1_ids.has("shockwave_emitter"), "tier 1 should include shockwave_emitter", failures)

	var design_catalog: ShipDesignCatalog = SHIP_DESIGN_CATALOG_SCRIPT.new()
	design_catalog.setup(component_catalog)

	_expect(not design_catalog.is_component_unlocked(TEST_EMPIRE_ID, "basic_laser"), "nothing unlocked before bootstrap", failures)
	design_catalog.bootstrap_empire_unlocks(TEST_EMPIRE_ID)

	for component_id in tier0_ids:
		_expect(design_catalog.is_component_unlocked(TEST_EMPIRE_ID, component_id), "tier 0 component should be unlocked after bootstrap: %s" % component_id, failures)
	for component_id in tier1_ids:
		_expect(not design_catalog.is_component_unlocked(TEST_EMPIRE_ID, component_id), "tier 1 component should stay locked after bootstrap: %s" % component_id, failures)

	# Unlocks are per empire.
	_expect(not design_catalog.is_component_unlocked(OTHER_EMPIRE_ID, "basic_laser"), "unlocks should not leak between empires", failures)

	_expect(design_catalog.unlock_component(TEST_EMPIRE_ID, "shockwave_emitter"), "manual unlock should succeed", failures)
	_expect(design_catalog.is_component_unlocked(TEST_EMPIRE_ID, "shockwave_emitter"), "manual unlock should persist", failures)
	_expect(not design_catalog.unlock_component(TEST_EMPIRE_ID, "shockwave_emitter"), "double unlock should be rejected", failures)
	_expect(not design_catalog.unlock_component(TEST_EMPIRE_ID, "unknown_component"), "unknown component should be rejected", failures)

	var unlocked_ids := design_catalog.get_unlocked_component_ids(TEST_EMPIRE_ID)
	_expect(unlocked_ids.size() == tier0_ids.size() + 1, "unlocked id list should contain tier 0 plus the manual unlock", failures)
	var sorted_copy := unlocked_ids.duplicate()
	sorted_copy.sort()
	_expect(unlocked_ids == sorted_copy, "unlocked id list should be sorted for deterministic output", failures)

	# Bootstrap is idempotent and keeps manual unlocks.
	design_catalog.bootstrap_empire_unlocks(TEST_EMPIRE_ID)
	_expect(design_catalog.is_component_unlocked(TEST_EMPIRE_ID, "shockwave_emitter"), "re-bootstrap should keep manual unlocks", failures)
	_expect(design_catalog.get_unlocked_component_ids(TEST_EMPIRE_ID).size() == unlocked_ids.size(), "re-bootstrap should not duplicate unlocks", failures)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
