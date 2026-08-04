# schedule_entry.gd
class_name ScheduleEntry extends Resource

@export_range(0, 23) var start_hour: int = 8
@export_range(0, 59) var start_minute: int = 0
@export var activity: ActivityResource

var start_minutes: int:
	get: return start_hour * 60 + start_minute
