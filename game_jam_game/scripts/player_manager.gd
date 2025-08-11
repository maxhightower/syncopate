extends Node2D
class_name PlayerManager

# Emitted when the active track index changes (0-3)
signal track_changed(track_index: int)

# The Player scene to instance per track
@export var track_scene: PackedScene
@export var track_count: int = 4

# Colors for each track (1: red, 2: yellow, 3: blue, 4: green)
var track_colors: Array[Color] = [
		Color(1, 0, 0), # Track 1 - red
		Color(1, 1, 0), # Track 2 - yellow
		Color(0, 0, 1), # Track 3 - blue
		Color(0, 1, 0)  # Track 4 - green
]

# Reference to the UI (can be set in editor or found at runtime)
@export var cassette_ui: CassetteButtonlessUI
@export var pause_menu_scene: PackedScene
var _pause_menu: Node


# Holds the instantiated Player tracks
var tracks: Array[Player] = []

# The spawn point for all players
@export var spawn_point: Vector2 = Vector2.ZERO

# Index of the currently active track
var active_track_idx: int = -1

# Reference to the camera
@onready var main_camera: Camera2D = $Camera2D

# Global time tracking (shared across tracks) that can rewind when Q is held
var global_time: float = 0.0
var _is_rewinding_time: bool = false

# Timeline settings
const TAPE_LENGTH: float = 15.0
var _pending_switch_idx: int = -1
var _phase_offsets: Array[float] = []

func _ready() -> void:
	# Instantiate and set up each track
	# Allow other nodes to find this manager
	add_to_group("player_manager")

	# Ensure a combat registry exists in the scene
	if not get_tree().get_first_node_in_group("combat_registry"):
		var reg_script = load("res://scripts/level_architecture/combat_registry.gd")
		if reg_script:
			var registry = reg_script.new()
			add_child(registry)

	# Ensure a pause menu exists
	if not pause_menu_scene:
		# Try to find an existing PauseMenu node in the scene
		var existing := get_tree().get_first_node_in_group("pause_menu")
		if existing:
			_pause_menu = existing
	else:
		_pause_menu = pause_menu_scene.instantiate()
		if _pause_menu:
			# Allow lookup while paused
			_pause_menu.add_to_group("pause_menu")
			get_tree().current_scene.add_child(_pause_menu)
	for i in range(track_count):
		var player = track_scene.instantiate() as Player
		player.name = "Track%d" % i
		# Position all players at the spawn point
		player.position = spawn_point
		# Tint the player based on its track color
		player.modulate = track_colors[i % track_colors.size()]
		add_child(player)
		# Listen for when the player's ring buffer starts looping
		player.connect("loop_started", Callable(self, "_on_loop_started").bind(i))
		tracks.append(player)
		# Disable input on all until we activate one
		player.set_process_input(false)

		# Start all players hidden until their track is activated
		player.visible = false

		# Disable individual player cameras since we'll use the main camera
		if player.has_node("Camera2D"):
			player.get_node("Camera2D").enabled = false

		# Initialize phase offsets as unset (-1); will be set when first activated
		_phase_offsets.append(-1.0)

	# Activate the first track by default
	activate_track(0)

	# Find and connect to the UI
	_find_and_connect_ui()

# Intercept unhandled input and forward only to the active track
#func _unhandled_input(event: InputEvent) -> void:
#	tracks[active_track_idx]._unhandled_input(event)


