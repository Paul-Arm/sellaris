extends Node

signal day_tick(date: Dictionary)
signal month_tick(year: int, month: int)
signal year_tick(year: int)

@export var real_seconds_per_sim_day := 0.25
var sim_speed: float = 1.0
var accumulator: float = 0.0

# Midnight of the current in-game day.
var current_day_unix: int = 0

# Dictionary<int, Array[Callable]>
var scheduled_events: Dictionary = {}

func _ready() -> void:
	current_day_unix = Time.get_unix_time_from_datetime_dict({
		"year": 2025,
		"month": 1,
		"day": 1,
		"hour": 0,
		"minute": 0,
		"second": 0,
	})

func _physics_process(delta: float) -> void:
	if sim_speed <= 0.0:
		return

	accumulator += delta * sim_speed

	while accumulator >= real_seconds_per_sim_day:
		accumulator -= real_seconds_per_sim_day
		_advance_one_day()

func pause_sim() -> void:
	sim_speed = 0.0

func set_sim_speed(value: float) -> void:
	sim_speed = max(value, 0.0)

func get_current_date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(current_day_unix)

func get_current_date_string() -> String:
	return Time.get_datetime_string_from_unix_time(current_day_unix, true)

func _advance_one_day() -> void:
	var previous := Time.get_datetime_dict_from_unix_time(current_day_unix)
	current_day_unix += 86400
	var now := Time.get_datetime_dict_from_unix_time(current_day_unix)

	# Daily
	day_tick.emit(now)
	get_tree().call_group("sim_daily", "_on_sim_day", now)

	# Monthly
	if now.month != previous.month or now.year != previous.year:
		month_tick.emit(now.year, now.month)
		get_tree().call_group("sim_monthly", "_on_sim_month", now.year, now.month)

	# Yearly
	if now.year != previous.year:
		year_tick.emit(now.year)
		get_tree().call_group("sim_yearly", "_on_sim_year", now.year)

	_run_events_for_today()

func _run_events_for_today() -> void:
	if not scheduled_events.has(current_day_unix):
		return

	var events: Array = scheduled_events[current_day_unix]
	scheduled_events.erase(current_day_unix)

	for cb in events:
		if cb is Callable and cb.is_valid():
			cb.call()

func _schedule_unix_day(unix_day: int, callback: Callable) -> void:
	if not scheduled_events.has(unix_day):
		scheduled_events[unix_day] = []
	scheduled_events[unix_day].append(callback)

func schedule_after_days(days: int, callback: Callable) -> void:
	_schedule_unix_day(current_day_unix + days * 86400, callback)

func schedule_after_years(years: int, callback: Callable) -> void:
	var d := Time.get_datetime_dict_from_unix_time(current_day_unix)
	d.year += years
	_schedule_unix_day(Time.get_unix_time_from_datetime_dict(d), callback)

func schedule_on_date(day: int, month: int, year: int, callback: Callable) -> void:
	var unix_day := Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": month,
		"day": day,
		"hour": 0,
		"minute": 0,
		"second": 0,
	})
	_schedule_unix_day(unix_day, callback)

func schedule_on_iso_date(iso_date: String, callback: Callable) -> void:
	var unix_day := Time.get_unix_time_from_datetime_string("%sT00:00:00" % iso_date)
	_schedule_unix_day(unix_day, callback)
