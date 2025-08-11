extends CharacterBody2D
## REWIND SYSTEM (sync with player)
# -- Set up ring buffer for enemy -- #
@onready var track1: RingBuffer = RingBuffer.create_by_seconds(15, Engine.get_physics_ticks_per_second())
var is_replaying: bool = false
var track_replay_index: int = 0
var loop_triggered: bool = false

# Ghost system
var is_ghost_mode: bool = false
var echo_ghost_dead: bool = false
@export var dead_ghost_color_tint: Color = Color(0.3, 0.3, 0.3, 0.22)
@export var live_ghost_color_tint: Color = Color(0.6, 0.6, 1.0, 0.55)



@onready var animation_player := $AnimationPlayer
@onready var sprite := $Sprite2D

# Physics variables (matching player physics system)
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")  # Base gravity from project settings
@export var fall_gravity_scale: float = 20.0  # Same as player's fall state
@export var fast_fall_gravity_scale: float = 35.0  # Same as player's fast fall
@export var terminal_velocity: float = 3000.0  # Same as player's terminal velocity
@export var fast_fall_terminal_velocity: float = 5000.0  # Same as player's fast fall terminal velocity
@export var friction: float = 0.95   # Ground friction for sliding (increased from 0.8)
@export var air_friction: float = 0.98  # Air resistance

# Collision prevention
@export var collision_safety_margin: float = 2.0  # Extra margin to prevent getting stuck
@export var max_horizontal_penetration: float = 5.0  # Max allowed horizontal penetration before correction

# Knockback variables
@export var knockback_resistance: float = 1.0  # How much knockback to apply (0.0 = no knockback, 1.0 = full knockback)
@export var max_knockback_velocity: float = 800.0  # Maximum knockback speed
@export var min_velocity_threshold: float = 2.0  # Minimum velocity to continue moving (reduced from 10.0)

# Health and status
@export var max_health: int = 2
var current_health: int = 2

# Enemy invincibility system (similar to player)
@export var spawn_invincibility_duration: float = 1  # Brief invincibility on spawn
var spawn_invincibility_timer: float = 0.0
var is_spawn_invincible: bool = false

# Movement variables
@export var move_speed: float = 300.0  # Increased from 100.0 for faster, more challenging enemies
@export var patrol_range: float = 2000.0  # How far the enemy patrols (increased from 1000.0)
@export var chase_range: float = 2500.0   # How far the enemy will chase the player (increased from 1000.0)
@export var return_to_patrol_range: float = 800.0  # Distance at which enemy stops chasing and returns (increased from 400.0)


# Jump variables
@export var jump_velocity: float = -800.0  # Much higher jump - twice as high as player short jump
@export var jump_cooldown: float = 0.8  # Reduced from 1.0 for more frequent jumping
@export var jump_threshold_height: float = 120.0  # Increased from 80.0 to handle taller obstacles
@export var can_jump_gaps: bool = true  # Whether enemy can jump small gaps
@export var max_jump_gap_width: float = 150.0  # Maximum gap width the enemy will attempt to jump
var jump_timer: float = 0.0  # Timer for jump cooldown

# Line of sight detection variables
@export var sight_range: float = 150000.0   # How far the enemy can see the player (increased from 300.0)
@export var sight_angle: float = 120.0   # Field of view in degrees (60 degrees each side)
@export var sight_check_interval: float = 5  # How often to check line of sight (in seconds)
var sight_check_timer: float = 0.0

# Edge detection variables
@export var edge_detection_distance: float = 250.0  # How far ahead to check for edges
@export var wall_detection_distance: float = 500.0  # How far ahead to check for walls

# Attack variables
@export var attack_range: float = 60.0   # Distance at which enemy can attack
@export var attack_damage: int = 1  # Changed to 1 to take 1 heart per hit
@export var attack_cooldown: float = 1.5 # Seconds between attacks
@export var attack_knockback_force: float = 500.0
@export var attack_state_duration: float = 0.8  # Minimum time to stay in attack state
@export var attack_state_exit_range: float = 80.0  # Slightly larger than attack_range to prevent rapid state switching

# Passive body damage variables
@export var passive_body_damage_enabled: bool = true  # Whether touching enemy damages player
@export var passive_body_damage: int = 1  # Damage dealt by touching enemy body
@export var passive_damage_cooldown: float = 1.0  # Cooldown between passive damage instances
@export var passive_body_knockback_enabled: bool = true 
@export var passive_body_knockback: int = 1



# AI State variables
enum EnemyState { PATROL, CHASE, ATTACK, RETURN_TO_PATROL, SEARCH_ALTERNATE_PATH }
var current_state: EnemyState = EnemyState.PATROL
var patrol_start_position: Vector2
var patrol_direction: int = 1  # 1 for right, -1 for left
var attack_timer: float = 0.0
var attack_state_timer: float = 0.0  # Timer to prevent rapid attack state switching
var passive_damage_timer: float = 0.0  # Timer for passive damage cooldown
var player: CharacterBody2D = null
var last_known_player_position: Vector2
var is_attacking: bool = false  # Flag to prevent multiple simultaneous attacks

# Pathfinding and approach tracking variables
var stuck_timer: float = 0.0  # How long enemy has been stuck trying to reach player
var stuck_threshold: float = 3.0  # Seconds before considering alternative approach
var last_distance_to_player: float = 0.0  # Track if we're getting closer to player
var distance_check_timer: float = 0.0  # Timer for checking progress
var failed_jump_attempts: int = 0  # Track consecutive failed jump attempts
var max_failed_jumps: int = 3  # Max failed jumps before trying alternate path
var alternate_search_timer: float = 0.0  # How long to search for alternate path
var alternate_search_duration: float = 5.0  # Seconds to search before giving up
var original_chase_direction: int = 1  # Remember original chase direction

