class_name ActivityTask extends RefCounted

enum State { GOTO, SETTLE, PERFORM, DONE, FAILED }

var resource: ActivityResource
var npc: NPCBase
var state: State = State.GOTO
var object: SmartObject
var slot: int = -1
var minutes_done: int = 0
var window_end: int = -1        # schedule minute this task stops making sense

func _init(res: ActivityResource, owner: NPCBase) -> void:
	resource = res
	npc = owner

func still_valid(now: int) -> bool:
	if window_end < 0:
		return true
	return now < window_end

func release() -> void:
	if object:
		object.release(npc.npc_id)
		object = null
		slot = -1

func pause() -> void:
	release()
	npc.stop()

func finish() -> void:
	release()
	state = State.DONE