func _unhandled_input(event: InputEvent) -> void:
	# Speed controls, pause, and rewind
	if event is InputEventKey and not event.echo:
		if event.pressed:
			# ESC toggles pause menu
			if event.keycode == KEY_ESCAPE:
				if _pause_menu:
					_pause_menu.toggle()
				return
			# Slow down
			if event.keycode == KEY_Z:
				Engine.time_scale = max(0.1, Engine.time_scale - 0.5)
				print("[PlayerManager] Slowed time_scale to ", Engine.time_scale)
				if cassette_ui:
					cassette_ui.update_speed_modifier_label()
				return
			# Speed up
			elif event.keycode == KEY_C:
				if Engine.time_scale == 0.1:
					Engine.time_scale = 0.5
				elif Engine.time_scale == 2.5:
					pass
				else:
					Engine.time_scale = Engine.time_scale + 0.5
				print("[PlayerManager] Sped up time_scale to ", Engine.time_scale)
				if cassette_ui:
					cassette_ui.update_speed_modifier_label()
				return
			# Start rewind
			elif event.keycode == KEY_Q:
				for p in tracks:
					if p and p.has_method("start_rewind"):
						p.start_rewind()
				_is_rewinding_time = true
				if cassette_ui and cassette_ui.has_method("start_rewind_timer"):
					cassette_ui.start_rewind_timer()
				return
		else:
			# Key released
			if event.keycode == KEY_Q:
				for i in range(tracks.size()):
					var p = tracks[i]
					if p and p.has_method("stop_rewind"):
						if i == active_track_idx:
							p.stop_rewind(true)
						else:
							p.stop_rewind(false)
				_stop_time_rewind()
				return

	# Switching actions (next-tick commit)
	if event.is_action_pressed("switch_next"):
		_request_switch_to((active_track_idx + 1) % tracks.size())
		event.consume()
		return
	elif event.is_action_pressed("switch_prev"):
		_request_switch_to((active_track_idx - 1 + tracks.size()) % tracks.size())
		event.consume()
		return
	elif event.is_action_pressed("switch_1"):
		_request_switch_to(0)
		event.consume()
		return
	elif event.is_action_pressed("switch_2"):
		_request_switch_to(1)
		event.consume()
		return
	elif event.is_action_pressed("switch_3"):
		_request_switch_to(2)
		event.consume()
		return
	elif event.is_action_pressed("switch_4"):
		_request_switch_to(3)
		event.consume()
		return

	# Forward to the active track
	if active_track_idx >= 0 and active_track_idx < tracks.size():
		tracks[active_track_idx]._unhandled_input(event)

func _request_switch_to(new_idx: int) -> void:
	if new_idx < 0 or new_idx >= tracks.size():
		return
	if new_idx == active_track_idx:
		return
	_pending_switch_idx = new_idx


# Called when a track's ring buffer becomes full and starts replaying
func _on_loop_started(looping_track_idx: int) -> void:
	# Only switch if it's from the active track
	if looping_track_idx != active_track_idx:
		return
	# Compute next track index (wraps around)
	var next_idx = (active_track_idx + 1) % tracks.size()
	# Switch control to the next track while keeping previous tracks visible
	activate_track(next_idx)

# 
# Enable input on the chosen track, disable on the others
func activate_track(idx: int) -> void:
	# Check if we're already on this track to prevent unnecessary work
	if active_track_idx == idx:
		return

	Engine.time_scale = 1.0
	if cassette_ui:
		cassette_ui.update_speed_modifier_label()

	# Move the new active player to the spawn point
	if idx >= 0 and idx < tracks.size():
		tracks[idx].global_position = spawn_point
		# Start a fresh 15s take for the newly active track to avoid stale tape state
		if tracks[idx].has_method("begin_live_take"):
			tracks[idx].begin_live_take()
		# Set immutable phase on first activation
		if _phase_offsets[idx] < 0.0:
			_phase_offsets[idx] = fmod(global_time, TAPE_LENGTH)

	for i in range(tracks.size()):
		var is_active := i == idx
		tracks[i].set_process_input(is_active)
		# Only active puppet runs physics/_process; ghosts are sampled externally
		tracks[i].set_physics_process(is_active)
		tracks[i].set_process(is_active)
		tracks[i].visible = i <= idx  # keep current and prior tracks visible

		# Handle ghost mode transitions: force all non-actives to ghost, only active is live
		if tracks[i].has_method("set_ghost_mode"):
			# Non-active tracks are echo ghosts (not controllable)
			tracks[i].set_ghost_mode(i != idx, false)
			if i != idx:
				print("[PlayerManager] Track ", i, " ghosted; active is ", idx)

	active_track_idx = idx

	# Notify listeners (like the UI) that the active track changed
	track_changed.emit(idx)

	# Restart enemy loop when tracks switch
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e and e.has_method("restart_loop"):
			e.restart_loop()
		elif e and e.has_method("begin_live_take"):
			e.begin_live_take()

	# Move the main camera to follow the active player
	if main_camera and idx < tracks.size():
		var active_player = tracks[idx]
		# Use a tween for smooth camera transition
		var tween = create_tween()
		tween.tween_property(main_camera, "global_position", active_player.global_position, 0.3)
		tween.tween_callback(_update_camera_follow)

	print("[PlayerManager] Switched to track %d" % idx)

	# Update the UI to show the correct track button state (visual-only to avoid loops)
	if cassette_ui:
		var expected_ui_track = idx + 1  # Convert to UI numbering (1-4)
		if cassette_ui.has_method("update_track_display_only"):
			cassette_ui.update_track_display_only(expected_ui_track)
			# Ensure UI reconnects health listener to the new active player
			if cassette_ui.has_method("_connect_to_active_player"):
				cassette_ui._connect_to_active_player()
		else:
			if cassette_ui.has_method("get_current_track"):
				var ui_track = cassette_ui.get_current_track()
				if ui_track != expected_ui_track:
					cassette_ui.current_track = expected_ui_track
					cassette_ui._update_timer_display()
					cassette_ui._update_progress_bar()

	# Commit happens immediately here (called from next tick)