# Targeting behavior options
enum TargetMode { ACTIVE_ONLY, NEAREST_PLAYER }
@export var target_mode: TargetMode = TargetMode.ACTIVE_ONLY
@export var ignore_ghost_players: bool = true

# Decision Tree System
class DecisionTreeNode extends RefCounted:
	"""Base class for all decision tree nodes"""
	func evaluate(_enemy) -> String:
		return "default"

class ConditionNode extends DecisionTreeNode:
	"""A node that checks a condition and returns different actions based on result"""
	var condition_func: Callable
	var true_node: DecisionTreeNode
	var false_node: DecisionTreeNode
	
	func _init(condition: Callable, true_action: DecisionTreeNode, false_action: DecisionTreeNode):
		condition_func = condition
		true_node = true_action
		false_node = false_action
	
	func evaluate(enemy) -> String:
		if condition_func.call(enemy):
			return true_node.evaluate(enemy)
		else:
			return false_node.evaluate(enemy)

class ActionNode extends DecisionTreeNode:
	"""A leaf node that returns a specific action"""
	var action_name: String
	
	func _init(action: String):
		action_name = action
	
	func evaluate(_enemy) -> String:
		return action_name

# Decision Tree Instance
var decision_tree: DecisionTreeNode

func _ready():
	# Add the enemy to a group so other systems can find it
	add_to_group("enemy")
	add_to_group("enemies")
	is_ghost_mode = false
	echo_ghost_dead = false
	current_health = max_health
	patrol_start_position = global_position
	
	# Scale down the enemy to fit better on platforms
	scale = Vector2(0.8, 0.8)  # Make enemy 80% of original size
	
	# Start with brief spawn invincibility to prevent immediate damage
	is_spawn_invincible = true
	spawn_invincibility_timer = spawn_invincibility_duration
	
	print("Enemy _ready() called - Initial Health: ", current_health, "/", max_health)
	print("Enemy spawn invincibility active for: ", spawn_invincibility_duration, " seconds")
	print("Enemy position: ", global_position)
	print("Enemy is_on_floor(): ", is_on_floor())
	print("Enemy patrol start position: ", patrol_start_position)
	
	# Enable the passive body hitbox
	_setup_passive_body_hitbox()
	
	# Resolve the active player from the PlayerManager first; fallback to group/search
	_resolve_active_player()
	if not player:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
			print("Enemy found player (fallback): ", player.name)
		else:
			print("Warning: No player found in 'player' group. Searching for Player node...")
			# Search the scene tree for a Player node
			var scene_root = get_tree().current_scene
			if scene_root:
				player = _find_player_recursive(scene_root)
				if player:
					print("Enemy found player by search: ", player.name)
				else:
					print("Warning: No player found! Enemy will only patrol.")
	
	print("Enemy _ready() called - Health: ", current_health)
	print("Enemy position: ", global_position)
	print("Enemy is_on_floor(): ", is_on_floor())
	print("Enemy patrol start position: ", patrol_start_position)
	
	# Build the decision tree
	_build_decision_tree()

# Start a fresh 15s live take for the enemy (clear loop/buffer and reset AI timers)
func begin_live_take() -> void:
	is_replaying = false
	track1.clear()
	track_replay_index = 0
	loop_triggered = false
	# Reset transient timers/state
	attack_timer = 0.0
	attack_state_timer = 0.0
	passive_damage_timer = 0.0
	jump_timer = 0.0
	stuck_timer = 0.0
	failed_jump_attempts = 0
	alternate_search_timer = 0.0
	# Return to baseline behavior
	current_state = EnemyState.PATROL
	is_ghost_mode = false
	echo_ghost_dead = false
	if sprite:
		sprite.modulate = Color(1,1,1,1)
# Set ghost mode (echo ghost for inactive tracks)
func set_ghost_mode(ghost: bool) -> void:
	is_ghost_mode = ghost
	if not ghost:
		echo_ghost_dead = false
		if sprite:
			sprite.modulate = Color(1,1,1,1)
# Echo ghost playback for inactive tracks
func ghost_playback_at(local_time: float) -> void:
	if track1.length == 0:
		return
	var tps = int(max(1, Engine.get_physics_ticks_per_second()))
	var duration = float(track1.buffer_size) / float(tps)
	if duration <= 0.0:
		return
	var frame = int(floor(clamp(local_time, 0.0, max(0.0, duration - (1.0 / float(tps)))) * float(tps)))
	frame = clamp(frame, 0, max(0, track1.length - 1))
	var tick = track1.get_at(frame)
	if tick == null:
		return
	position = tick.position
	velocity = tick.velocity
	# Dead/alive ghost visual
	var recorded_health = tick.health if tick.has("health") else 1
	echo_ghost_dead = recorded_health <= 0
	if sprite:
		if echo_ghost_dead:
			sprite.modulate = dead_ghost_color_tint
		else:
			sprite.modulate = live_ghost_color_tint

# Alias for clarity
func restart_loop() -> void:
	begin_live_take()

func reset_to_spawn() -> void:
		global_position = patrol_start_position
		velocity = Vector2.ZERO

# Ensure the enemy tracks the currently active player across track switches
func _resolve_active_player() -> void:
	var pm = get_tree().get_first_node_in_group("player_manager")
	if pm and pm.tracks.size() > 0:
		# Always target the player on track 1, regardless of active track
		player = pm.tracks[0]

