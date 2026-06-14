extends LimboState

# ─── Node References ───────────────────────────────────────────────────────────
@onready var debug: Label = %debug

# ─── Constants ─────────────────────────────────────────────────────────────────
const ANIM_NAME: StringName = &"idle_jump"

const FRAME_RISE_START:      int = 2
const FRAME_RISE_LOOP_START: int = 4
const FRAME_FALL_START:      int = 5
const FRAME_FALL_LOOP_END:   int = 7
const FRAME_FALL_LOOP_MAX:   int = 10
const FRAME_LAND_START:      int = 11
const FRAME_LAND_END:        int = 15

# ─── State ─────────────────────────────────────────────────────────────────────
var _player: CharacterBody2D
var is_on_fall: bool = false
var is_on_rise: bool = false
var is_on_land: bool = false
# ─── Signal Callables ──────────────────────────────────────────────────────────
# Stored as variables so they can be connected/disconnected by name from anywhere.
var _sig_transition:  Callable  # rise windup  → fires jump velocity
var _sig_loop:        Callable  # rise/fall loop  → wraps frame back to start
var _sig_interval:    Callable  # fall one-shot  → hands off to fall loop
var _sig_land:        Callable  # land sequence  → dispatches idle


# ─── LimboState Callbacks ───────────────────────────────────────────────────────

func _setup() -> void:
	_player = agent

func _enter() -> void:
	PlayerData.coyote_timer      = 0.0
	PlayerData.jump_buffer_timer = 0.0
	is_on_fall = false
	is_on_rise = false
	play_anim_then_loop(FRAME_RISE_START, FRAME_RISE_LOOP_START)

func _exit() -> void:
	get_root().previous_state = self
	is_on_fall = false
	is_on_rise = false
	is_on_land = false
	disconnect_all_signals()

func _update(delta: float) -> void:
	_player.apply_gravity(delta)
	get_root().check_for_edge_grab()
	var falling := _player.velocity.y >= 0

	if falling and not is_on_fall and is_on_rise:
		is_on_fall = true
		play_anim_interval(FRAME_FALL_START, FRAME_FALL_LOOP_END)

	if is_on_fall and _player.is_on_floor() and not is_on_land:
		is_on_land = true
		play_rest_animation(FRAME_LAND_START)# ─── Animation Helpers ──────────────────────────────────────────────────────────

func play_anim_then_loop(transition_frame: int, end_frame: int) -> void:
	if _player.sprite.animation == ANIM_NAME:
		return
	_player.sprite.play(ANIM_NAME)
	_sig_transition = _on_transition_frame_changed.bind(transition_frame, end_frame)
	_connect_once(_player.sprite.frame_changed, _sig_transition)

func _on_transition_frame_changed(transition_frame: int, end_frame: int) -> void:
	if _player.sprite.frame < transition_frame:
		return
	_player.velocity.y = PlayerData.JUMP_VELOCITY
	is_on_rise = true
	disconnect_signal(_player.sprite.frame_changed, _sig_transition)
	play_anim_looped(transition_frame, end_frame)

func play_anim_looped(start_frame: int, end_frame: int) -> void:
	_player.sprite.stop()             # stop first
	_player.sprite.frame = start_frame
	_player.sprite.play(ANIM_NAME)    # play AFTER frame is set
	_sig_loop = _on_frame_changed.bind(start_frame, end_frame)
	_connect_once(_player.sprite.frame_changed, _sig_loop)

func _on_frame_changed(start_frame: int, end_frame: int) -> void:
	if _player.sprite.frame > end_frame:
		_player.sprite.frame = start_frame



func play_anim_interval(start_frame: int, end_frame: int) -> void:
	disconnect_signal(_player.sprite.frame_changed, _sig_loop)
	_player.sprite.stop()
	_player.sprite.frame = start_frame
	_player.sprite.play(ANIM_NAME)
	_sig_interval = _on_frame_changed_for_interval.bind(end_frame)
	_connect_once(agent.sprite.frame_changed, _sig_interval)

func _on_frame_changed_for_interval(end_frame: int) -> void:
	if _player.sprite.frame != end_frame:
		return
	disconnect_signal(_player.sprite.frame_changed, _sig_interval)
	play_anim_looped(end_frame, FRAME_FALL_LOOP_MAX)


func play_rest_animation(start_frame: int) -> void:
	disconnect_signal(_player.sprite.frame_changed, _sig_loop)
	_player.sprite.stop()
	_player.sprite.frame = start_frame
	_player.sprite.play(ANIM_NAME)
	_sig_land = _on_frame_changed_for_end
	_connect_once(agent.sprite.frame_changed, _sig_land)

func _on_frame_changed_for_end() -> void:
	if _player.sprite.frame != FRAME_LAND_END:
		return
	disconnect_signal(_player.sprite.frame_changed, _sig_land)
	get_root().dispatch(&"idle")


# ─── Signal Utilities ───────────────────────────────────────────────────────────

func _connect_once(sig: Signal, callable: Callable) -> void:
	if callable.is_valid() and not sig.is_connected(callable):
		sig.connect(callable)

func disconnect_signal(sig: Signal, callable: Callable) -> void:
	if callable.is_valid() and sig.is_connected(callable):
		sig.disconnect(callable)

func disconnect_all_signals() -> void:
	disconnect_signal(_player.sprite.frame_changed, _sig_transition)
	disconnect_signal(_player.sprite.frame_changed, _sig_loop)
	disconnect_signal(_player.sprite.frame_changed, _sig_interval)
	disconnect_signal(_player.sprite.frame_changed, _sig_land)
