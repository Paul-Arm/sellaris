extends SceneTree

const SCENES := [
	"res://assets/stations/modular_space_station/station_hub_core.tscn",
	"res://assets/stations/modular_space_station/corridor_segment.tscn",
	"res://assets/stations/modular_space_station/habitation_dome_module.tscn",
	"res://assets/stations/modular_space_station/industrial_tank_cluster.tscn",
	"res://assets/stations/modular_space_station/defense_turret_module.tscn",
	"res://assets/stations/modular_space_station/solar_array_module.tscn",
	"res://assets/stations/modular_space_station/comms_spire_module.tscn",
	"res://assets/stations/modular_space_station/station_assembly_showcase.tscn",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for scene_path in SCENES:
		var scene := load(scene_path) as PackedScene
		if scene == null:
			push_error("Could not load %s" % scene_path)
			quit(1)
			return
		var instance := scene.instantiate()
		if instance == null:
			push_error("Could not instantiate %s" % scene_path)
			quit(1)
			return
		print("OK %s -> %s children" % [scene_path, instance.get_child_count()])
		instance.free()
	print("All modular station assets loaded successfully.")
	quit()