# Resolve target according to configured mode
func _resolve_target_player() -> void:
	match target_mode:
		TargetMode.ACTIVE_ONLY:
			_resolve_active_player()
		TargetMode.NEAREST_PLAYER:
			var candidates = get_tree().get_nodes_in_group("player")
			var best: CharacterBody2D = null
			var best_dist := INF
			for p in candidates:
				if ignore_ghost_players and p.has_method("is_in_ghost_mode") and p.is_in_ghost_mode():
					continue
				var d = global_position.distance_to(p.global_position)
				if d < best_dist:
					best = p
					best_dist = d
			if best:
				player = best

# Recursive function to find player
func _find_player_recursive(node: Node) -> CharacterBody2D:
	# Check if this node is the player by name
	if node.name == "Player":
		return node as CharacterBody2D
	
	# Check if this node has a script that contains "player"
	if node.get_script() != null:
		var script = node.get_script()
		var script_path = script.get_path() if script else ""
		if "player.gd" in script_path.to_lower():
			return node as CharacterBody2D
	
	# Check children recursively
	for child in node.get_children():
		var result = _find_player_recursive(child)
		if result:
			return result
	
	return null

# Decision Tree Building and Conditions
func _build_decision_tree():
	"""Build the enemy's decision tree for AI behavior"""
	# Define all the leaf actions
	var attack_action = ActionNode.new("attack")
	var chase_action = ActionNode.new("chase")
	var patrol_action = ActionNode.new("patrol")
	var return_action = ActionNode.new("return_to_patrol")
	var jump_to_player_action = ActionNode.new("jump_to_player")
	var search_alternate_action = ActionNode.new("search_alternate_path")
	
	# Build a smarter tree structure with alternate pathfinding
	# Level 5: Check if stuck and need alternate path
	var stuck_check = ConditionNode.new(
		_should_search_alternate_path,
		search_alternate_action,
		ConditionNode.new(
			_should_jump_to_player,
			jump_to_player_action,
			ConditionNode.new(
				_is_in_attack_range,
				attack_action,
				chase_action
			)
		)
	)
	
	# Level 4: Continue chase vs return
	var _continue_vs_return = ConditionNode.new(
		_should_continue_chase,
		stuck_check,  # Use smart pathfinding when chasing
		return_action
	)
	
	# Level 3: Player detected vs not detected
	var player_detected = ConditionNode.new(
		_can_detect_player,
		stuck_check,  # Always use smart pathfinding when player detected
		ConditionNode.new(
			_should_return_to_patrol,
			return_action,
			patrol_action
		)
	)
	
	# Level 2: Root - Player exists check
	decision_tree = ConditionNode.new(
		_player_exists,
		player_detected,
		patrol_action
	)
	
	print("Decision tree built successfully with smart pathfinding behavior")

# Decision Tree Condition Functions
func _player_exists(_enemy) -> bool:
	"""Check if player reference exists and is valid"""
	return player != null and is_instance_valid(player)

func _can_detect_player(_enemy) -> bool:
	"""Check if enemy can detect the player (sight or proximity)"""
	if not player:
		return false
	
	var distance = global_position.distance_to(player.global_position)
	
	# Check proximity detection first (always works)
	if distance <= chase_range:
		return true
	
	# Check line of sight if within sight range
	if distance <= sight_range and sight_check_timer <= 0:
		sight_check_timer = sight_check_interval
		return can_see_player()
	
	return false

func _should_jump_to_player(_enemy) -> bool:
	"""Check if enemy should jump up to reach player on a higher platform"""
	if not player or jump_timer > 0 or not is_on_floor():
		if randf() < 0.1:  # Debug output
			print("Jump check failed: player=", player != null, " jump_timer=", jump_timer, " on_floor=", is_on_floor())
		return false
	
	var player_pos = player.global_position
	var enemy_pos = global_position
	
	# Check if player is above and within horizontal range
	var horizontal_distance = abs(player_pos.x - enemy_pos.x)
	var vertical_distance = enemy_pos.y - player_pos.y  # Positive if player is above
	
	# Debug output
	if randf() < 0.1:
		print("Jump check - H_dist: ", horizontal_distance, " V_dist: ", vertical_distance, " Player above: ", vertical_distance > 20)
	
	# More realistic jump conditions - enemy can only jump so high
	if vertical_distance > 5 and vertical_distance <= 300 and horizontal_distance <= 150:
		# Check if there's actually a clear path to jump
		var space_state = get_world_2d().direct_space_state
		
		# Check for obstacles in jump path
		var jump_path_check = PhysicsRayQueryParameters2D.create(
			enemy_pos + Vector2(0, -10),
			Vector2(player_pos.x, enemy_pos.y - 200)  # Check jump arc
		)
		jump_path_check.collision_mask = 1
		jump_path_check.exclude = [self, player]
		
		var path_result = space_state.intersect_ray(jump_path_check)
		
		if path_result.is_empty():
			print("Enemy should jump to reach player! H_dist:", horizontal_distance, " V_dist:", vertical_distance, " (SMART JUMP)")
			return true
		else:
			print("Jump path blocked by obstacle - will try alternate route")
			failed_jump_attempts += 1
			return false
	
	return false

func _is_in_attack_range(_enemy) -> bool:
	"""Check if player is within attack range and attack is ready"""
	if not player:
		return false
	
	var distance = global_position.distance_to(player.global_position)
	return distance <= attack_range and attack_timer <= 0

func _should_continue_chase(_enemy) -> bool:
	"""Check if enemy should continue chasing or return to patrol"""
	if not player:
		return false
	
	var distance = global_position.distance_to(player.global_position)
	return distance <= return_to_patrol_range

func _should_return_to_patrol(_enemy) -> bool:
	"""Check if enemy should return to patrol area"""
	var distance_to_start = global_position.distance_to(patrol_start_position)
	return distance_to_start > 50.0  # If far from patrol start, return

