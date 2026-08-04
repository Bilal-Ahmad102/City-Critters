# brain.gd
class_name Brain extends Node

@export var schedule: NPCSchedule
@export var personality: NPCPersonality

var npc: NPCBase
var current: ActivityTask
var _stack: Array[ActivityTask] = []

func _ready() -> void:
	npc = get_parent()
	GameClock.minute_changed.connect(_on_minute_changed)

func _on_minute_changed(now: int) -> void:
	if current and current.state in [ActivityTask.State.DONE, ActivityTask.State.FAILED]:
		pop_goal()
		return
	if _stack.is_empty():
		var wanted := schedule.entry_at(now)
		if wanted and (current == null or current.resource != wanted.activity):
			_replace_scheduled(wanted.activity)

func push_goal(task: ActivityTask) -> void:
	if current:
		if not current.resource.interruptible:
			return
		current.pause()
		_stack.push_back(current)
	current = task
	npc.blackboard.set_var(&"goal", task)

func pop_goal() -> void:
	var now := GameClock.total_minutes
	if current:
		current.release()
	while not _stack.is_empty():
		var t: ActivityTask = _stack.pop_back()
		if t.still_valid(now):
			current = t
			npc.blackboard.set_var(&"goal", t)
			return
	_replace_scheduled(schedule.entry_at(now).activity)

func _replace_scheduled(res: ActivityResource) -> void:
	if current:
		current.release()
	current = res.create_task(npc)
	npc.blackboard.set_var(&"goal", current)
