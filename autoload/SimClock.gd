extends Node

signal day_tick(date: Dictionary)
signal month_tick(year: int, month: int)
signal year_tick(year: int)

@export var real_seconds_per_sim_day := 0.25

var sim_speed: float = 1.0
var _sim_speed_milli: int = 1000
var _accumulator_scaled_usec: int = 0
var _real_usec_per_sim_day: int = 250000
var _current_year: int = 2025
var _current_month: int = 1
var _current_day: int = 1
var _current_day_serial: int = 0
var _current_month_serial: int = 0

# Dictionary<int, Array[Callable]>
var scheduled_events: Dictionary = {}


func _ready() -> void:
	_real_usec_per_sim_day = maxi(int(round(real_seconds_per_sim_day * 1000000.0)), 1)
	_reset_calendar(2025, 1, 1)
	set_sim_speed(sim_speed)


func _physics_process(delta: float) -> void:
	if _sim_speed_milli <= 0:
		return

	var delta_usec := maxi(int(round(delta * 1000000.0)), 0)
	_accumulator_scaled_usec += delta_usec * _sim_speed_milli
	var threshold_usec_scaled := _real_usec_per_sim_day * 1000

	while _accumulator_scaled_usec >= threshold_usec_scaled:
		_accumulator_scaled_usec -= threshold_usec_scaled
		_advance_one_day()


func pause_sim() -> void:
	set_sim_speed(0.0)


func set_sim_speed(value: float) -> void:
	sim_speed = maxf(value, 0.0)
	_sim_speed_milli = maxi(int(round(sim_speed * 1000.0)), 0)


func get_current_date() -> Dictionary:
	return {
		"year": _current_year,
		"month": _current_month,
		"day": _current_day,
		"hour": 0,
		"minute": 0,
		"second": 0,
	}


func get_current_date_string() -> String:
	return "%04d-%02d-%02d" % [_current_year, _current_month, _current_day]


func get_current_day_serial() -> int:
	return _current_day_serial


func get_current_month_serial() -> int:
	return _current_month_serial


func _advance_one_day() -> void:
	var previous_year := _current_year
	var previous_month := _current_month
	_increment_calendar_day()
	var now := get_current_date()

	day_tick.emit(now)
	get_tree().call_group("sim_daily", "_on_sim_day", now)

	if _current_month != previous_month or _current_year != previous_year:
		_current_month_serial += 1
		month_tick.emit(_current_year, _current_month)
		get_tree().call_group("sim_monthly", "_on_sim_month", _current_year, _current_month)

	if _current_year != previous_year:
		year_tick.emit(_current_year)
		get_tree().call_group("sim_yearly", "_on_sim_year", _current_year)

	_run_events_for_today()


func _run_events_for_today() -> void:
	if not scheduled_events.has(_current_day_serial):
		return

	var events: Array = scheduled_events[_current_day_serial]
	scheduled_events.erase(_current_day_serial)

	for cb in events:
		if cb is Callable and cb.is_valid():
			cb.call()


func _schedule_day_serial(day_serial: int, callback: Callable) -> void:
	if day_serial < _current_day_serial:
		return
	if not scheduled_events.has(day_serial):
		scheduled_events[day_serial] = []
	scheduled_events[day_serial].append(callback)


func schedule_after_days(days: int, callback: Callable) -> void:
	_schedule_day_serial(_current_day_serial + maxi(days, 1), callback)


func schedule_after_years(years: int, callback: Callable) -> void:
	var year_offset := maxi(years, 0)
	var target_year := _current_year + year_offset
	var target_day := mini(_current_day, _get_days_in_month(target_year, _current_month))
	_schedule_day_serial(_date_to_day_serial(target_year, _current_month, target_day), callback)


func schedule_on_date(day: int, month: int, year: int, callback: Callable) -> void:
	if year < 1 or month < 1 or month > 12:
		return
	var clamped_day := clampi(day, 1, _get_days_in_month(year, month))
	_schedule_day_serial(_date_to_day_serial(year, month, clamped_day), callback)


func schedule_on_iso_date(iso_date: String, callback: Callable) -> void:
	var parts := iso_date.split("-")
	if parts.size() != 3:
		return
	schedule_on_date(int(parts[2]), int(parts[1]), int(parts[0]), callback)


func _reset_calendar(year: int, month: int, day: int) -> void:
	_current_year = maxi(year, 1)
	_current_month = clampi(month, 1, 12)
	_current_day = clampi(day, 1, _get_days_in_month(_current_year, _current_month))
	_current_day_serial = 0
	_current_month_serial = 0
	scheduled_events.clear()


func _increment_calendar_day() -> void:
	_current_day += 1
	_current_day_serial += 1
	if _current_day <= _get_days_in_month(_current_year, _current_month):
		return

	_current_day = 1
	_current_month += 1
	if _current_month <= 12:
		return

	_current_month = 1
	_current_year += 1


func _date_to_day_serial(year: int, month: int, day: int) -> int:
	if year < 2025:
		return -1
	var serial := 0
	for scan_year in range(2025, year):
		serial += 366 if _is_leap_year(scan_year) else 365
	for scan_month in range(1, month):
		serial += _get_days_in_month(year, scan_month)
	serial += day - 1
	return serial


func _get_days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if _is_leap_year(year) else 28
		_:
			return 30


func _is_leap_year(year: int) -> bool:
	if year % 400 == 0:
		return true
	if year % 100 == 0:
		return false
	return year % 4 == 0
