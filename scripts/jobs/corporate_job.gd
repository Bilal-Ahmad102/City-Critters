extends "res://scripts/jobs/job_base.gd"
# CorporateJob — satirical office-tasks minigame (GDD: stock market, budgets,
# spreadsheet puzzles). MVP mechanic: the expense-report audit. One spreadsheet
# row is on screen at a time ("Rubber ducks: 7 x $4 = $28"); the player
# approves correct rows and rejects wrong ones before the row times out.
# Stock-market and budget rounds can be added later as extra task generators.

func _init() -> void:
	job_type = "Corporate"

signal task_presented(task: Dictionary)
signal task_answered(task_id: int, correct: bool, payout: int)
signal task_missed(task_id: int)

# Line items that show up on expense reports. Purely flavor.
const LINE_ITEMS: Array[String] = [
	"Paperclips", "Rubber ducks", "Motivational posters", "Coffee",
	"Synergy consulting", "Ergonomic chairs", "Team-building lunch",
	"Printer ink", "Sticky notes", "Executive stress balls",
]

@export var task_pay: int = 8              # pay per correct audit
@export var task_time_limit: float = 10.0  # seconds before a row auto-skips
# Chance a generated row is actually correct. Slight bias keeps players
# reading instead of spam-rejecting.
@export var correct_chance: float = 0.5

var _task: Dictionary = {}                 # the row on screen right now
var _task_counter: int = 0
var _correct: int = 0
var _wrong: int = 0
var _missed: int = 0

func _on_job_started() -> void:
	_task = {}
	_task_counter = 0
	_correct = 0
	_wrong = 0
	_missed = 0
	_next_task()

func _on_job_tick(delta: float) -> void:
	if _task.is_empty():
		return
	_task["elapsed"] += delta
	if _task["elapsed"] >= _task["time_limit"]:
		_missed += 1
		task_missed.emit(_task["id"])
		_next_task()

func _next_task() -> void:
	var qty := randi_range(2, 12)
	var price := randi_range(2, 9)
	var total := qty * price
	var is_correct := randf() < correct_chance
	if not is_correct:
		# Off by a believable amount, never by zero.
		total += [-price, price, -qty, qty, 10, -10][randi() % 6]
	_task = {
		"id": _task_counter,
		"text": "%s: %d x $%d = $%d" % [
			LINE_ITEMS[randi() % LINE_ITEMS.size()], qty, price, total],
		"is_correct": is_correct,
		"time_limit": task_time_limit,
		"elapsed": 0.0,
	}
	_task_counter += 1
	task_presented.emit(_task)

# The player judges the current row: approve (true) or reject (false).
# Returns whether the judgement was right. Right answers pay; wrong ones just
# move on — cozy game, no punishment beyond the lost pay.
func answer(approve: bool) -> bool:
	if _task.is_empty():
		return false
	var right: bool = approve == _task["is_correct"]
	var payout := 0
	if right:
		payout = task_pay
		_correct += 1
		_award(payout)
	else:
		_wrong += 1
	task_answered.emit(_task["id"], right, payout)
	_next_task()
	return right

func current_task() -> Dictionary:
	return _task

func _build_summary() -> Dictionary:
	return {
		"correct": _correct,
		"wrong": _wrong,
		"missed": _missed,
		"earned": _earned,
	}
