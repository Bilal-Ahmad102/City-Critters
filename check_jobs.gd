extends SceneTree
# Temporary CI-style smoke test for the new job modules. Run with:
#   godot --headless -s check_jobs.gd
# Runs on the first process frame so autoloads (CurrencySystem) exist.

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var failures := _run()
	quit(failures)
	return true

func _run() -> int:
	var failures := 0

	# 1. Every new scene (and the two worlds) must load and instantiate.
	for path in [
		"res://scenes/jobs/retail_store.tscn",
		"res://scenes/jobs/stock_shelf.tscn",
		"res://scenes/jobs/delivery_depot.tscn",
		"res://scenes/jobs/delivery_point.tscn",
		"res://scenes/jobs/corporate_desk.tscn",
		"res://scenes/jobs/corporate_office.tscn",
		"res://scenes/ui/minimap.tscn",
		"res://scenes/city/town.tscn",
		"res://scenes/city/st_guy_blockout.tscn",
	]:
		var ps: PackedScene = load(path)
		if ps == null:
			printerr("LOAD FAIL: ", path)
			failures += 1
			continue
		var inst := ps.instantiate()
		if inst == null:
			printerr("INSTANCE FAIL: ", path)
			failures += 1
			continue
		print("ok: ", path)
		inst.free()

	# 2. Logic smoke tests (job nodes are plain Nodes; no tree needed).
	var retail: Node = (load("res://scripts/jobs/retail_job.gd") as GDScript).new()
	retail.start_job()
	var req: Dictionary = retail.pending_requests()[0]
	assert(retail.restock_shelf(req["shelf"], req["item"]) > 0, "restock should pay")
	assert(retail.restock_shelf(0, "nonsense") == -1, "bad restock should miss")
	retail._customer_waiting = true
	assert(retail.checkout() > 0, "checkout should pay")
	assert(retail.checkout() == -1, "empty register should miss")
	retail.end_job()
	print("ok: retail_job logic  summary=", retail._build_summary())
	retail.free()

	var delivery: Node = (load("res://scripts/jobs/delivery_job.gd") as GDScript).new()
	delivery.set_destinations({"Bakery": 40.0, "Inn": 90.0})
	delivery.start_job()
	var parcel: Dictionary = delivery.take_parcel()
	assert(not parcel.is_empty(), "should hand out a parcel")
	assert(delivery.take_parcel().is_empty(), "one parcel at a time")
	assert(delivery.deliver("WrongDoor") == -1, "wrong door should miss")
	var pay: int = delivery.deliver(parcel["dest"])
	assert(pay >= delivery.delivery_pay, "delivery should pay at least base")
	delivery.end_job()
	print("ok: delivery_job logic  payout=", pay, " summary=", delivery._build_summary())
	delivery.free()

	var corp: Node = (load("res://scripts/jobs/corporate_job.gd") as GDScript).new()
	corp.start_job()
	for i in 5:
		var task: Dictionary = corp.current_task()
		assert(not task.is_empty(), "a task should always be on screen")
		assert(corp.answer(task["is_correct"]) == true, "truthful answer is correct")
	corp.end_job()
	var s: Dictionary = corp._build_summary()
	assert(s["correct"] == 5 and s["earned"] == 5 * corp.task_pay, "5 correct audits")
	print("ok: corporate_job logic  summary=", s)
	corp.free()

	# 3. MapMarker objective group toggling (needs the tree, hence _process).
	var holder := Node3D.new()
	var marker: Node = (load("res://scripts/ui/map_marker.gd") as GDScript).new()
	holder.add_child(marker)
	root.add_child(holder)
	assert(marker.is_in_group("map_markers"), "marker should self-register")
	marker.set_objective(true)
	assert(marker.is_in_group("map_objective"), "objective flag on")
	marker.set_objective(false)
	assert(not marker.is_in_group("map_objective"), "objective flag off")
	print("ok: map_marker groups")
	holder.free()

	if failures == 0:
		print("ALL CHECKS PASSED")
	return failures