func _should_search_alternate_path(_enemy) -> bool:
	"""Check if enemy should search for alternate path to reach player"""
	if not player or current_state != EnemyState.CHASE:
		return false
	
	# Check if enemy has been stuck trying to reach player
	if stuck_timer >= stuck_threshold:
		print("Enemy stuck for ", stuck_timer, " seconds - searching alternate path")
		return true
	
	# Check if enemy has failed too many jump attempts
	if failed_jump_attempts >= max_failed_jumps:
		print("Enemy failed ", failed_jump_attempts, " jump attempts - searching alternate path")
		return true
	
	return false

# Decision Tree Execution
func execute_decision_tree() -> String:
	"""Execute the decision tree and return the action to take"""
	if decision_tree:
		return decision_tree.evaluate(self)
	return "patrol"  # Default fallback

# Decision Tree Debugging
func debug_decision_tree():
	"""Print current decision tree evaluation for debugging"""
	print("=== Decision Tree Debug ===")
	print("Player exists: ", _player_exists(self))
	if _player_exists(self):
		print("Can detect player: ", _can_detect_player(self))
		print("Is in attack range: ", _is_in_attack_range(self))
		print("Should continue chase: ", _should_continue_chase(self))
	print("Should return to patrol: ", _should_return_to_patrol(self))
	print("Final action: ", execute_decision_tree())
	print("==========================")

# Decision Tree Expansion Functions
func add_new_behavior(condition_name: String, _condition_func: Callable, action_name: String):
	"""Add a new behavior branch to the decision tree"""
	# This is a simplified example - in practice you'd rebuild the tree
	# or have a more sophisticated tree modification system
	print("Adding new behavior: ", condition_name, " -> ", action_name)

func create_custom_decision_tree():
	"""Example of how to create a custom decision tree"""
	# You can completely customize the decision tree structure
	var custom_tree = ConditionNode.new(
		func(enemy): return enemy._player_exists(enemy),
		ConditionNode.new(
			func(enemy): return enemy._is_in_attack_range(enemy),
			ActionNode.new("attack"),
			ActionNode.new("chase")
		),
		ActionNode.new("patrol")
	)
	
	decision_tree = custom_tree
	print("Custom decision tree created")

# Setup the passive body hitbox for contact damage
func _setup_passive_body_hitbox():
	var body_hitbox = get_node_or_null("BodyHitBox")
	if body_hitbox:
		# Set damage values for the passive hitbox
		body_hitbox.damage = passive_body_damage
		body_hitbox.knockback_multiplier = 200.0  # Lighter knockback for passive contact
		
		# Enable the collision shape
		var collision_shape = body_hitbox.get_node_or_null("CollisionShape2D")
		if collision_shape:
			collision_shape.disabled = false if passive_body_damage_enabled else true
			print("Enemy passive body hitbox configured - damage: ", passive_body_damage, ", enabled: ", passive_body_damage_enabled)
		else:
			print("Warning: BodyHitBox CollisionShape2D not found")
	else:
		print("Warning: BodyHitBox not found in enemy scene")

# Toggle passive body damage on/off
func set_passive_body_damage_enabled(enabled: bool):
	passive_body_damage_enabled = enabled
	var body_hitbox = get_node_or_null("BodyHitBox")
	if body_hitbox:
		var collision_shape = body_hitbox.get_node_or_null("CollisionShape2D")
		if collision_shape:
			collision_shape.disabled = not enabled
			print("Enemy passive body damage ", "enabled" if enabled else "disabled")

func _physics_process(delta):
	# Ghost mode: echo ghosts are sampled externally, skip normal logic
	if is_ghost_mode:
		return

	# Refresh target selection according to configured targeting mode
	_resolve_target_player()

	# REWIND SYSTEM
	if is_replaying:
		if track1.length == 0:
			return
		var tick = track1.get_at(track_replay_index)
		if tick:
			self.position = tick.position
			self.velocity = tick.velocity
		# Move backward, wrap around if needed
		track_replay_index -= 1
		if track_replay_index < 0:
			# Clamp at beginning and stop rewinding to avoid looping
			track_replay_index = 0
			stop_rewind()
		return

	# Record enemy state to buffer (only if not rewinding)
	track1.push({
		"position": self.position,
		"velocity": self.velocity,
		"health": current_health
	})

	# Normal enemy update and movement code
	# Update spawn invincibility timer
	if is_spawn_invincible:
		spawn_invincibility_timer -= delta
		if spawn_invincibility_timer <= 0.0:
			is_spawn_invincible = false
			print("Enemy spawn invincibility ended")

	# AI behavior based on current state
	update_ai_behavior(delta)

	# Apply friction/air resistance only if not actively moving
	var is_actively_moving = false
	match current_state:
		EnemyState.PATROL, EnemyState.CHASE, EnemyState.RETURN_TO_PATROL:
			is_actively_moving = true
		EnemyState.ATTACK:
			is_actively_moving = false

	# Only apply friction when not actively trying to move
	if not is_actively_moving:
		if is_on_floor():
			# Ground friction
			velocity.x *= friction
			if abs(velocity.x) < min_velocity_threshold:
				velocity.x = 0.0
		else:
			# Air resistance
			velocity.x *= air_friction

	# Apply gravity if not on floor (using player's gravity scale system)
	if not is_on_floor():
		var gravity_scale = fall_gravity_scale
		var max_fall_velocity = terminal_velocity
		velocity.y = min(
			velocity.y + gravity * gravity_scale * delta,
			max_fall_velocity
		)

	# Check for and resolve horizontal collisions to prevent getting jammed
	if is_on_wall():
		var collision_info = move_and_collide(Vector2.ZERO, true)
		if collision_info:
			var penetration_depth = collision_info.get_travel().length()
			if penetration_depth > max_horizontal_penetration:
				var push_direction = collision_info.get_normal()
				global_position += push_direction * (collision_safety_margin + penetration_depth)
				velocity.x *= 0.5
				if randf() < 0.1:
					print("Enemy pushed away from wall, penetration: ", penetration_depth)

	# Apply the movement
	move_and_slide()

	# Additional safety check: if enemy is still overlapping significantly, move it out
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var collision = get_slide_collision(i)
			if collision and collision.get_travel().length() > max_horizontal_penetration:
				global_position += collision.get_normal() * collision_safety_margin
