extends State

@export var land_state: State
@export var move_state: State
@export var idle_state: State
@export var jump_state: State
@export var air_attack_state: State
@export var crouch_state: State
@export var dash_state: State

# ---- Tunables --------------------------------------------------------
@export var fall_gravity_scale: float = 20.0  # Changed from 3000.0 to current fast fall value
@export var fast_fall_gravity_scale: float = 35.0  # Increased from 20.0 for even faster fast fall
@export var terminal_velocity: float  = 3000.0  # Changed from 1500.0 to current fast fall value
@export var fast_fall_terminal_velocity: float = 5000.0  # Increased from 3000.0 for even faster fast fall
@export var air_accel: float          = 100.0
@export var air_friction: float       = 200.0  # Increased from 0.0 for better air control
@export var air_direction_change_multiplier: float = 1.5  # Extra braking force when changing directions in air
@export var max_air_speed: float      = 2000.0
@export var fast_fall_air_speed: float = 150.0  # Reduced air control during fast fall
@export var sword_offset_y: float     = -15.0  # How much to move sword up during fall

# Air camera panning tunables
@export var air_camera_offset_y: float = 60.0  # How much to move camera down when in air
@export var air_camera_transition_speed: float = 4.0  # Slower, smoother camera transition
@export var air_camera_pan_delay: float = 0.1  # Seconds to wait before camera starts panning down in air

# Wall sliding tunables (COMMENTED OUT - Wall sliding disabled)
# @export var wall_slide_gravity_scale: float = 0.8  # Reduced gravity when wall sliding
# @export var wall_slide_max_fall_speed: float = 200.0  # Maximum fall speed while wall sliding
# @export var wall_slide_stick_threshold: float = 50.0  # Minimum speed towards wall to start sliding
# @export var wall_slide_player_overlap_threshold: float = 0.6  # How much of player must overlap with wall (0.0 to 1.0)

# Wall jump tunables (COMMENTED OUT - Wall jumping disabled with wall sliding)
# @export var wall_jump_horizontal_force: float = 400.0  # Horizontal force when wall jumping
# @export var wall_jump_vertical_force: float = 700.0   # Vertical force when wall jumping
# @export var wall_jump_away_from_wall: bool = true     # Whether to jump away from wall or allow any direction

# Enhanced air control from head bonk
var enhanced_air_control: bool = false
var enhanced_control_timer: float = 0.0
var enhanced_control_multiplier: float = 1.0

# Wall sliding state tracking (COMMENTED OUT - Wall sliding disabled)
# var is_currently_wall_sliding: bool = false

# Air camera panning state tracking
var original_camera_offset: Vector2
var target_camera_offset: Vector2
var air_timer: float = 0.0
var camera_tween: Tween  # For smooth camera transitions
# ----------------------------------------------------------------------

var original_sword_position: Vector2

func enter() -> void:
	super()
	# print("Entering fall state")
	# Reset wall sliding state (COMMENTED OUT - Wall sliding disabled)
	# is_currently_wall_sliding = false
	# Reset air timer for camera panning
	air_timer = 0.0
	
	# Store original camera offset and set target for air panning
	if parent.camera:
		original_camera_offset = parent.camera.offset
		target_camera_offset = original_camera_offset + Vector2(0, air_camera_offset_y)
		
		# Kill any existing camera tween
		if camera_tween:
			camera_tween.kill()
	
	# Store original sword position and move it up slightly during fall
	if parent.sword:
		original_sword_position = parent.sword.position
		parent.sword.position = original_sword_position + Vector2(0, sword_offset_y)

func exit() -> void:
	# Reset wall sliding state (COMMENTED OUT - Wall sliding disabled)
	# is_currently_wall_sliding = false
	
	# Smoothly reset camera offset when exiting fall state
	if parent.camera and camera_tween:
		camera_tween.kill()
		camera_tween = parent.create_tween()
		camera_tween.set_ease(Tween.EASE_OUT)
		camera_tween.set_trans(Tween.TRANS_QUART)
		camera_tween.tween_property(parent.camera, "offset", original_camera_offset, 0.4)
	elif parent.camera:
		parent.camera.offset = original_camera_offset
	
	# Reset sword position when exiting fall, but let player handle direction
	if parent.sword:
		parent.sword.position.y = original_sword_position.y  # Reset Y position only
		parent.update_sword_position()  # Let the player handle X position based on current facing direction