# Find and connect to the UI
func _find_and_connect_ui() -> void:
	# Try to find the UI in the scene tree
	var ui_node = get_node_or_null("../UI/CassetteButtonlessUI")
	if not ui_node:
		ui_node = get_node_or_null("UI/CassetteButtonlessUI") 
	if not ui_node:
		# Search the entire scene tree for the UI
		ui_node = _search_for_ui(get_tree().current_scene)
	
	if ui_node:
		cassette_ui = ui_node
		print("[PlayerManager] Found UI: ", cassette_ui.name)
		
		# Connect to UI track switching signals if they exist
		if cassette_ui.has_signal("track_changed"):
			cassette_ui.connect("track_changed", Callable(self, "_on_ui_track_changed"))
		
		# Connect to track timer finished signal to handle ghost mode restoration
		if cassette_ui.has_signal("track_timer_finished"):
			cassette_ui.connect("track_timer_finished", Callable(self, "_on_track_timer_finished"))
		
		# Connect to cassette events following the requested pattern
		if cassette_ui.has_signal("cassette_event"):
			cassette_ui.connect("cassette_event", Callable(self, "_on_cassette_event"))
		
		# Override the UI's track switching to also switch player visibility
		_setup_ui_track_switching()
	else:
		print("[PlayerManager] Warning: Could not find CassetteButtonlessUI")

func _search_for_ui(node: Node) -> Node:
	if node.name == "CassetteButtonlessUI":
		return node
	
	for child in node.get_children():
		var result = _search_for_ui(child)
		if result:
			return result
	return null

# Set up UI track switching to also switch players
func _setup_ui_track_switching() -> void:
	if not cassette_ui:
		return
	
	# Override the UI's input handling to also switch player tracks
	if cassette_ui.has_method("_input"):
		# We'll connect to key presses directly since the UI already handles them
		pass

# Handle UI track changes
func _on_ui_track_changed(track_number: int) -> void:
	# Convert from UI track numbering (1-4) to our array indexing (0-3)
	var player_idx = track_number - 1
	if player_idx >= 0 and player_idx < tracks.size():
		_request_switch_to(player_idx)

# Handle track timer finished events - used for ghost mode restoration
func _on_track_timer_finished(track_number: int) -> void:
	print("[PlayerManager] Track ", track_number, " timer finished!")
	
	# When track 1 timer finishes, the system will auto-progress to track 2
	# This is handled by the cassette UI, but we can add any special logic here
	# The activate_track function will automatically restore players from ghost mode
	if track_number == 1:
		print("[PlayerManager] Track 1 finished - any ghost players will be restored when switching to track 2")

func reset_all_players() -> void:
		for p in tracks:
				if p and p.has_method("reset_to_spawn"):
						p.reset_to_spawn()
		activate_track(0)

