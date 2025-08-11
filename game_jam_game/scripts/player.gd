extends CharacterBody2D
class_name Player

# -- Set up ring buffer -- #
@onready var track1: RingBuffer = RingBuffer.create_by_seconds(15, Engine.get_physics_ticks_per_second())
var is_replaying: bool = false
var is_rewinding: bool = false
var track_replay_index: int = 0
var loop_triggered: bool = false

signal loop_started
signal health_changed(new_health: int)
 
@onready var animations: AnimatedSprite2D = $AnimatedSprite2D
@onready var sword: Node2D = $AnimatedSprite2D/Sword
@onready var camera: Camera2D = $Camera2D

@onready var state_machine: Node = $state_machine
var last_flip_h: bool = false
var original_sword_position: Vector2
var spawn_position: Vector2
var total_time = 0.0

# Ghost/timeline helpers
var _ticks_per_second: int = 0


# Input polling system - ensures inputs are only processed once per frame
var input_just_pressed: Dictionary = {}
var input_consumed: Dictionary = {}
var input_actions: Array[String] = [
	"jump", "attack", "crouch", "dash", "move_left", "move_right", "up"
]



# Coyote time variables
@export var coyote_time_duration: float = 0.25  # Time window for coyote jump
var coyote_timer: float = 0.0
var was_on_floor: bool = false
var coyote_available: bool = false  # Track if coyote time should be available
var jumped_off_ground: bool = false  # Track if player jumped off ground (vs walked off)

# Jump cooldown variables
@export var jump_cooldown_duration: float = 0.05  # Shorter cooldown for continuous short jumps
var jump_cooldown_timer: float = 0.0
var can_jump_again: bool = true

# Generalized input buffer system
@export var input_buffer_duration: float = 0.15  # Buffer duration for input responsiveness
@export var input_buffer_refresh_cooldown: float = 0.02  # Cooldown before buffer can be refreshed
var input_buffers: Dictionary = {}  # Stores buffered inputs with their timers
var input_buffer_hold_times: Dictionary = {}  # Stores how long inputs were held when buffered
var input_hold_start_times: Dictionary = {}  # Track when input buttons were first pressed
var last_buffer_times: Dictionary = {}  # Track when each buffer was last set



# Health system variables
@export var max_health: int = 3  # Player starts with 3 hearts
var current_health: int = 3

func get_health() -> int:
		return current_health

func set_health(value: int) -> void:
		current_health = clamp(value, 0, max_health)
		health_changed.emit(current_health)

# Ghost mode system - when player dies, becomes a ghost until timer ends
var is_ghost_mode: bool = false
var ghost_is_spirit: bool = false  # True when player is dead but still controllable (no damage)
var echo_ghost_dead: bool = false  # True when echo ghost playback represents a dead player at sampled time
@export var ghost_transparency: float = 0.7  # How transparent the ghost appears (0.7 = dimmer but visible)
@export var ghost_color_tint: Color = Color(0.6, 0.6, 1.0, 0.7)  # Slightly blue tint with reduced alpha
# Color for dead echo ghosts (more grey and translucent)
@export var dead_ghost_color_tint: Color = Color(0.3, 0.3, 0.3, 0.22)
# Color for live echo ghosts (less translucent, blue)
@export var live_ghost_color_tint: Color = Color(0.6, 0.6, 1.0, 0.55)

# Invincibility frames system
@export var invincibility_duration: float = 1.5  # Duration of invincibility after taking damage
@export var invincibility_flash_rate: float = 8.0  # How fast to flash during invincibility (flashes per second)
var invincibility_timer: float = 0.0
var is_invincible: bool = false
var flash_visible: bool = true  # Track visibility state for flashing effect




# Fast fall damage mechanic variables
@export var fast_fall_damage_multiplier: float = 1.5  # Damage multiplier when fast falling
@export var fast_fall_minimum_speed: float = 800.0  # Minimum fall speed to trigger bonus damage
@export var max_fast_fall_damage_multiplier: float = 4.0  # Maximum damage multiplier at terminal velocity

# Action cancellation system
@export var allow_movement_cancel: bool = true  # Allow movement to cancel actions
@export var allow_jump_cancel: bool = true     # Allow jump to cancel actions  
@export var allow_dash_cancel: bool = true     # Allow dash to cancel actions
@export var action_cancel_window: float = 0.3  # Time window after action start where cancellation is allowed
@export var dash_cancel_window: float = 0.1    # Shorter cancel window for dash (more commitment)
@export var use_animation_cancel_points: bool = false  # Use specific animation frames for cancellation
var current_action_start_time: float = 0.0     # When the current action started
var current_action_cancelable: bool = false    # Whether the current action can be canceled
var current_action_type: String = ""           # Type of current action for specific cancel rules
var animation_cancel_enabled: bool = false     # Whether animation-based cancellation is currently enabled