# Start rewinding the enemy's recorded path
func start_rewind() -> void:
	if track1.length == 0:
		return
	is_replaying = true
	track_replay_index = (track1.length - 1) if track1.length > 0 else 0

# Stop rewinding and return to normal control
func stop_rewind() -> void:
	is_replaying = false

# AI Behavior System (Decision Tree Based)
func update_ai_behavior(_delta: float):
	# Re-try finding player if we don't have one
	if not player or not is_instance_valid(player):
		_try_find_player()
	
	# Execute decision tree to get next action
	var action = execute_decision_tree()
	
	# Debug output for decision tree
	if randf() < 0.05:  # More frequent debug
		print("=== AI Debug ===")
		print("Action: ", action, " | State: ", get_current_state_name())
		if player:
			print("Player detected: ", _can_detect_player(self))
			print("Should jump to player: ", _should_jump_to_player(self))
			print("In attack range: ", _is_in_attack_range(self))
		print("================")
	
	# Execute the chosen action
	match action:
		"attack":
			if current_state != EnemyState.ATTACK:
				current_state = EnemyState.ATTACK
				attack_state_timer = attack_state_duration
				print("Decision Tree: Switching to ATTACK")
			attack_behavior()
			
		"chase":
			if current_state != EnemyState.CHASE:
				current_state = EnemyState.CHASE
				last_known_player_position = player.global_position
				# Reset pathfinding tracking when starting new chase
				stuck_timer = 0.0
				failed_jump_attempts = 0
				last_distance_to_player = 0.0
				print("Decision Tree: Switching to CHASE")
			chase_behavior()
			
		"jump_to_player":
			if current_state != EnemyState.CHASE:
				current_state = EnemyState.CHASE
				last_known_player_position = player.global_position
				print("Decision Tree: Switching to JUMP_TO_PLAYER")
			jump_to_player_behavior()
			
		"search_alternate_path":
			if current_state != EnemyState.SEARCH_ALTERNATE_PATH:
				current_state = EnemyState.SEARCH_ALTERNATE_PATH
				alternate_search_timer = 0.0
				if player:
					original_chase_direction = 1 if player.global_position.x > global_position.x else -1
				print("Decision Tree: Switching to SEARCH_ALTERNATE_PATH")
			search_alternate_path_behavior()
			
		"return_to_patrol":
			if current_state != EnemyState.RETURN_TO_PATROL:
				current_state = EnemyState.RETURN_TO_PATROL
				print("Decision Tree: Switching to RETURN_TO_PATROL")
			return_to_patrol_behavior()
			
		"patrol":
			if current_state != EnemyState.PATROL:
				current_state = EnemyState.PATROL
				print("Decision Tree: Switching to PATROL")
			patrol_behavior()
			
		_:
			# Fallback to patrol
			patrol_behavior()

# Helper function to try finding the player
func _try_find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		print("Enemy found player: ", player.name)
	else:
		# Alternative: search for node by class name
		var scene_root = get_tree().current_scene
		if scene_root:
			player = _find_player_recursive(scene_root)
			if player:
				print("Enemy found player by search: ", player.name)

func patrol_behavior():
	# Check for obstacles and edges before moving
	var can_move_forward = can_move_in_direction(patrol_direction)
	
	# Check if enemy should jump
	if should_jump(patrol_direction):
		perform_jump()
	
	# Simple back and forth patrol
	var distance_from_start = global_position.x - patrol_start_position.x
	
	# Check if we've reached the patrol limits or hit an obstacle/edge
	if distance_from_start >= patrol_range or not can_move_forward and patrol_direction > 0:
		patrol_direction = -1
		if randf() < 0.02:  # Reduced from 0.1 to decrease debug frequency
			print("Enemy turning left - reached limit or obstacle")
	elif distance_from_start <= -patrol_range or not can_move_forward and patrol_direction < 0:
		patrol_direction = 1
		if randf() < 0.02:  # Reduced from 0.1 to decrease debug frequency
			print("Enemy turning right - reached limit or obstacle")
	
	# Move in patrol direction only if we can move forward or if we're jumping
	if can_move_forward or not is_on_floor():
		velocity.x = patrol_direction * move_speed
	else:
		velocity.x = 0
		# Force direction change if stuck and can't jump
		if not should_jump(patrol_direction):
			patrol_direction *= -1
			print("Enemy stuck, forcing direction change")
	
	# Face the direction we're moving
	if sprite:
		sprite.flip_h = patrol_direction > 0
	
	# Debug patrol occasionally
	if randf() < 0.01:  # Reduced from 0.02 to decrease debug frequency
		print("Patrolling - Distance from start: ", distance_from_start, " | Direction: ", patrol_direction, " | Range: ", patrol_range, " | Can move: ", can_move_forward)

func chase_behavior():
	# Move towards the player
	var direction_to_player = (player.global_position - global_position).normalized()
	var _chase_direction = 1 if direction_to_player.x > 0 else -1
	
	# Check if enemy should jump while chasing
	if should_jump(_chase_direction):
		perform_jump()
	
	velocity.x = direction_to_player.x * move_speed * 2.5  # Move much faster when chasing (increased from 1.8)
	
	# Face the direction we're moving
	if sprite:
		sprite.flip_h = direction_to_player.x > 0