func process_frame(delta: float) -> State:
	# Handle input processing every frame using polling system
	if parent.is_action_just_pressed_once("jump"):
		# Wall jumping functionality disabled - commenting out wall slide jump check
		# Check if we're wall sliding and can perform a wall jump
		# if is_currently_wall_sliding:
		#	perform_wall_jump()
		#	return jump_state
		# Check for coyote jump
		if parent.can_coyote_jump():
			print("Coyote jump from fall state!")
			return jump_state
		else:
			# Can't jump right now, but buffer the input
			parent.buffer_jump()
			
	if parent.is_action_just_pressed_once('attack'):
		return air_attack_state
		
	# Don't transition to crouch state if already holding crouch
	# This prevents unnecessary state switching between fall and crouch
	if parent.is_action_just_pressed_once('crouch'):
		return crouch_state
		
	# Allow air dash
	if parent.is_action_just_pressed_once('dash'):
		# Check if dash is available and air dash is enabled
		if dash_state and dash_state.is_dash_available() and dash_state.air_dash_enabled:
			return dash_state
		else:
			print("Air dash on cooldown! Buffering dash input...")
			parent.buffer_input("dash")
	
	# Check for buffered inputs that can now be executed
	if parent.has_valid_dash_buffer() and dash_state and dash_state.is_dash_available():
		print("Executing buffered dash!")
		parent.consume_input_buffer("dash")
		return dash_state
	
	# Update air timer for camera panning
	air_timer += delta
	
	# Start smooth camera panning after the delay
	if parent.camera and air_timer >= air_camera_pan_delay and not camera_tween:
		camera_tween = parent.create_tween()
		camera_tween.set_ease(Tween.EASE_OUT)
		camera_tween.set_trans(Tween.TRANS_QUART)
		camera_tween.tween_property(parent.camera, "offset", target_camera_offset, 0.5)  # Smooth 0.5 second transition
	
	# Update animation based on whether player is fast falling
	if parent.is_action_pressed_polling("crouch"):
		parent.animations.play("crouch")
	else:
		# You can add a specific fall animation here if one exists
		# For now, we'll let the default animation play
		pass
	return null

func process_input(_event: InputEvent) -> State:
	# Input processing moved to process_frame for polling system
	return null

