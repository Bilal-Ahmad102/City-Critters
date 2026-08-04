class_name NPCSchedule extends Resource

@export var entries: Array[ScheduleEntry] = []

var _sorted: Array[ScheduleEntry] = []

func _ensure_sorted() -> void:
	if _sorted.size() == entries.size():
		return
	_sorted = entries.duplicate()
	_sorted.sort_custom(func(a, b): return a.start_minutes < b.start_minutes)

func entry_at(minutes: int) -> ScheduleEntry:
	_ensure_sorted()
	if _sorted.is_empty():
		return null
	# before the first entry of the day you are still doing last night's activity
	var found: ScheduleEntry = _sorted[-1]
	for e in _sorted:
		if e.start_minutes <= minutes:
			found = e
		else:
			break

	return found