func jump_to_player_behavior():
	"""Behavior for jumping up to reach player on higher platform"""
	print("JUMP_TO_PLAYER behavior active!")
	
	# Move towards the player horizontally
	var direction_to_player = (player.global_position - global_position).normalized()
	var _chase_direction = 1 if direction_to_player.x > 0 else -1
	
	# Move horizontally towards player position
	velocity.x = direction_to_player.x * move_speed * 1.5  # Moderate speed while positioning
	
	# Perform the jump if we're close enough horizontally and conditions are right
	if _should_jump_to_player(self) and is_on_floor():
		perform_jump()
		print("Enemy jumping to reach player on platform!")
	
	# Face the direction we're moving
	if sprite:
		sprite.flip_h = direction_to_player.x > 0

func search_alternate_path_behavior():
	"""Behavior for searching alternate path when direct approach fails"""
	print("SEARCH_ALTERNATE_PATH behavior active! Timer: ", alternate_search_timer)
	
	# If we've been searching too long, give up and return to patrol
	if alternate_search_timer >= alternate_search_duration:
		print("Alternate path search timeout - returning to patrol")
		current_state = EnemyState.RETURN_TO_PATROL
		stuck_timer = 0.0
		failed_jump_attempts = 0
		return
	
	# Try moving in the opposite direction from original chase to find alternate route
	var search_direction = -original_chase_direction
	
	# Check if we can move in the search direction
	if can_move_in_direction(search_direction):
		velocity.x = search_direction * move_speed * 1.2  # Move at moderate speed
		print("Searching for alternate path, moving ", "left" if search_direction < 0 else "right")
		
		# Check if we found a way around the obstacle
		if player:
			var distance_to_player = global_position.distance_to(player.global_position)
			var player_direction = 1 if player.global_position.x > global_position.x else -1
			
			# If we can now move toward player or are closer, switch back to chase
			if can_move_in_direction(player_direction) and distance_to_player < last_distance_to_player + 100:
				print("Found alternate path! Switching back to chase")
				current_state = EnemyState.CHASE
				stuck_timer = 0.0
				failed_jump_attempts = 0
				alternate_search_timer = 0.0
				return
	else:
		# If can't move in search direction, try jumping over obstacles
		if should_jump(search_direction):
			perform_jump()
		else:
			# Change search direction
			original_chase_direction *= -1
			print("Blocked in search direction, trying other way")
	
	# Face the direction we're moving
	if sprite:
		sprite.flip_h = search_direction > 0

func attack_behavior():
	# Stop moving and attack
	velocity.x = 0
	
	# Face the player
	if sprite and player:
		var direction_to_player = (player.global_position - global_position).normalized()
		sprite.flip_h = direction_to_player.x > 0
	
	# Attack if cooldown is ready and not already attacking
	if attack_timer <= 0 and not is_attacking:
		perform_attack()
		attack_timer = attack_cooldown

func can_see_player() -> bool:
	"""Check if the enemy can see the player using line of sight detection"""
	if not player:
		return false
	
	var distance_to_player = global_position.distance_to(player.global_position)
	
	# Check if player is within sight range
	if distance_to_player > sight_range:
		return false
	
	# Calculate direction to player
	var direction_to_player = (player.global_position - global_position).normalized()
	
	# Get enemy's facing direction based on sprite flip
	var enemy_facing_direction = Vector2.RIGHT
	if sprite and sprite.flip_h:
		enemy_facing_direction = Vector2.RIGHT  # When flipped, still facing right
	else:
		enemy_facing_direction = Vector2.LEFT   # When not flipped, facing left
	
	# Calculate angle between enemy's facing direction and direction to player
	var angle_to_player = rad_to_deg(enemy_facing_direction.angle_to(direction_to_player))
	angle_to_player = abs(angle_to_player)
	
	# Check if player is within field of view
	if angle_to_player > sight_angle / 2:
		return false
	
	# Perform raycast to check for obstacles
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(
		global_position + Vector2(0, -20),  # Start slightly above enemy center
		player.global_position + Vector2(0, -20)  # End slightly above player center
	)
	
	# Set collision mask to only check for walls/obstacles (not player or enemy)
	query.collision_mask = 1  # Assuming walls are on collision layer 1
	query.exclude = [self]  # Exclude the enemy from the raycast
	
	var result = space_state.intersect_ray(query)
	
	# If no obstacle was hit, the enemy can see the player
	if result.is_empty():
		print("Enemy can see player! Distance: ", distance_to_player, ", Angle: ", angle_to_player)
		return true
	else:
		print("Enemy sight blocked by obstacle: ", result.collider)
		return false

func can_move_in_direction(direction: int) -> bool:
	"""Check if the enemy can move in the given direction (1 for right, -1 for left)"""
	var space_state = get_world_2d().direct_space_state
	var check_distance = wall_detection_distance
	
	# Check for walls ahead
	var wall_check_start = global_position
	var wall_check_end = global_position + Vector2(direction * check_distance, 0)
	
	var wall_query = PhysicsRayQueryParameters2D.create(wall_check_start, wall_check_end)
	wall_query.collision_mask = 1  # Check for walls
	wall_query.exclude = [self]
	
	var wall_result = space_state.intersect_ray(wall_query)
	if not wall_result.is_empty():
		print("Wall detected ahead, cannot move")
		return false
	
	# Check for edges (no ground ahead)
	var edge_check_start = global_position + Vector2(direction * edge_detection_distance, 0)
	var edge_check_end = edge_check_start + Vector2(0, 100)  # Check downward for ground
	
	var edge_query = PhysicsRayQueryParameters2D.create(edge_check_start, edge_check_end)
	edge_query.collision_mask = 1  # Check for ground
	edge_query.exclude = [self]
	
	var edge_result = space_state.intersect_ray(edge_query)
	if edge_result.is_empty():
		print("Edge detected ahead, cannot move")
		return false
	
	return true