func _ready() -> void:
	# Initialize the state machine, passing a reference of the player to the states,
	# that way they can move and react accordingly
	# Ensure enemies and systems can find all player instances
	add_to_group("player")
	state_machine.init(self)
	# store the sword position and direction
	last_flip_h = animations.flip_h
	original_sword_position = sword.position
	# Initialize coyote time state
	was_on_floor = is_on_floor()
	coyote_timer = coyote_time_duration if was_on_floor else 0.0
	coyote_available = was_on_floor
	
	# Initialize jump cooldown state
	jump_cooldown_timer = 0.0
	can_jump_again = true
	
	# Input buffer system is initialized automatically via Dictionary declarations
	# No manual initialization needed for the generalized buffer system

	# Cache ticks/s for sampling convenience
	_ticks_per_second = int(max(1, Engine.get_physics_ticks_per_second()))
	
func set_total_time(time: float) -> void:
		total_time = time

func _pad_ring_buffer_to_full() -> void:
	var rb := track1
	if rb.length >= rb.buffer_size:
		return
	var last_tick = rb.get_latest()
	if last_tick == null:
		last_tick = {
			"input": {},
			"seconds": total_time,
			"health": current_health,
			"position": self.position,
			"velocity": self.velocity
		}
	while rb.length < rb.buffer_size:
		rb.push(last_tick)

func reset_to_spawn() -> void:
		global_position = spawn_position
		velocity = Vector2.ZERO
		track1.clear()
		track_replay_index = 0
		is_replaying = false

# Start a fresh 15s live take: clear tape and reset replay/ghost-related flags and input state
func begin_live_take() -> void:
	# Stop any rewind/replay state
	is_rewinding = false
	is_replaying = false
	# Ensure this puppet is live (manager controls ghosting, but keep consistent)
	is_ghost_mode = false
	# Reset loop latch so a newly cleared tape won't instantly auto-advance
	loop_triggered = false
	# Clear recorded ticks
	track1.clear()
	track_replay_index = 0
	# Flush any buffered inputs so the first live frame is clean
	input_just_pressed.clear()
	input_consumed.clear()
	input_buffers.clear()
	input_buffer_hold_times.clear()
	last_buffer_times.clear()
	for action in input_actions:
		input_hold_start_times[action] = 0.0
	# Ensure physics callbacks remain active for the live puppet
	set_physics_process(true)

func _unhandled_input(event: InputEvent) -> void:
	
	if is_replaying and event.is_action_pressed("reset_track"):
		is_replaying = false
		track1.clear()
		track_replay_index = 0
		
	# Track when input buttons are first pressed for hold time calculation
	for action in input_actions:
		if event.is_action_pressed(action):
			input_hold_start_times[action] = total_time
			# print(action.capitalize(), " hold started at: ", total_time)
		elif event.is_action_released(action):
			input_hold_start_times[action] = 0.0
			# print(action.capitalize(), " hold reset - button released")
	
	# Keep calling process_input for states that haven't been converted to polling yet
	state_machine.process_input(event)

func is_echo_ghost() -> bool:
	return is_ghost_mode and not ghost_is_spirit

func is_spirit_ghost() -> bool:
	return is_ghost_mode and ghost_is_spirit

# Is this ghost representing a dead state?
func is_dead_ghost() -> bool:
	return is_ghost_mode and (ghost_is_spirit or echo_ghost_dead)

# Is this ghost representing an alive state?
func is_alive_ghost() -> bool:
	return is_ghost_mode and not is_dead_ghost()