func process_physics(delta: float) -> State:
	# Update dash cooldown
	if dash_state:
		dash_state.update_cooldown(delta)
		
	# Check if player is holding crouch for fast fall
	var is_fast_falling = parent.is_action_pressed_polling("crouch")
	
	# Get input axis for wall sliding detection (COMMENTED OUT - Wall sliding disabled)
	# var axis := Input.get_axis("move_left","move_right")
	
	# Check for wall sliding conditions (COMMENTED OUT - Wall sliding disabled)
	# var is_wall_sliding = false
	# if parent.is_on_wall() and axis != 0:
	#	# Check if player is moving towards the wall
	#	var wall_normal = parent.get_wall_normal()
	#	var moving_towards_wall = (axis > 0 and wall_normal.x < 0) or (axis < 0 and wall_normal.x > 0)
	#	
	#	# Check if player is falling and still sufficiently overlapping with wall
	#	if moving_towards_wall and parent.velocity.y > 0 and is_player_overlapping_wall():
	#		is_wall_sliding = true
	#		# print("Wall sliding activated!")
	
	# Update wall sliding state tracking (COMMENTED OUT - Wall sliding disabled)
	# is_currently_wall_sliding = is_wall_sliding
	#var is_wall_sliding = false  # Always false since wall sliding is disabled
	
	# Apply appropriate gravity and terminal velocity based on state
	var gravity_scale: float
	var max_fall_velocity: float
	var air_speed_limit: float
	
	# Wall sliding physics disabled - using simplified fall physics
	# if is_wall_sliding:
	#	gravity_scale = wall_slide_gravity_scale
	#	max_fall_velocity = wall_slide_max_fall_speed
	#	air_speed_limit = max_air_speed  # Normal air speed while wall sliding
	if is_fast_falling:
		gravity_scale = fast_fall_gravity_scale
		max_fall_velocity = fast_fall_terminal_velocity
		air_speed_limit = fast_fall_air_speed
	else:
		gravity_scale = fall_gravity_scale
		max_fall_velocity = terminal_velocity
		air_speed_limit = max_air_speed
	
	# Debug output for wall sliding (COMMENTED OUT - Wall sliding disabled)
	# if is_wall_sliding:
	#	# print("Wall sliding! Velocity: ", parent.velocity.y, " | Gravity scale: ", gravity_scale)
	#	pass  # Debug output disabled
	if is_fast_falling and parent.velocity.y > 0:
		# print("Fast falling with crouch! Velocity: ", parent.velocity.y)
		pass  # Debug output disabled
	
	# Gravity with clamp
	parent.velocity.y = min(
		parent.velocity.y + gravity * gravity_scale * delta,
		max_fall_velocity
	)

	# Horizontal control (enhanced after head bonk, wall sliding disabled)
	var base_air_speed = air_speed_limit
	
	# Apply enhanced air control if active
	var current_air_accel = air_accel
	if enhanced_air_control:
		enhanced_control_timer -= delta
		current_air_accel *= enhanced_control_multiplier
		air_speed_limit = base_air_speed * 1.2  # Also boost max air speed slightly
		
		if enhanced_control_timer <= 0.0:
			enhanced_air_control = false
			# print("Enhanced air control expired in fall state")

	var axis := Input.get_axis("move_left","move_right")  # Added back for horizontal movement
	var target: float = axis * air_speed_limit

	if axis != 0:
		# Check if we're changing direction in air (input and current velocity have opposite signs)
		var is_changing_direction = (axis > 0 and parent.velocity.x < 0) or (axis < 0 and parent.velocity.x > 0)
		
		# Apply stronger braking force when changing directions in air
		var effective_air_accel = current_air_accel
		if is_changing_direction:
			effective_air_accel = current_air_accel * air_direction_change_multiplier
		
		parent.velocity.x = move_toward(parent.velocity.x, target, effective_air_accel * delta)
		parent.animations.flip_h = axis < 0
	else:
		# No input - apply stronger friction to make player fall straight down quickly
		var no_input_friction = air_friction * 3.0  # Much stronger friction when no input
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, no_input_friction * delta)

	parent.move_and_slide()
	
	# Check for buffered jump that can now be executed
	if parent.has_valid_input_buffer("jump") and parent.can_jump():
		# print("Executing buffered jump from fall state!")
		parent.consume_input_buffer("jump")
		return jump_state
	
	# Check for head bonk during fall (rare but possible)
	# This can happen if player hits ceiling while falling upward from a bounce or something
	if parent.velocity.y < 0:
		# print("Head bonk during fall state!")
		pass  # Head bonk handling is done in the check function

	if parent.is_on_floor():
		return land_state

	return null

# Perform a wall jump (COMMENTED OUT - Wall jumping disabled)
# func perform_wall_jump():
#	print("Wall jump performed!")
#	
#	# Get the wall normal to determine jump direction
#	var wall_normal = parent.get_wall_normal()
#	
#	# Set vertical velocity
#	parent.velocity.y = -wall_jump_vertical_force
#	
#	# Set horizontal velocity based on wall jump settings
#	if wall_jump_away_from_wall:
#		# Jump away from the wall
#		parent.velocity.x = wall_normal.x * wall_jump_horizontal_force
#		# Update sprite direction to face away from wall
#		parent.animations.flip_h = wall_normal.x > 0
#	else:
#		# Allow player input to determine direction (more flexible)
#		var axis = Input.get_axis("move_left", "move_right")
#		if axis != 0:
#			parent.velocity.x = axis * wall_jump_horizontal_force
#			parent.animations.flip_h = axis < 0
#		else:
#			# If no input, default to jumping away from wall
#			parent.velocity.x = wall_normal.x * wall_jump_horizontal_force
#			parent.animations.flip_h = wall_normal.x > 0
#	
#	# Reset wall sliding state
#	is_currently_wall_sliding = false
#	
#	# Mark that player jumped (for coyote time system)
#	parent.mark_jumped_off_ground()
#	parent.coyote_timer = 0.0
#	parent.coyote_available = false

