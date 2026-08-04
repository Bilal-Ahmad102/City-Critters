extends Node

signal minute_changed(total_minutes: int)
signal hour_changed(hour: int)

const MINUTES_PER_DAY := 1440

@export var minutes_per_second: float = 12.0   # 12 -> a full day in 2 real minutes
@export var paused: bool = false

var total_minutes: int = 6 * 60
var _accum: float = 0.0

var hour: int:
	get: return total_minutes / 60

func _process(delta: float) -> void:
	if paused:
		return
	_accum += delta * minutes_per_second
	while _accum >= 1.0:
		_accum -= 1.0
		var prev_hour := hour
		total_minutes = (total_minutes + 1) % MINUTES_PER_DAY
		minute_changed.emit(total_minutes)
		if hour != prev_hour:
			hour_changed.emit(hour)

func set_time(h: int, m: int = 0) -> void:
	total_minutes = (h * 60 + m) % MINUTES_PER_DAY
	minute_changed.emit(total_minutes)