func _physics_process(delta: float) -> void:
	# Always tick invincibility frames (even if ghost; visuals respect ghost mode)
	update_invincibility(delta)
	# Echo ghosts are driven externally; don't run physics/state while echo-ghosting
	if is_echo_ghost() and not is_rewinding:
		return

	if is_rewinding:
		if track1.length == 0:
			return
		var tick = track1.get_at(track_replay_index)
		if tick:
			self.position = tick.position
			self.velocity = tick.velocity
			# Apply recorded inputs for visual correctness during rewind,
			# but use a copy to avoid accidental shared mutations
			if tick.input is Dictionary:
				self.input_just_pressed = tick.input.duplicate(true)
			else:
				self.input_just_pressed = {}
			# update the cassette player
			if has_node("../CassetteButtonlessUI"):
				var ui = get_node("../CassetteButtonlessUI")
				if ui.has_method("set_progress"):
					# Assume tick["seconds"] is the time at this tick, and UI expects 0..1
					var progress = float(track_replay_index) / float(track1.length - 1) if track1.length > 1 else 0.0
					ui.set_progress(progress)
		# Move backward, wrap around if needed
		track_replay_index -= 1
		if track_replay_index < 0:
			# Clamp at the earliest tick and stop rewinding to avoid looping
			track_replay_index = 0
			# At the very beginning, ensure no stale input is imposed
			input_just_pressed.clear()
			# Auto-stop rewind when we hit the beginning of the recording
			stop_rewind()
			# Inform PlayerManager to stop global time rewind mode
			var pm = get_tree().get_first_node_in_group("player_manager")
			if pm and pm.has_method("_stop_time_rewind"):
				pm._stop_time_rewind()
		return
	else:
		track1.push({
			"input" : (input_just_pressed.duplicate(true) if input_just_pressed else {}),
			"seconds" : total_time,
			"health" : current_health,  # Use actual current health
			"position": self.position,
			"velocity": self.velocity
				})
	
	# Only signal loop start when not ghosting; dying pads the buffer to full
	if track1.is_full() and not loop_triggered and not is_ghost_mode:
		loop_triggered = true
		emit_signal("loop_started")
	
		# If in echo ghost mode, limit what systems update (spirit ghosts behave like live players)
		if is_echo_ghost():
			# Still apply gravity and basic physics so echo ghost doesn't float
			if not is_on_floor():
				velocity.y += get_gravity().y * delta
				move_and_slide()
				return  # Skip most other game logic
	
	# Update jump cooldown timer
	if jump_cooldown_timer > 0.0:
		jump_cooldown_timer -= delta
		if jump_cooldown_timer <= 0.0:
			can_jump_again = true
			# print("Jump cooldown expired - can jump again")
		
	# Update jump buffer timer
	update_input_buffers(delta)
	
	# Update coyote time BEFORE state machine processing
	update_coyote_time(delta)
	
	state_machine.process_physics(delta)

func buffer_jump():
	buffer_input("jump")
func _process(delta: float) -> void:
	# Poll inputs: allow for live and spirit ghosts; skip for echo ghosts
	if not is_echo_ghost():
		poll_inputs()
	if is_replaying:
		return

	state_machine.process_frame(delta)
	

	if animations.flip_h != last_flip_h:
		update_sword_position()

		last_flip_h = animations.flip_h

# Input polling system - call this every frame to capture inputs
func poll_inputs() -> void:
	
	# Skip input polling for echo ghosts, but allow it for spirit ghosts
	if is_echo_ghost():
		input_just_pressed.clear()
		input_consumed.clear()
		return
	
	if is_replaying:
		return
	# Reset consumed flags for new frame
	input_consumed.clear()
	
	# Poll all input actions and store their just_pressed state
	for action in input_actions:
		var just_pressed = Input.is_action_just_pressed(action)
		input_just_pressed[action] = just_pressed
		
		# Auto-buffer inputs when they're pressed for improved responsiveness
		if just_pressed:
			buffer_input(action)

# Public method for states to check if an action was just pressed this frame
# Returns true only once per frame, even if called multiple times
func is_action_just_pressed_once(action: String) -> bool:
	if not input_just_pressed.has(action):
		return false
	
	if input_consumed.get(action, false):
		return false  # Already consumed this frame
	
	if input_just_pressed[action]:
		input_consumed[action] = true  # Mark as consumed
		return true
	
	return false

# Public method for states to check if an action is currently pressed
func is_action_pressed_polling(action: String) -> bool:
	return Input.is_action_pressed(action)

func update_sword_position() -> void:
	# Flip the sword's x position when the sprite flips
	if animations.flip_h:
		# Facing left - sword should be on the left side
		sword.scale.x = -1
		sword.position.x = -abs(sword.position.x)
	else:
		# Facing right - sword should be on the right side  
		sword.scale.x = 1
		sword.position.x = abs(sword.position.x)




