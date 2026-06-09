extends "res://scripts/hobbies/hobby_base.gd"
# FishingHobby — Webfishing-style cast and reel minigame logic.

signal cast_started()
signal bite_detected()
signal fish_caught(fish_id: String)
signal fish_missed()

@export var bite_window: float = 1.5   # seconds player has to react
@export var min_wait: float = 2.0
@export var max_wait: float = 6.0

var _waiting_for_bite: bool = false
var _bite_active: bool = false
var _bite_timer: float = 0.0
var _wait_timer: float = 0.0

func _on_start() -> void:
	_cast()

func _cast() -> void:
	_waiting_for_bite = true
	_wait_timer = randf_range(min_wait, max_wait)
	cast_started.emit()

func _process(delta: float) -> void:
	if _waiting_for_bite:
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_trigger_bite()
	elif _bite_active:
		_bite_timer -= delta
		if _bite_timer <= 0.0:
			_bite_active = false
			fish_missed.emit()

func _trigger_bite() -> void:
	_waiting_for_bite = false
	_bite_active = true
	_bite_timer = bite_window
	bite_detected.emit()

func reel() -> void:
	if _bite_active:
		_bite_active = false
		var fish_id := "fish_common"  # TODO: pick from weighted loot table
		fish_caught.emit(fish_id)
		finish({"fish": fish_id})
