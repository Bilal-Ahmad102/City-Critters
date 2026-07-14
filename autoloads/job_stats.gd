extends Node
# JobStats — lifetime job statistics, fed by JobBase.end_job on every shift.
# Tracks per job type: shifts worked, money earned, best single shift, and the
# lifetime sum of every counter a job reports in its summary (served, missed,
# delivered, ...). Performance is scored from those counters via GOOD_KEYS /
# BAD_KEYS, so new jobs get stats for free as long as their _build_summary
# uses int counters. Persisted to user:// (skipped when running headless so
# smoke tests don't pollute the save).

signal stats_changed(job_type: String)

const SAVE_PATH := "user://job_stats.cfg"

# Summary keys counted as successes / failures when scoring performance.
const GOOD_KEYS: Array[String] = ["served", "restocked", "customers", "delivered", "correct"]
const BAD_KEYS: Array[String] = ["missed", "walkouts", "wrong"]

# job_type -> {"shifts": int, "earned": int, "best_shift": int,
#              "totals": {summary counter -> lifetime sum}}
var _stats: Dictionary = {}

func _ready() -> void:
	_load()

func record_shift(job_type: String, summary: Dictionary) -> void:
	var entry: Dictionary = _stats.get(job_type,
		{"shifts": 0, "earned": 0, "best_shift": 0, "totals": {}})
	var earned := int(summary.get("earned", 0))
	entry["shifts"] += 1
	entry["earned"] += earned
	entry["best_shift"] = maxi(int(entry["best_shift"]), earned)
	var totals: Dictionary = entry["totals"]
	for key in summary:
		if key == "earned":
			continue
		if summary[key] is int:
			totals[key] = int(totals.get(key, 0)) + int(summary[key])
	_stats[job_type] = entry
	_save()
	stats_changed.emit(job_type)

func job_types() -> Array:
	var types := _stats.keys()
	types.sort()
	return types

func get_job(job_type: String) -> Dictionary:
	var entry: Dictionary = _stats.get(job_type, {})
	return entry.duplicate(true)

func total_shifts() -> int:
	var total := 0
	for job_type in _stats:
		total += int(_stats[job_type]["shifts"])
	return total

func total_earned() -> int:
	var total := 0
	for job_type in _stats:
		total += int(_stats[job_type]["earned"])
	return total

# Lifetime success ratio in [0, 1]: good outcomes / all outcomes. Jobs whose
# counters never appear in GOOD/BAD (or a fresh job) score a clean 1.0.
func performance(job_type: String) -> float:
	var entry: Dictionary = _stats.get(job_type, {})
	var totals: Dictionary = entry.get("totals", {})
	var good := 0
	var bad := 0
	for key in GOOD_KEYS:
		good += int(totals.get(key, 0))
	for key in BAD_KEYS:
		bad += int(totals.get(key, 0))
	if good + bad == 0:
		return 1.0
	return float(good) / float(good + bad)

func _save() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cfg := ConfigFile.new()
	for job_type in _stats:
		cfg.set_value("jobs", job_type, _stats[job_type])
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section("jobs"):
		return
	for job_type in cfg.get_section_keys("jobs"):
		var entry: Variant = cfg.get_value("jobs", job_type)
		if entry is Dictionary:
			_stats[job_type] = entry