func update_coyote_time(delta: float) -> void:
	var currently_on_floor = is_on_floor()
	
	if currently_on_floor:
		# Add motion blur effect for high-speed landings
		if not was_on_floor :
			var _impact_intensity = clamp(abs(velocity.y) / 1200.0, 0.2, 0.8)
		
		# Reset timer and availability when on ground
		coyote_timer = coyote_time_duration
		coyote_available = true
		
		# Only start jump cooldown if we landed after jumping off ground
		if not was_on_floor and jumped_off_ground:
			print("Landed on ground after jumping - starting jump cooldown")
			jump_cooldown_timer = jump_cooldown_duration
			can_jump_again = false
		elif not was_on_floor:
			print("Landed on ground after walking off - no jump cooldown")
		
		jumped_off_ground = false  # Reset jump flag when landing
	else:
		# Only start the message when we first leave the ground
		if was_on_floor:
			print("LEFT GROUND! Jumped: ", jumped_off_ground, " Coyote timer: ", coyote_timer, " Available: ", coyote_available)
			
			# If player jumped off ground, disable coyote time immediately
			if jumped_off_ground:
				coyote_available = false
				coyote_timer = 0.0
				print("Coyote time disabled - player jumped off ground")
		
		# Count down when in air, but only if coyote is available
		if coyote_available and coyote_timer > 0.0:
			coyote_timer = max(0.0, coyote_timer - delta)
			if coyote_timer <= 0.0:
				print("COYOTE TIME EXPIRED!")
				coyote_available = false
	
	was_on_floor = currently_on_floor

func can_coyote_jump() -> bool:
	var can_coyote = coyote_available and coyote_timer > 0.0

	if can_coyote and not is_on_floor():
		print("Coyote time jump activated! Timer: ", coyote_timer)
	
	return can_coyote


# Check if player can perform a normal ground jump
func can_ground_jump() -> bool:
	return is_on_floor() and can_jump_again

# Update all input buffers - call this every physics frame
func update_input_buffers(delta: float) -> void:
	var expired_buffers = []
	
	for action in input_buffers.keys():
		input_buffers[action] -= delta
		if input_buffers[action] <= 0.0:
			expired_buffers.append(action)
			print(action.capitalize(), " buffer expired")
	
	# Remove expired buffers
	for action in expired_buffers:
		input_buffers.erase(action)
		input_buffer_hold_times.erase(action)

# Buffer any input for later execution
func buffer_input(action: String):
	# Allow refreshing the buffer if enough time has passed or if no buffer exists
	var current_time = total_time
	var last_time = last_buffer_times.get(action, 0.0)
	
	if not input_buffers.has(action) or (current_time - last_time) >= input_buffer_refresh_cooldown:
		input_buffers[action] = input_buffer_duration
		last_buffer_times[action] = current_time
		
		# Calculate how long the input has been held when buffering
		var hold_start = input_hold_start_times.get(action, current_time)
		input_buffer_hold_times[action] = current_time - hold_start

func has_valid_dash_buffer() -> bool:
	return has_valid_input_buffer("dash")

func has_valid_jump_buffer() -> bool:
	return has_valid_input_buffer("jump")

# Check if there's a buffered input that should be executed
func has_valid_input_buffer(action: String) -> bool:
	return input_buffers.has(action) and input_buffers[action] > 0.0

# Get the hold time of a buffered input
func get_buffered_input_hold_time(action: String) -> float:
	return input_buffer_hold_times.get(action, 0.0)

# Get current hold time for any input (how long it's been held since press)
func get_current_input_hold_time(action: String) -> float:
	var hold_start = input_hold_start_times.get(action, 0.0)
	if hold_start > 0.0:
		return total_time - hold_start
	return 0.0

func get_current_jump_hold_time() -> float:
	return get_current_input_hold_time("jump")

func mark_jumped_off_ground():
	jumped_off_ground = true

func consume_jump_buffer():
	return consume_input_buffer("jump")

# Consume an input buffer (call this when a buffered input is executed)
func consume_input_buffer(action: String):
	var hold_time = input_buffer_hold_times.get(action, 0.0)
	
	input_buffers.erase(action)
	input_buffer_hold_times.erase(action)
	last_buffer_times.erase(action)
	
	# print(action.capitalize(), " buffer consumed! Was held for: ", hold_time, " seconds")
	return hold_time  	# Return the hold time for states to use

# Update invincibility system
func update_invincibility(delta: float) -> void:
	if is_invincible:
		invincibility_timer -= delta
		
		# Handle flashing effect during invincibility
		var flash_interval = 1.0 / invincibility_flash_rate
		var flash_time = fmod(invincibility_timer, flash_interval * 2.0)
		flash_visible = flash_time < flash_interval
		
		# Apply visibility based on flash state (only if not in ghost mode)
		if animations and not is_ghost_mode:
			animations.modulate.a = 0.4 if flash_visible else 0.8
		
		# End invincibility when timer expires
		if invincibility_timer <= 0.0:
			end_invincibility()

func start_invincibility() -> void:
	"""Start invincibility frames after taking damage"""
	is_invincible = true
	invincibility_timer = invincibility_duration
	flash_visible = true
	print("Invincibility started for ", invincibility_duration, " seconds")

