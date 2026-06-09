extends Node
# JobBase — base class for all job minigames.
# Extend this for each job type (FoodService, Retail, etc.)

signal job_completed(currency_earned: int)
signal job_failed()

@export var base_pay: int = 50
@export var time_limit: float = 60.0

var _elapsed: float = 0.0
var _active: bool = false

func start_job() -> void:
	_elapsed = 0.0
	_active = true
	_on_job_started()

func end_job(success: bool) -> void:
	_active = false
	if success:
		CurrencySystem.earn(base_pay)
		job_completed.emit(base_pay)
	else:
		job_failed.emit()

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed >= time_limit:
		end_job(false)

# Override in subclass
func _on_job_started() -> void:
	pass