# Check if player is still sufficiently overlapping with wall for wall sliding (COMMENTED OUT - Wall sliding disabled)
# func is_player_overlapping_wall() -> bool:
#	if not parent.is_on_wall():
#		return false
#	
#	# Get the player's collision shape
#	var collision_shape = parent.get_node("CollisionShape2D") as CollisionShape2D
#	if not collision_shape or not collision_shape.shape:
#		return false
#	
#	# Get player bounds
#	var shape_rect = collision_shape.shape.get_rect()
#	var player_top = parent.global_position.y - (shape_rect.size.y * collision_shape.scale.y / 2)
#	var player_bottom = parent.global_position.y + (shape_rect.size.y * collision_shape.scale.y / 2)
#	var player_height = shape_rect.size.y * collision_shape.scale.y
#	
#	# Use raycast to find the wall bounds
#	var space_state = parent.get_world_2d().direct_space_state
#	var wall_normal = parent.get_wall_normal()
#	
#	# Cast rays from player position to find wall boundaries
#	var ray_start_x = parent.global_position.x
#	var ray_direction = Vector2(-wall_normal.x, 0) * 32  # Cast 32 pixels toward wall
#	
#	# Cast rays at different heights to find wall bounds
#	var wall_top = player_bottom  # Default to player bottom if no wall found above
#	var wall_bottom = player_top  # Default to player top if no wall found below
#	
#	# Cast rays upward to find wall top
#	for i in range(5):
#		var ray_y = player_top - (i * 16)  # Check every 16 pixels above player
#		var query = PhysicsRayQueryParameters2D.create(
#			Vector2(ray_start_x, ray_y),
#			Vector2(ray_start_x, ray_y) + ray_direction
#		)
#		query.collision_mask = 1  # Assuming walls are on collision layer 1
#		var result = space_state.intersect_ray(query)
#		
#		if not result:
#			wall_top = ray_y
#			break
#	
#	# Cast rays downward to find wall bottom
#	for i in range(5):
#		var ray_y = player_bottom + (i * 16)  # Check every 16 pixels below player
#		var query = PhysicsRayQueryParameters2D.create(
#			Vector2(ray_start_x, ray_y),
#			Vector2(ray_start_x, ray_y) + ray_direction
#		)
#		query.collision_mask = 1  # Assuming walls are on collision layer 1
#		var result = space_state.intersect_ray(query)
#		
#		if not result:
#			wall_bottom = ray_y
#			break
#	
#	# Calculate overlap
#	var wall_height = wall_bottom - wall_top
#	var overlap_top = max(player_top, wall_top)
#	var overlap_bottom = min(player_bottom, wall_bottom)
#	var overlap_height = max(0, overlap_bottom - overlap_top)
#	
#	var overlap_ratio = overlap_height / player_height
#	
#	# Debug output (can be removed later)
#	if overlap_ratio < wall_slide_player_overlap_threshold:
#		print("Wall slide ending - overlap ratio: ", overlap_ratio, " (threshold: ", wall_slide_player_overlap_threshold, ")")
#	
#	return overlap_ratio >= wall_slide_player_overlap_threshold

# Method to receive enhanced air control from jump state after head bonk
func receive_enhanced_control(timer: float, multiplier: float):
	enhanced_air_control = true
	enhanced_control_timer = timer
	enhanced_control_multiplier = multiplier
	print("Fall state received enhanced air control! Timer: ", timer, " Multiplier: ", multiplier)