func should_jump(direction: int) -> bool:
	"""Check if the enemy should jump over an obstacle or gap"""
	if jump_timer > 0 or not is_on_floor():
		return false
	
	var space_state = get_world_2d().direct_space_state
	
	# Check for obstacles that can be jumped over
	var obstacle_check_start = global_position + Vector2(0, -10)  # Slightly above center
	var obstacle_check_end = global_position + Vector2(direction * wall_detection_distance, -10)
	
	var obstacle_query = PhysicsRayQueryParameters2D.create(obstacle_check_start, obstacle_check_end)
	obstacle_query.collision_mask = 1
	obstacle_query.exclude = [self]
	
	var obstacle_result = space_state.intersect_ray(obstacle_query)
	
	# If there's an obstacle, check if it's jumpable
	if not obstacle_result.is_empty():
		var obstacle_height = global_position.y - obstacle_result.position.y
		if obstacle_height <= jump_threshold_height:
			print("Enemy should jump over obstacle, height: ", obstacle_height)
			return true
	
	# Enhanced: Check if player is above and we should jump to reach them
	if player and (current_state == EnemyState.CHASE or current_state == EnemyState.PATROL):
		var player_pos = player.global_position
		var enemy_pos = global_position
		var horizontal_distance = abs(player_pos.x - enemy_pos.x)
		var vertical_distance = enemy_pos.y - player_pos.y
		
		# With higher jump ability, can reach much higher platforms
		if vertical_distance > 10 and vertical_distance <= 350 and horizontal_distance <= 120:
			print("Enemy should jump to reach player above (HIGH JUMP from should_jump)")
			return true
	
	# Check for gaps that can be jumped
	if can_jump_gaps:
		var gap_check_start = global_position + Vector2(direction * edge_detection_distance, 0)
		var gap_check_end = gap_check_start + Vector2(0, 100)
		
		var gap_query = PhysicsRayQueryParameters2D.create(gap_check_start, gap_check_end)
		gap_query.collision_mask = 1
		gap_query.exclude = [self]
		
		var gap_result = space_state.intersect_ray(gap_query)
		
		# If no ground found, check if gap is small enough to jump
		if gap_result.is_empty():
			# Check for ground further ahead to see gap width
			var far_check_start = global_position + Vector2(direction * max_jump_gap_width, 0)
			var far_check_end = far_check_start + Vector2(0, 100)
			
			var far_query = PhysicsRayQueryParameters2D.create(far_check_start, far_check_end)
			far_query.collision_mask = 1
			far_query.exclude = [self]
			
			var far_result = space_state.intersect_ray(far_query)
			
			# If there's ground within jump distance, attempt the jump
			if not far_result.is_empty():
				print("Enemy should jump over gap")
				return true
	
	return false

func perform_jump():
	"""Make the enemy jump"""
	if is_on_floor() and jump_timer <= 0:
		velocity.y = jump_velocity
		jump_timer = jump_cooldown
		print("Enemy jumping HIGH! Velocity: ", velocity.y, " (should reach approximately twice player height)")
		
		# Optional: Add some horizontal momentum if moving
		if abs(velocity.x) > 50:
			# Preserve horizontal momentum during jump
			print("Jump with horizontal momentum: ", velocity.x)

func return_to_patrol_behavior():
	# Move back towards patrol start position
	var direction_to_start = (patrol_start_position - global_position).normalized()
	var return_direction = 1 if direction_to_start.x > 0 else -1
	
	# Check if enemy should jump while returning
	if should_jump(return_direction):
		perform_jump()
	
	velocity.x = direction_to_start.x * move_speed
	
	# Face the direction we're moving
	if sprite:
		sprite.flip_h = direction_to_start.x > 0

func perform_attack():
	print("Enemy attacking!")
	is_attacking = true  # Set flag to prevent multiple simultaneous attacks
	
	# Play attack animation if available
	#if animation_player.has_animation("attack"):
	#	animation_player.play("attack")
	
	# Create a temporary hitbox for the attack
	create_attack_hitbox()
	
	# Reset attack flag after a short delay to allow for next attack
	var reset_timer = Timer.new()
	reset_timer.wait_time = 0.5  # Half second before allowing next attack
	reset_timer.one_shot = true
	reset_timer.timeout.connect(_on_attack_reset)
	add_child(reset_timer)
	reset_timer.start()
	
	# Check if player is still in range and deal damage (fallback if hitbox system fails)
	if player and global_position.distance_to(player.global_position) <= attack_range:
		# This is a fallback - the hitbox system should handle damage normally
		print("Player in attack range - hitbox should handle damage")

func _on_attack_reset():
	is_attacking = false
	print("Attack flag reset - ready for next attack")