func end_invincibility() -> void:
	"""End invincibility frames and restore normal appearance"""
	is_invincible = false
	invincibility_timer = 0.0
	flash_visible = true
	
	# Restore normal sprite appearance (but respect ghost mode)
	if animations:
		if is_ghost_mode:
			animations.modulate = ghost_color_tint  # Restore ghost appearance
		else:
			animations.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Restore normal appearance
	
	print("Invincibility ended")

func is_player_invincible() -> bool:
	"""Check if player is currently invincible"""
	return is_invincible

# Debug function to get invincibility status
func get_invincibility_status() -> Dictionary:
	"""Get detailed invincibility status for debugging"""
	return {
		"is_invincible": is_invincible,
		"time_remaining": invincibility_timer,
		"flash_visible": flash_visible,
		"total_duration": invincibility_duration
	}



# Debug function to print all current buffers
func print_buffer_status():
	if input_buffers.is_empty():
		print("No inputs currently buffered")
	else:
		print("Currently buffered inputs:")
		for action in input_buffers.keys():
			print("  ", action.capitalize(), ": ", input_buffers[action], "s remaining")



# Rewind Replay System
func start_rewind() -> void:
	"""
	Begin rewinding the player's recorded path. This will set the player into replay mode and
	move backward through the ring buffer each physics frame.
	Also triggers enemy rewind if present.
	"""
	if track1.length == 0:
		return
	is_replaying = true
	is_rewinding = true
	# Start from the most recent tick
	track_replay_index = (track1.length - 1) if track1.length > 0 else 0
	set_physics_process(true)

	# Trigger enemy rewind if enemy exists and has start_rewind
	var enemy = get_tree().get_first_node_in_group("enemy")
	if enemy and enemy.has_method("start_rewind"):
		enemy.start_rewind()

func stop_rewind(commit: bool = false) -> void:
	"""
	Stop rewinding and return to normal control.
	Also stops enemy rewind if present.
	"""
	is_replaying = false
	is_rewinding = false
	set_physics_process(true)

	# If requested, truncate the recording up to the current rewind point
	if commit:
		_commit_rewind_state()

	# Flush any potentially stale inputs/buffers captured during replay so
	# no unintended actions trigger on the first live frame after rewind
	input_just_pressed.clear()
	input_consumed.clear()
	input_buffers.clear()
	input_buffer_hold_times.clear()
	last_buffer_times.clear()
	for action in input_actions:
		input_hold_start_times[action] = 0.0

	# Stop enemy rewind if enemy exists and has stop_rewind
	var enemy = get_tree().get_first_node_in_group("enemy")
	if enemy and enemy.has_method("stop_rewind"):
		enemy.stop_rewind()

func _commit_rewind_state() -> void:
	"""Truncate the ring buffer to the current rewind index (inclusive)."""
	if track1.length == 0:
		return
	var arr: Array = track1.duplicate()  # earliest -> latest
	var keep_count: int = int(clamp(track_replay_index + 1, 0, track1.length))
	# Rebuild the buffer with only the kept entries
	track1.clear()
	for i in range(keep_count):
		track1.push(arr[i])









# ═══════════════════════════════════════════════════════════════════════════════
# ACTION CANCELLATION SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

# Start a new cancelable action
func start_cancelable_action(action_type: String = "default"):
	current_action_start_time = total_time
	current_action_cancelable = true
	current_action_type = action_type

# Mark current action as non-cancelable
func set_action_non_cancelable():
	current_action_cancelable = false

# Check if current action can be canceled
func can_cancel_current_action() -> bool:
	if not current_action_cancelable:
		return false
	
	# If using animation-based cancellation, check that too
	if use_animation_cancel_points and not animation_cancel_enabled:
		return false
	
	var time_since_action_start = total_time - current_action_start_time
	var cancel_window = action_cancel_window
	
	# Use shorter cancel window for dash
	if current_action_type == "dash":
		cancel_window = dash_cancel_window
	
	return time_since_action_start <= cancel_window

# Enable animation-based cancellation (called from animation events)
func enable_animation_cancel():
	animation_cancel_enabled = true

# Disable animation-based cancellation (called from animation events)  
func disable_animation_cancel():
	animation_cancel_enabled = false

# Check if player is trying to cancel with movement
func is_trying_to_cancel_with_movement() -> bool:
	if not allow_movement_cancel or not can_cancel_current_action():
		return false
	
	var input_axis = Input.get_axis("move_left", "move_right")
	return input_axis != 0.0