# Handle cassette events following the requested pattern
func _on_cassette_event(event_type: String) -> void:
	print("[PlayerManager] Received cassette event: ", event_type)
	
	# Handle different cassette events
	match event_type:
		"play":
			# Start/resume playback
			_handle_play_event()
		"stop":
			_handle_stop_event()
		"pause":
			_handle_pause_event()
		"rewind":
			_handle_rewind_event()
		"fast_forward":
			_handle_fast_forward_event()
		"damage":
			# Handle damage event - make UI lose a heart
			_handle_damage_event()
		_:
			print("[PlayerManager] Unknown cassette event: ", event_type)

func _handle_play_event():
	print("[PlayerManager] Handling play event")
	# Add play logic here

func _handle_stop_event():
	print("[PlayerManager] Handling stop event")
	# Add stop logic here

func _handle_pause_event():
	print("[PlayerManager] Handling pause event")
	# Add pause logic here

func _handle_rewind_event():
	print("[PlayerManager] Handling rewind event")
	# Add rewind logic here

func _handle_fast_forward_event():
	print("[PlayerManager] Handling fast forward event")
	# Add fast forward logic here

func _handle_damage_event():
	print("[PlayerManager] Handling damage event - player took damage")
	# Make the UI lose a heart following the requested pattern
	if cassette_ui and cassette_ui.has_method("lose_heart"):
		cassette_ui.lose_heart()
	else:
		print("[PlayerManager] Warning: UI doesn't have lose_heart method")



# Public method to get the active track
func get_active_track_index() -> int:
	return active_track_idx

# Public method to get the active player
func get_active_player() -> Player:
	if active_track_idx < tracks.size():
		return tracks[active_track_idx]
	return null

# Update camera to follow the active player continuously
func _update_camera_follow() -> void:
	if main_camera and active_track_idx < tracks.size():
		main_camera.global_position = tracks[active_track_idx].global_position

# Process function to keep camera following the active player
func _process(_delta: float) -> void:
	# Update global time (rewind while Q is held)
	var delta = _delta
	if _is_rewinding_time:
		global_time = max(0.0, global_time - delta)
	else:
		global_time += delta

	# Propagate global time to all players so their internal timers/buffers sync
	for p in tracks:
		if p and p.has_method("set_total_time"):
			p.set_total_time(global_time)

	# Next-tick switch commit: if a switch was requested, check lockouts and apply
	if _pending_switch_idx >= 0:
		var can_switch := true
		if active_track_idx >= 0 and active_track_idx < tracks.size():
			var current = tracks[active_track_idx]
			if current and current.has_method("can_switch_tracks"):
				can_switch = current.can_switch_tracks()
		if can_switch:
			activate_track(_pending_switch_idx)
			_pending_switch_idx = -1
		# else keep pending until allowed; UI should already be highlighting selection

	# Drive ghost playback for all non-active tracks using fixed 15s phases
	for i in range(tracks.size()):
		if i == active_track_idx:
			continue
		var ghost = tracks[i]
		if ghost and ghost.is_in_ghost_mode() and ghost.has_method("ghost_playback_at"):
			var phase_start := _phase_offsets[i]
			# Compute local time within this tape's phase-aligned 15s window
			var local := fmod(max(0.0, global_time - phase_start), TAPE_LENGTH)
			ghost.ghost_playback_at(local)

	_update_camera_follow()

# Allow player to signal the manager to stop time rewind
func _stop_time_rewind():
	_is_rewinding_time = false
	if cassette_ui and cassette_ui.has_method("stop_rewind_timer"):
		cassette_ui.stop_rewind_timer()

# Public method to trigger damage events following the requested pattern
func take_damage():
	"""Called when the player takes damage - emits damage signal to UI"""
	if cassette_ui:
		cassette_ui.trigger_cassette_action("damage")
	else:
		print("[PlayerManager] Warning: No UI reference for damage event")

# Public method to trigger other cassette events
func trigger_cassette_event(event_type: String):
	"""Public method to trigger any cassette event"""
	if cassette_ui:
		cassette_ui.trigger_cassette_action(event_type)
	else:
		print("[PlayerManager] Warning: No UI reference for event: ", event_type)
