extends SceneTree

const DEPOSIT_COMPONENT_SCRIPT: Script = preload("res://core/economy/components/ResourceDepositComponent.gd")


func _initialize() -> void:
	var failures: Array[String] = []
	_run(failures)
	if failures.is_empty():
		print("Resource deposit component test passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _run(failures: Array[String]) -> void:
	var valid_resource_ids := PackedStringArray([
		"matter",
		"energy",
		"food",
		"alloys",
		"exotic_gases",
		"living_metal",
		"dark_matter",
	])
	var generated_body := {
		"id": "alpha_prime",
		"type": "planet",
		"resource_richness_points": 66,
		"habitability_points": 72,
		"is_colonizable": true,
	}

	var generated_a: Array[Dictionary] = DEPOSIT_COMPONENT_SCRIPT.resolve_deposit_amounts(7, "sys_alpha", generated_body, valid_resource_ids)
	var generated_b: Array[Dictionary] = DEPOSIT_COMPONENT_SCRIPT.resolve_deposit_amounts(7, "sys_alpha", generated_body, valid_resource_ids)
	_expect(not generated_a.is_empty(), "generated planet should have deposits", failures)
	_expect(JSON.stringify(generated_a) == JSON.stringify(generated_b), "generated deposits should be deterministic for the same key", failures)
	_expect(_amount_for(generated_a, "matter") > 0, "generated planet should include matter from the rule table", failures)

	var fixed_body := {
		"id": "fixed_body",
		"type": "planet",
		"resource_deposit_component": {
			"mode": "fixed",
			"deposits": [
				{"resource_id": "matter", "milliunits": 50000},
				{"resource_id": "unknown_resource", "milliunits": 9000},
			],
		},
	}
	var fixed_amounts: Array[Dictionary] = DEPOSIT_COMPONENT_SCRIPT.resolve_deposit_amounts(7, "sys_alpha", fixed_body, valid_resource_ids)
	_expect(fixed_amounts.size() == 1, "fixed override should ignore generated deposits and invalid resources", failures)
	_expect(_amount_for(fixed_amounts, "matter") == 50000, "fixed override should preserve exact milliunits", failures)
	_expect(_amount_for(fixed_amounts, "unknown_resource") == 0, "invalid fixed resource id should be filtered", failures)

	var additive_body := {
		"id": "additive_body",
		"type": "planet",
		"resource_richness_points": 0,
		"resource_deposit_component": {
			"mode": "additive",
			"deposits": [{"resource_id": "matter", "milliunits": 50000}],
		},
	}
	var additive_amounts: Array[Dictionary] = DEPOSIT_COMPONENT_SCRIPT.resolve_deposit_amounts(7, "sys_alpha", additive_body, valid_resource_ids)
	_expect(_amount_for(additive_amounts, "matter") > 50000, "additive override should add fixed deposits to generated deposits", failures)

	var disabled_body := {
		"id": "disabled_body",
		"type": "planet",
		"resource_deposit_component": {"mode": "none"},
	}
	var disabled_amounts: Array[Dictionary] = DEPOSIT_COMPONENT_SCRIPT.resolve_deposit_amounts(7, "sys_alpha", disabled_body, valid_resource_ids)
	_expect(disabled_amounts.is_empty(), "none mode should disable deposits", failures)


func _amount_for(amounts: Array[Dictionary], resource_id: String) -> int:
	for amount in amounts:
		if str(amount.get("resource_id", "")) == resource_id:
			return int(amount.get("milliunits", 0))
	return 0


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		return
	failures.append(message)
