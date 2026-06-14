extends LimboState

'''
     Brief landing squash state — plays the land animation once then exits.
Adds tactile weight to Marla's porcelain body hitting the stage floor.
If no "land" animation exists in your SpriteFrames, it falls back to "idle"
and exits after LAND_DURATION seconds. '''

const LAND_DURATION := 0.10  # seconds — short enough to feel snappy

var _player  : CharacterBody2D
var _timer   : float = 0.0

func _setup() -> void:
	_player = agent

func _enter() -> void:
	_timer    = LAND_DURATION
	_player.play_anim(&"land")

	# Kill vertical velocity cleanly
	_player.velocity.y = 0.0
	# Slight horizontal skid — porcelain weight
	_player.velocity.x *= 0.6


func _on_animation_finished() -> void:
	if _player.sprite.animation in ["land"]:
		_exit_land()

func _exit() -> void:
	get_root().previous_state = self

func _update(delta: float) -> void:
	# Bleed horizontal to zero during landing squash
	#_player.velocity.x = move_toward(_player.velocity.x, 0.0,
		#PlayerData.DECELERATION * delta)
	_player.apply_horizontal(delta, PlayerData.RUN_SPEED)
	_timer -= delta


func _exit_land() -> void:
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		if Input.is_action_pressed("run"):
			get_root().dispatch(&"run")
		else:
			get_root().dispatch(&"walk")
	else:
		get_root().dispatch(&"idle")
	get_root().previous_state = self