# Check if player is trying to cancel with jump
func is_trying_to_cancel_with_jump() -> bool:
	if not allow_jump_cancel or not can_cancel_current_action():
		return false
	
	return is_action_just_pressed_once("jump")

# Check if player is trying to cancel with dash
func is_trying_to_cancel_with_dash() -> bool:
	if not allow_dash_cancel or not can_cancel_current_action():
		return false
	
	return is_action_just_pressed_once("dash")

# Check for any cancellation input
func is_trying_to_cancel_action() -> bool:
	return is_trying_to_cancel_with_movement() or is_trying_to_cancel_with_jump() or is_trying_to_cancel_with_dash()

# Get the current action status for debugging
func get_action_status() -> Dictionary:
	return {
		"action_type": current_action_type,
		"cancelable": current_action_cancelable,
		"time_remaining": max(0.0, action_cancel_window - (total_time - current_action_start_time)),
		"animation_cancel_enabled": animation_cancel_enabled
	}

# End the current action (called when action completes or is canceled)
func end_current_action():
	current_action_cancelable = false
	animation_cancel_enabled = false
	current_action_type = ""

# ═══════════════════════════════════════════════════════════════════════════════

# Check if player can perform any type of jump (ground or coyote)
func can_jump() -> bool:
	return can_ground_jump() or can_coyote_jump()


func apply_knockback(knockback_force: Vector2):
	"""Apply knockback force to the player"""
	# Store the knockback for state machines to potentially use
	var knockback_magnitude = knockback_force.length()
	
	# Different knockback handling based on player state
	if is_on_floor():
		# Ground knockback - apply horizontal force, reduce vertical knockback
		velocity.x += knockback_force.x
		velocity.y += knockback_force.y * 0.5  # Reduce vertical knockback when grounded but allow some
	else:
		# Air knockback - apply full force for more dynamic aerial combat
		velocity += knockback_force
	
	# Clamp velocities to prevent excessive knockback but allow reasonable combat dynamics
	var max_knockback_velocity = 1200.0  # Slightly reduced for better control
	velocity.x = clamp(velocity.x, -max_knockback_velocity, max_knockback_velocity)
	velocity.y = clamp(velocity.y, -max_knockback_velocity, max_knockback_velocity)
	
	# Add visual feedback for knockback
	if knockback_magnitude > 80:  # Lowered threshold for more responsive feedback
		# Flash sprite and shake camera for significant knockback
		flash_sprite()
		var damage_equivalent = int(knockback_magnitude / 15)  # More sensitive camera shake
		shake_camera_for_damage(damage_equivalent)
		
		# Add motion blur burst effect
		var _blur_intensity = clamp(knockback_magnitude / 400.0, 0.2, 0.8)

	
	print("Player received knockback: ", knockback_force, " | New velocity: ", velocity, " | On floor: ", is_on_floor())

	# Apply a short lockout to switching after knockback
	if not is_ghost_mode:
		var mag = knockback_force.length()
		var lockout = clamp(mag / 2000.0, 0.1, 0.35)
		# store via input buffer dicts indirectly by timer
		# reuse invincibility timers is not ideal; keep separate
		# We'll piggyback on an optional field by setting a small timer via call_deferred
		set_meta("switch_lockout_until", total_time + lockout)

# Fast fall damage calculation
func get_fast_fall_damage_multiplier() -> float:
	# Check if player is fast falling (holding crouch) and moving downward fast enough
	var is_fast_falling = is_action_pressed_polling("crouch")
	
	if not is_fast_falling or velocity.y <= fast_fall_minimum_speed:
		return 1.0  # No bonus damage
	
	# Calculate multiplier based on fall speed
	# Linear interpolation from minimum speed to terminal velocity
	var speed_ratio = (velocity.y - fast_fall_minimum_speed) / (3000.0 - fast_fall_minimum_speed)  # 3000 is fast fall terminal velocity
	speed_ratio = clamp(speed_ratio, 0.0, 1.0)
	
	# Calculate the final multiplier
	var damage_multiplier = lerp(fast_fall_damage_multiplier, max_fast_fall_damage_multiplier, speed_ratio)
	
	print("Fast fall damage! Speed: ", velocity.y, " | Multiplier: ", damage_multiplier)
	return damage_multiplier