func create_attack_hitbox():
	# Check if there's already an active attack hitbox
	var existing_hitbox = get_node_or_null("AttackHitbox")
	attack_range = 40
	
	if existing_hitbox:
		print("Attack hitbox already exists, skipping creation")
		return
	
	# Create a temporary hitbox for this attack
	var hitbox_area = Area2D.new()
	var hitbox_collision = CollisionShape2D.new()
	var hitbox_shape = RectangleShape2D.new()
	
	# Name the hitbox for identification
	hitbox_area.name = "AttackHitbox"
	
	# Name the collision shape so the hitbox script can find it
	hitbox_collision.name = "CollisionShape2D"
	
	# Set up the collision shape first
	hitbox_shape.size = Vector2(attack_range, 40)  # Width = attack range, height = 40
	hitbox_collision.shape = hitbox_shape
	
	# Position the hitbox in front of the enemy
	var hitbox_offset = Vector2(attack_range * 0.5, 0)
	if sprite and sprite.flip_h:
		hitbox_offset.x = -hitbox_offset.x
	
	hitbox_collision.position = hitbox_offset
	
	# Add collision to hitbox area first
	hitbox_area.add_child(hitbox_collision)
	
	# Set collision layers properly for hitboxes
	hitbox_area.collision_layer = 4  # Layer 4 for hitboxes
	hitbox_area.collision_mask = 0   # Don't detect anything
	
	# Try to load the hitbox script
	var hitbox_script = load("res://scripts/hit_hurt_boxes/hitbox.gd")
	if hitbox_script:
		hitbox_area.set_script(hitbox_script)
		
		# Set up the hitbox properties after the script is set
		hitbox_area.damage = attack_damage
		hitbox_area.knockback_multiplier = attack_knockback_force
		
		print("Enemy attack hitbox created - damage set to: ", attack_damage, " (should be 1)")
		print("Hitbox damage property: ", hitbox_area.damage)
	else:
		print("Warning: Could not load hitbox script, using basic Area2D")
	
	# Add hitbox to the scene tree
	add_child(hitbox_area)
	
	print("Created attack hitbox at offset: ", hitbox_offset, " with size: ", hitbox_shape.size)
	
	# Remove the hitbox after a short duration
	var timer = Timer.new()
	timer.wait_time = 0.3  # Hitbox active for 0.3 seconds (slightly longer for better hit detection)
	timer.one_shot = true
	timer.timeout.connect(_on_attack_hitbox_timeout.bind(hitbox_area))
	add_child(timer)
	timer.start()

func _on_attack_hitbox_timeout(hitbox_area: Area2D):
	if hitbox_area and is_instance_valid(hitbox_area):
		hitbox_area.queue_free()

# Damage system (called by HurtBox)
func take_damage(damage_amount: int) -> void:
	# Check for spawn invincibility
	if is_spawn_invincible:
		print("Enemy spawn invincibility active - damage ignored! Time remaining: ", spawn_invincibility_timer)
		return
	
	print("=== ENEMY TAKING DAMAGE ===")
	print("Damage amount: ", damage_amount)
	print("Health before: ", current_health, "/", max_health)
	print("Time since _ready(): ", Time.get_time_dict_from_system())
	print("Call stack: ")
	var stack = get_stack()
	for i in range(min(3, stack.size())):  # Show top 3 stack frames
		print("  ", stack[i])
	
	current_health = max(0, current_health - damage_amount)
	animation_player.play("hurt")
	print("Health after: ", current_health, "/", max_health)
	print("=== END DAMAGE LOG ===")
	
	if current_health <= 0:
		die()

func die():
	print("Enemy defeated!")
	# Record earliest kill into the combat registry with PlayerManager's global time
	var pm = get_tree().get_first_node_in_group("player_manager")
	var registry = get_tree().get_first_node_in_group("combat_registry")
	if pm and registry and registry.has_method("record_kill"):
		registry.record_kill(self, pm.global_time)
	# You can add death effects here (particles, sound, etc.)
	queue_free()

# Apply knockback when hit
func apply_knockback(knockback_vector: Vector2):
	# Interrupt attack if currently attacking
	if current_state == EnemyState.ATTACK:
		current_state = EnemyState.CHASE
		attack_timer = attack_cooldown * 0.5  # Reduced cooldown after being hit
	
	# Apply knockback with resistance factor
	var actual_knockback = knockback_vector * knockback_resistance
	
	# Clamp to maximum knockback velocity
	if actual_knockback.length() > max_knockback_velocity:
		actual_knockback = actual_knockback.normalized() * max_knockback_velocity
	
	velocity += actual_knockback

# Utility functions for enemy AI
func get_distance_to_player() -> float:
	if player:
		return global_position.distance_to(player.global_position)
	return INF

func is_player_in_range(range_distance: float) -> bool:
	return get_distance_to_player() <= range_distance

func get_current_state_name() -> String:
	match current_state:
		EnemyState.PATROL:
			return "PATROL"
		EnemyState.CHASE:
			return "CHASE"
		EnemyState.ATTACK:
			return "ATTACK"
		EnemyState.RETURN_TO_PATROL:
			return "RETURN_TO_PATROL"
		EnemyState.SEARCH_ALTERNATE_PATH:
			return "SEARCH_ALTERNATE_PATH"
		_:
			return "UNKNOWN"

# Method to manually set enemy state (useful for debugging or special events)
func set_enemy_state(new_state: EnemyState):
	current_state = new_state
	match new_state:
		EnemyState.ATTACK:
			attack_timer = 0  # Reset attack timer when forced into attack state
		EnemyState.PATROL:
			# Reset patrol direction based on position relative to start
			var distance_from_start = global_position.x - patrol_start_position.x
			patrol_direction = 1 if distance_from_start < 0 else -1

# Utility methods for passive body damage
func is_passive_damage_enabled() -> bool:
	"""Check if passive body damage is currently enabled"""
	return passive_body_damage_enabled

func get_passive_damage_amount() -> int:
	"""Get the amount of damage dealt by touching enemy body"""
	return passive_body_damage

func set_passive_damage_amount(damage: int):
	"""Set the passive body damage amount"""
	passive_body_damage = damage
	var body_hitbox = get_node_or_null("BodyHitBox")
	if body_hitbox:
		body_hitbox.damage = damage
		print("Enemy passive body damage set to: ", damage)
