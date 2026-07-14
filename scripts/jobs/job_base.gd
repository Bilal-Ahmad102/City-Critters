extends Node
# JobBase — parent for all job minigames. Handles the shift lifecycle (timer,
# payout, summary) so subclasses only implement the actual minigame in the
# _on_job_* hooks. Extend this for each job type (FoodService, Retail, ...).

signal job_started()
signal job_completed(currency_earned: int)  # emitted once when a shift ends well
signal job_failed()
signal shift_ended(summary: Dictionary)      # totals for the payout screen

@export var base_pay: int = 50
@export var shift_length: float = 60.0
# Display name used to bucket lifetime stats in JobStats. Subclasses assign
# their own in _init (an @export here can't be re-exported by a subclass).
var job_type: String = "Job"

var _elapsed: float = 0.0
var _active: bool = false
# Payout accumulates here across the shift so end_job pays once and the summary
# can report the same figure.
var _earned: int = 0

func start_job() -> void:
	_elapsed = 0.0
	_earned = 0
	_active = true
	_on_job_started()
	job_started.emit()

func end_job(success: bool = true) -> void:
	if not _active:
		return
	_active = false
	_on_job_ended()
	if _earned > 0:
		CurrencySystem.earn(_earned)
	if success:
		job_completed.emit(_earned)
	else:
		job_failed.emit()
	var summary := _build_summary()
	JobStats.record_shift(job_type, summary)
	shift_ended.emit(summary)

func is_active() -> bool:
	return _active

func time_left() -> float:
	return maxf(0.0, shift_length - _elapsed)

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_on_job_tick(delta)
	if _elapsed >= shift_length:
		end_job(true)

# Subclasses call this to add to the shift payout.
func _award(amount: int) -> void:
	_earned += amount

# --- Override in subclass ---
func _on_job_started() -> void:
	pass

func _on_job_tick(_delta: float) -> void:
	pass

func _on_job_ended() -> void:
	pass

func _build_summary() -> Dictionary:
	return {"earned": _earned}
