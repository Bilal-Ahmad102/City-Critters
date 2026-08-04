extends Node
# GameClock — canonical in-game time for the whole game. One in-game day lasts
# minutes_per_day real minutes. Anything that cares about time (NPC schedules,
# shop hours, HUD clock) listens to the signals here.
#
# If the current world contains a Sky3D node in the "sky3d" group, the clock
# drives it: Sky3D's own time progression is disabled and current_time is
# pushed every frame, so sun/moon/stars always match GameClock exactly.
#
# Day + hour persist to user://clock.cfg (skipped when headless, like the
# other saves, so tests never pollute a real save).

signal time_changed(hour: float)
signal hour_changed(hour: int)
signal minute_changed(minutes: int)   # minute-of-day 0..1439, for NPC schedules
signal day_changed(day: int)

const SAVE_PATH := "user://clock.cfg"

@export var minutes_per_day: float = 20.0

var hour: float = 8.0
var day: int = 1
var running: bool = true

var _prev_hour: int = -1
var _prev_minute: int = -1
var _sky: Node = null

# Minute-of-day, 0..1439. NPC schedules compare against this.
var total_minutes: int:
	get: return int(hour * 60.0)

func _ready() -> void:
	load_saved()
	_prev_hour = int(hour)
	_prev_minute = total_minutes

func _process(delta: float) -> void:
	if not running:
		return
	hour += delta * 24.0 / (minutes_per_day * 60.0)
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_changed.emit(day)
	time_changed.emit(hour)
	var h: int = int(hour)
	if h != _prev_hour:
		_prev_hour = h
		hour_changed.emit(h)
		save()
	_emit_minute()
	_drive_sky()

# Manual jump (debug / sleep / tests). Emits the same signals a natural tick would.
func set_time(new_hour: float) -> void:
	hour = fposmod(new_hour, 24.0)
	time_changed.emit(hour)
	var h: int = int(hour)
	if h != _prev_hour:
		_prev_hour = h
		hour_changed.emit(h)
	_emit_minute()
	_drive_sky()

func _emit_minute() -> void:
	var m: int = total_minutes
	if m != _prev_minute:
		_prev_minute = m
		minute_changed.emit(m)

func time_string() -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]

func is_night() -> bool:
	return hour < 6.0 or hour >= 20.0

func _drive_sky() -> void:
	var sky: Node = get_tree().get_first_node_in_group("sky3d")
	if sky != _sky:
		_sky = sky
		# The clock is the single time source; stop Sky3D advancing on its own.
		if _sky != null:
			_sky.set("game_time_enabled", false)
	if _sky != null:
		_sky.set("current_time", hour)

func save() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("clock", "day", day)
	cfg.set_value("clock", "hour", hour)
	cfg.save(SAVE_PATH)

func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var saved_day: Variant = cfg.get_value("clock", "day", day)
	if saved_day is int:
		day = saved_day
	var saved_hour: Variant = cfg.get_value("clock", "hour", hour)
	if saved_hour is float or saved_hour is int:
		hour = fposmod(float(saved_hour), 24.0)