# Camera shake function for damage feedback
func shake_camera_for_damage(damage_amount: int):
	"""Shake the camera based on damage amount - more damage = stronger shake"""
	var game_camera = get_tree().get_first_node_in_group("game_camera")
	var player_camera = camera
	
	# Calculate shake intensity based on damage (scale from 1-5 damage to 2-15 shake strength)
	var base_shake = 5.0
	var max_shake = 45.0
	var max_damage_for_scaling = 5.0  # Updated for new damage scaling
	var damage_ratio = clamp(float(damage_amount) / max_damage_for_scaling, 0.0, 1.0)
	var shake_strength = lerp(base_shake, max_shake, damage_ratio)
	
	# Calculate duration based on damage (0.1 to 0.4 seconds)
	var base_duration = 0.1
	var max_duration = 0.4
	var shake_duration = lerp(base_duration, max_duration, damage_ratio)
	
	print("Camera shake for ", damage_amount, " damage - strength: ", shake_strength, ", duration: ", shake_duration)
	


	
	# Shake both cameras if they exist
	for target_camera in [game_camera, player_camera]:
		if target_camera:
			_perform_camera_shake(target_camera, shake_strength, shake_duration)

func _perform_camera_shake(target_camera: Camera2D, shake_strength: float, duration: float):
	"""Perform the actual camera shake on a specific camera"""
	var original_offset = target_camera.offset
	var shake_tween = create_tween()
	shake_tween.set_parallel(true)
	
	var shake_steps = int(duration * 20)  # 20 steps per second for smooth shake
	var step_duration = duration / shake_steps
	
	for i in range(shake_steps):
		var progress = float(i) / shake_steps
		var falloff = 1.0 - progress  # Gradually reduce shake intensity
		var current_strength = shake_strength * falloff
		
		var random_offset = Vector2(
			randf_range(-current_strength, current_strength),
			randf_range(-current_strength, current_strength)
		)
		shake_tween.tween_property(target_camera, "offset", original_offset + random_offset, step_duration)
	
	# Return to original position at the end
	shake_tween.tween_property(target_camera, "offset", original_offset, step_duration)

# Visual feedback for head bonk
func flash_sprite():
	if animations:
		# Create a brief flash effect
		var original_modulate = animations.modulate
		animations.modulate = Color.YELLOW  # Flash yellow briefly
		
		# Create a tween to return to normal color
		var tween = create_tween()
		tween.tween_property(animations, "modulate", original_modulate, 0.2)
		
		# Use the new shake system for head bonk feedback
		shake_camera_for_damage(15)  # Moderate shake for head bonk
		
	return

# Health System Functions
func take_damage(damage_amount: int) -> void:
	"""Called when player takes damage - reduces health and updates UI"""
	# Check if player is in ghost mode - ghosts can't take damage
	if is_ghost_mode:
		print("Player is in ghost mode! Damage ignored.")
		if track1.length > 0:
			is_replaying = true
			track_replay_index = 0
		return
		
	# Check if player is invincible
	if is_invincible:
		print("Player is invincible! Damage ignored.")
		return
	
	if current_health <= 0:
		return  # Player is already dead

	set_health(current_health - damage_amount)
	print("Player took ", damage_amount, " damage! Health: ", current_health, "/", max_health)
	
	# Start invincibility frames
	start_invincibility()
	

	
	# Trigger camera shake for damage feedback
	shake_camera_for_damage(damage_amount * 10)  # Scale up for better feedback
	
	# Check if player died
	if current_health <= 0:
		die()


func die() -> void:
	"""Called when player health reaches 0"""
	print("Player died! Entering ghost mode until timer ends...")
	# Instead of restarting the game, enter controllable spirit mode (no damage)
	# Keep position where the player died while track remains active
	set_ghost_mode(true, true)

# ═══════════════════════════════════════════════════════════════════════════════
# GHOST MODE SYSTEM
# ═══════════════════════════════════════════════════════════════════════════════

