extends Node2D
class_name PlayerManager

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


# Holds the instantiated Player tracks
var tracks: Array[Player] = []

# The spawn point for all players
@export var spawn_point: Vector2 = Vector2.ZERO

# Index of the currently active track
var active_track_idx: int = -1

# Reference to the camera
@onready var main_camera: Camera2D = $Camera2D

func _ready() -> void:
	# Instantiate and set up each track
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

	# Activate the first track by default
	activate_track(0)

	# Find and connect to the UI
	_find_and_connect_ui()

# Intercept unhandled input and forward only to the active track
#func _unhandled_input(event: InputEvent) -> void:
#	tracks[active_track_idx]._unhandled_input(event)


func _unhandled_input(event: InputEvent) -> void:
	# Speed up/slow down tick rate with C and Z (Godot 4.x compatible)
		if event is InputEventKey and not event.echo:
			if event.pressed:
				if event.keycode == KEY_Z:
						Engine.time_scale = max(0.1, Engine.time_scale - 0.5)
						print("[PlayerManager] Slowed time_scale to ", Engine.time_scale)
						if cassette_ui:
								cassette_ui.update_speed_modifier_label()
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
				elif event.keycode == KEY_Q:
					# start the rewind
					if active_track_idx >= 0 and active_track_idx < tracks.size():
						var player = tracks[active_track_idx]
						if player.has_method("start_rewind"):
							player.start_rewind()
				elif event.keycode == KEY_E:
					# start fast forward
					if active_track_idx >= 0 and active_track_idx < tracks.size():
						var player = tracks[active_track_idx]
						if player.has_method("stop_fast_forward"):
							player.stop_fast_forward()
			else:
				# Key released
				if event.keycode == KEY_Q:
					if active_track_idx >= 0 and active_track_idx < tracks.size():
						var player = tracks[active_track_idx]
						if player.has_method("stop_rewind"):
							player.stop_rewind()
				elif event.keycode == KEY_E:
					if active_track_idx >= 0 and active_track_idx < tracks.size():
						var player = tracks[active_track_idx]
						if player.has_method("stop_fast_forward"):
							player.stop_fast_forward()
		# Forward input to active track
		if active_track_idx >= 0 and active_track_idx < tracks.size():
				tracks[active_track_idx]._unhandled_input(event)


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

	for i in range(tracks.size()):
		var is_active := i == idx
		tracks[i].set_process_input(is_active)
		tracks[i].visible = i <= idx  # keep current and prior tracks visible

		# Handle ghost mode transitions
		if tracks[i].has_method("set_ghost_mode"):
			tracks[i].set_ghost_mode(i < idx)

	active_track_idx = idx

	# Move the main camera to follow the active player
	if main_camera and idx < tracks.size():
		var active_player = tracks[idx]
		# Use a tween for smooth camera transition
		var tween = create_tween()
		tween.tween_property(main_camera, "global_position", active_player.global_position, 0.3)
		tween.tween_callback(_update_camera_follow)

	print("[PlayerManager] Switched to track %d" % idx)

	# Update the UI to show the correct track button state (but don't call switch_to_track to avoid loops)
	if cassette_ui and cassette_ui.has_method("get_current_track"):
		var ui_track = cassette_ui.get_current_track()
		var expected_ui_track = idx + 1  # Convert to UI numbering (1-4)
		if ui_track != expected_ui_track:
			# Only update UI if it's out of sync
			cassette_ui.current_track = expected_ui_track
			cassette_ui._update_timer_display()
			cassette_ui._update_progress_bar()

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
		activate_track(player_idx)

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
	_update_camera_follow()

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