func set_ghost_mode(ghost: bool, as_spirit: bool = false) -> void:
	"""Set the player's ghost mode state"""
	ghost_is_spirit = ghost and as_spirit
	if ghost:
		# Ensure ghost playback has a full window, but suppress loop_started
		_pad_ring_buffer_to_full()
		loop_triggered = true
		# Default echo state when entering ghost mode (will be updated by playback)
		echo_ghost_dead = as_spirit  # spirit ghosts are always considered dead ghosts
	# Always set flags according to requested state
	is_ghost_mode = ghost
	if not ghost:
		loop_triggered = false
		echo_ghost_dead = false
			
	if is_ghost_mode:
		print("Player entering ghost mode...")
		# Make player appear as a ghost with visual indicator
		if animations:
			animations.modulate = ghost_color_tint  # Apply blue tint and transparency
		
		# Ghost collision setup:
		# - collision_layer = 0: Ghost doesn't exist on any layer (enemies can't target)
		# - collision_mask = 1: Ghost can still collide with tileset for physics
		collision_layer = 0  # Don't exist on any layer - enemies can't target
		collision_mask = 1   # Still collide with ground/platforms for physics
		
		# Disable damage output: keep sword visuals for spirit, hide for echo
		if sword:
			# Spirit: visible and animates, Echo: hide
			sword.visible = ghost_is_spirit or sword.visible
			# Disable any hitboxes in the sword completely
			var hitbox = sword.get_node_or_null("Sprite2D/HitBox")
			if hitbox:
				hitbox.collision_layer = 0  # No collisions -> no damage
		
		# Disable hurtbox so ghost can't take damage from collisions
		var hurtbox = get_node_or_null("HurtBox")
		if hurtbox:
			hurtbox.collision_layer = 0
			hurtbox.collision_mask = 0  # Don't detect any hitboxes
		
		print("Ghost mode activated - player is transparent, can't be targeted, and can't deal/take damage")
	else:
		print("Player exiting ghost mode...")
		# Restore normal appearance and interactions
		if animations:
			animations.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Restore full color and opacity
		
		# Restore normal collisions (based on player.tscn values)
		collision_layer = 2  # Normal player collision layer
		collision_mask = 1   # Normal player collision mask for tileset interaction
		
		# Re-enable combat abilities
		if sword:
			sword.visible = true
			# Re-enable hitboxes in the sword
			var hitbox = sword.get_node_or_null("Sprite2D/HitBox")
			if hitbox:
				# Restore to default layer (3/4 mismatch can vary by setup; default to 4 used by HitBox)
				hitbox.collision_layer = 4
		
		# Re-enable hurtbox for normal damage detection
		var hurtbox = get_node_or_null("HurtBox")
		if hurtbox:
			hurtbox.collision_layer = 0  # HurtBox doesn't need to exist on any layer
			hurtbox.collision_mask = 4   # Detect hitboxes on layer 3

		# Reset health when exiting ghost mode (for next track)
		set_health(max_health)
		print("Ghost mode deactivated - player restored to normal state")

func is_in_ghost_mode() -> bool:
	"""Check if player is currently in ghost mode"""
	return is_ghost_mode

# External helpers for other systems
func is_echo_ghost_alive() -> bool:
	return is_echo_ghost() and not echo_ghost_dead

func is_echo_ghost_dead() -> bool:
	return is_echo_ghost() and echo_ghost_dead

func is_spirit_ghost_alive() -> bool:
	# Spirit ghost is always the dead player controlling; treat as not alive
	return false

# Determine recorded buffer duration in seconds
func get_buffer_duration_seconds() -> float:
	var tps = int(max(1, Engine.get_physics_ticks_per_second())) if _ticks_per_second <= 0 else _ticks_per_second
	if _ticks_per_second <= 0:
		_ticks_per_second = tps
	return float(track1.buffer_size) / float(tps)

# Drive ghost playback by sampling the recorded buffer at a local time [0, duration)
func ghost_playback_at(local_time: float) -> void:
	if track1.length == 0:
		return
	var duration := get_buffer_duration_seconds()
	if duration <= 0.0:
		return
	var tps = _ticks_per_second if _ticks_per_second > 0 else int(max(1, Engine.get_physics_ticks_per_second()))
	var frame := int(floor(clamp(local_time, 0.0, max(0.0, duration - (1.0 / float(tps)))) * float(tps)))
	frame = clamp(frame, 0, max(0, track1.length - 1))
	var tick = track1.get_at(frame)
	if tick == null:
		return
	position = tick.position
	velocity = tick.velocity
	# Update echo ghost liveness from recorded health at this frame
	if not ghost_is_spirit:
		# tick.health is recorded during live play
		var recorded_health = 1
		recorded_health = tick.health
		echo_ghost_dead = recorded_health <= 0
		# Update ghost visuals for echo ghosts
		if animations:
			if echo_ghost_dead:
				animations.modulate = dead_ghost_color_tint
			else:
				animations.modulate = live_ghost_color_tint
	input_just_pressed.clear()
	input_consumed.clear()

# Whether this puppet allows a track switch this tick
func can_switch_tracks() -> bool:
	# Simple lockout: block while rewinding or in early dash frames
	if is_rewinding:
		return false
	if current_action_type == "dash":
		var time_since = total_time - current_action_start_time
		if time_since <= dash_cancel_window:
			return false
	# Meta-time lockout (e.g., after knockback)
	if has_meta("switch_lockout_until"):
		var until_val = float(get_meta("switch_lockout_until"))
		if total_time < until_val:
			return false
	return true
