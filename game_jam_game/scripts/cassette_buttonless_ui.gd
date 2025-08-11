class_name CassetteButtonlessUI
extends Control

# Button References
@onready var background: Sprite2D = $Background
@onready var red_button: Sprite2D = $RedButton
@onready var yellow_button: Sprite2D = $YellowButton
@onready var blue_button: Sprite2D = $BlueButton
@onready var green_button: Sprite2D = $GreenButton

# UI References
@onready var timer_label: Label = $TimerContainer/VBoxContainer/TimerLabel
@onready var timer_progress_bar: ProgressBar = $ProgressBar
@onready var speed_modifier_label: Label = $SpeedModifierContainer/SpeedModifierLabel

# Hearts References
@onready var hearts_container: HBoxContainer = $HeartsContainer
@onready var heart1: Sprite2D = $HeartsContainer/Container/Heart1
@onready var heart2: Sprite2D = $HeartsContainer/Container2/Heart2
@onready var heart3: Sprite2D = $HeartsContainer/Container3/Heart3

# Audio Reference
@onready var button_click_audio: AudioStreamPlayer2D = $AudioStreamPlayer2D

# Player reference
var player: Node = null

# Player manager reference  
var player_manager: Node = null
var active_track: int = 1

# UI state
var ui_visible: bool = true
var slide_tween: Tween
var original_position: Vector2
var hidden_position: Vector2

# Button animation
var button_tweens: Array[Tween] = []
var button_original_positions: Array[Vector2] = []
var button_pressed_offset: float = 50.0  # How much buttons move down when pressed
var red_button_drop_offset: float = 50.0  # How far red button drops when key 1 is pressed

# Button state variables
var red_button_dropped: bool = false
var yellow_button_dropped: bool = false
var blue_button_dropped: bool = false
var green_button_dropped: bool = false

# Button original positions
var red_button_original_position: Vector2
var yellow_button_original_position: Vector2
var blue_button_original_position: Vector2
var green_button_original_position: Vector2

# Animation settings
const SLIDE_DURATION: float = 0.3
const SLIDE_EASE_TYPE = Tween.EASE_OUT
const SLIDE_TRANS_TYPE = Tween.TRANS_BACK
const BUTTON_ANIM_DURATION: float = 0.3

# Timer variables
var countdown_time: float = 15.0  # 15 seconds
var is_timer_running: bool = false
var is_timer_rewinding: bool = false

# Multi-track timer system
var timer_per_track: Dictionary = {}  # Stores time remaining for each track
var current_track: int = 1  # Currently active track (1-4)
var default_track_time: float = 15.0  # Default time for new tracks (15 seconds)

# Health system
var health_per_track: Dictionary = {}
var max_health: int = 3
var hearts: Array[Sprite2D] = []

signal ui_toggled(visible: bool)
signal timer_finished()
signal track_timer_finished(track_number: int)
signal health_changed(new_health: int)
signal track_changed(track_number: int)
signal cassette_event(event_type: String)

# Function to emit cassette events following the requested pattern
func trigger_cassette_action(action: String):
	cassette_event.emit(action)
	print("CassetteButtonlessUI: Triggered cassette event - ", action)

func _initialize_hearts():
		"""Initialize the hearts display system"""
		hearts = [heart1, heart2, heart3]
		if not health_per_track.has(current_track):
				health_per_track[current_track] = max_health
		_update_hearts_display()
		print("Hearts system initialized with ", max_health, " hearts")

func _update_hearts_display():
		"""Update the visual display of hearts based on current health"""
		var current_health = health_per_track.get(current_track, max_health)
		for i in range(hearts.size()):
				if hearts[i]:
						if i < current_health:
								# Full heart - normal appearance
								hearts[i].modulate = Color(1, 1, 1, 1)  # Full opacity, normal color
								hearts[i].visible = true
						else:
								# Empty heart - dimmed/hidden
								hearts[i].modulate = Color(0.3, 0.3, 0.3, 0.5)  # Dark and translucent
								hearts[i].visible = true

func take_damage(amount: int = 1):
		"""Player takes damage, reducing health"""
		var current_health = health_per_track.get(current_track, max_health)
		if current_health > 0:
				current_health = max(0, current_health - amount)
				health_per_track[current_track] = current_health
				_update_hearts_display()
				health_changed.emit(current_health)
				print("Player took ", amount, " damage. Health: ", current_health, "/", max_health)

				if current_health <= 0:
						print("Player died!")

func get_health() -> int:
		"""Get current player health"""
		return health_per_track.get(current_track, max_health)

func update_hearts(new_health: int) -> void:
		"""Update hearts display from external health system (called by player)"""
		health_per_track[current_track] = clamp(new_health, 0, max_health)
		_update_hearts_display()
		health_changed.emit(health_per_track[current_track])
		print("UI: Hearts updated to ", health_per_track[current_track], "/", max_health)

func get_max_health() -> int:
	"""Get maximum player health"""
	return max_health

func is_alive() -> bool:
				"""Check if player is still alive"""
				return health_per_track.get(current_track, max_health) > 0

func update_speed_modifier_label() -> void:
		speed_modifier_label.text = "%0.1fx" % Engine.time_scale

func _ready():
	# Store original positions for animation
	original_position = position
	hidden_position = Vector2(original_position.x, get_viewport().get_visible_rect().size.y + 50)
	
	# Wait for nodes to be ready
	await get_tree().process_frame
	
	# Store button original positions
	_store_button_positions()
	
	# Store red button's original position specifically
	if red_button:
		red_button_original_position = red_button.position
	if yellow_button:
		yellow_button_original_position = yellow_button.position
	if blue_button:
		blue_button_original_position = blue_button.position
	if green_button:
		green_button_original_position = green_button.position
	
	# Start hidden
	position = hidden_position
	visible = true  # Keep visible for animations, but positioned off-screen
	ui_visible = true
	
	# Find player
	_find_player()
	
	# Find player manager
	_find_player_manager()
	
	# Initialize progress bar settings
	if timer_progress_bar:
		timer_progress_bar.max_value = 100.0
		timer_progress_bar.min_value = 0.0
		timer_progress_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END
		timer_progress_bar.value = 0.0  # Start at 0 (no progress yet)
		print("Progress bar initialized: max=", timer_progress_bar.max_value, ", min=", timer_progress_bar.min_value)
	
		# Initialize track timers
		_initialize_timer_per_track()
		# Start the timer immediately so track 1 begins counting down
		start_timer()

		# Initialize health dictionaries
		_initialize_health_per_track()

		# Initialize hearts system
		_initialize_hearts()
	
	# Start the countdown timer for track 1
	current_track = 0
	switch_to_track(1)
	
	# Drop red button by default when game starts
	_drop_red_button()
	update_speed_modifier_label()

func _store_button_positions():
	button_original_positions.clear()
	var buttons = [red_button, yellow_button, blue_button, green_button]
	for button in buttons:
		if button:
			button_original_positions.append(button.position)

func _input(event):
	# Handle UI toggle
	if event.is_action_pressed("toggle_cassette_ui") or (event is InputEventKey and event.pressed and event.keycode == KEY_TAB):
		toggle_visibility()
		#print("UI toggled, visible: ", ui_visible)
	
	# Handle button animations when UI is visible
	#if not ui_visible:
		#if event is InputEventKey and event.pressed and event.keycode == KEY_1:
	#		print("Key 1 pressed but UI is not visible (visible: ", ui_visible, ")")
	#	return
		
	if event is InputEventKey and event.pressed:
		var key_code = event.keycode
		#print("Input received, key: ", key_code, ", UI visible: ", ui_visible)
		match key_code:
			KEY_1:
				#print("Key 1 pressed - Switching to track 1 (Red)")
				if button_click_audio:
					button_click_audio.play()
				switch_to_track(1)
				_set_only_button_dropped("red")
			KEY_2:
				#print("Key 2 pressed - Switching to track 2 (Yellow)")
				if button_click_audio:
					button_click_audio.play()
				switch_to_track(2)
				_set_only_button_dropped("yellow")
			KEY_3:
				#print("Key 3 pressed - Switching to track 3 (Blue)")
				if button_click_audio:
					button_click_audio.play()
				switch_to_track(3)
				_set_only_button_dropped("blue")
			KEY_4:
				#print("Key 4 pressed - Switching to track 4 (Green)")
				if button_click_audio:
					button_click_audio.play()
				switch_to_track(4)
				_set_only_button_dropped("green")


func _animate_button_press(button_index: int):
	var buttons = [red_button, yellow_button, blue_button, green_button]
	if button_index < 0 or button_index >= buttons.size():
		return
		
	var button = buttons[button_index]
	if not button:
		return
	
	# Don't animate red button with normal press if it's already dropped
	if button == red_button and red_button_dropped:
		return
	
	# Stop any existing tween for this button
	if button_index < button_tweens.size() and button_tweens[button_index]:
		button_tweens[button_index].kill()
	
	# Ensure we have enough tween slots
	while button_tweens.size() <= button_index:
		button_tweens.append(null)
	
	# Create new tween
	button_tweens[button_index] = create_tween()
	var tween = button_tweens[button_index]
	
	# Get original position
	var original_pos = button_original_positions[button_index]
	var pressed_pos = Vector2(original_pos.x, original_pos.y + button_pressed_offset)
	
	# Animate button press (down then back up)
	tween.tween_property(button, "position", pressed_pos, BUTTON_ANIM_DURATION)
	tween.tween_property(button, "position", original_pos, BUTTON_ANIM_DURATION)

func _drop_red_button():
	"""Drop the red button 200 pixels down"""
	print("_drop_red_button called, red_button exists: ", red_button != null, ", already dropped: ", red_button_dropped)
	if not red_button or red_button_dropped:
		return
	
	print("Dropping red button from position: ", red_button.position, " to: ", Vector2(red_button_original_position.x, red_button_original_position.y + red_button_drop_offset))
	red_button_dropped = true
	var target_position = Vector2(red_button_original_position.x, red_button_original_position.y + red_button_drop_offset)
	
	# Create smooth drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(red_button, "position", target_position, BUTTON_ANIM_DURATION * 2)

func _return_red_button():
	"""Return the red button to its original position"""
	if not red_button or not red_button_dropped:
		return
	
	red_button_dropped = false
	
	# Create smooth return animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(red_button, "position", red_button_original_position, BUTTON_ANIM_DURATION)

func _drop_yellow_button():
	"""Drop the yellow button down"""
	print("_drop_yellow_button called, yellow_button exists: ", yellow_button != null, ", already dropped: ", yellow_button_dropped)
	if not yellow_button or yellow_button_dropped:
		return
	
	print("Dropping yellow button from position: ", yellow_button.position, " to: ", Vector2(yellow_button_original_position.x, yellow_button_original_position.y + button_pressed_offset))
	yellow_button_dropped = true
	var target_position = Vector2(yellow_button_original_position.x, yellow_button_original_position.y + button_pressed_offset)
	
	# Create smooth drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(yellow_button, "position", target_position, BUTTON_ANIM_DURATION * 2)

func _return_yellow_button():
	"""Return the yellow button to its original position"""
	if not yellow_button or not yellow_button_dropped:
		return
	
	yellow_button_dropped = false
	
	# Create smooth return animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(yellow_button, "position", yellow_button_original_position, BUTTON_ANIM_DURATION)

func _drop_blue_button():
	"""Drop the blue button down"""
	print("_drop_blue_button called, blue_button exists: ", blue_button != null, ", already dropped: ", blue_button_dropped)
	if not blue_button or blue_button_dropped:
		return
	
	print("Dropping blue button from position: ", blue_button.position, " to: ", Vector2(blue_button_original_position.x, blue_button_original_position.y + button_pressed_offset))
	blue_button_dropped = true
	var target_position = Vector2(blue_button_original_position.x, blue_button_original_position.y + button_pressed_offset)
	
	# Create smooth drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(blue_button, "position", target_position, BUTTON_ANIM_DURATION * 2)

func _return_blue_button():
	"""Return the blue button to its original position"""
	if not blue_button or not blue_button_dropped:
		return
	
	blue_button_dropped = false
	
	# Create smooth return animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(blue_button, "position", blue_button_original_position, BUTTON_ANIM_DURATION)

func _drop_green_button():
	"""Drop the green button down"""
	print("_drop_green_button called, green_button exists: ", green_button != null, ", already dropped: ", green_button_dropped)
	if not green_button or green_button_dropped:
		return
	
	print("Dropping green button from position: ", green_button.position, " to: ", Vector2(green_button_original_position.x, green_button_original_position.y + button_pressed_offset))
	green_button_dropped = true
	var target_position = Vector2(green_button_original_position.x, green_button_original_position.y + button_pressed_offset)
	
	# Create smooth drop animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BOUNCE)
	tween.tween_property(green_button, "position", target_position, BUTTON_ANIM_DURATION * 2)

func _return_green_button():
	"""Return the green button to its original position"""
	if not green_button or not green_button_dropped:
		return
	
	green_button_dropped = false
	
	# Create smooth return animation
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(green_button, "position", green_button_original_position, BUTTON_ANIM_DURATION)

func _return_all_other_buttons(except_button: String):
	"""Return all buttons to original position except the specified one"""
	if except_button != "red":
		_return_red_button()
	if except_button != "yellow":
		_return_yellow_button()
	if except_button != "blue":
		_return_blue_button()
	if except_button != "green":
		_return_green_button()

func _set_only_button_dropped(button_name: String):
	"""Ensure only one button is dropped at a time"""
	# First, return all buttons to their original positions
	_return_all_buttons()
	
	# Then drop only the specified button
	match button_name:
		"red":
			_drop_red_button()
		"yellow":
			_drop_yellow_button()
		"blue":
			_drop_blue_button()
		"green":
			_drop_green_button()

func _return_all_buttons():
	"""Return all buttons to their original positions"""
	_return_red_button()
	_return_yellow_button()
	_return_blue_button()
	_return_green_button()

func _find_player():
	# Try multiple methods to find the player
	player = get_tree().get_first_node_in_group("player")
	
	if not player:
		var game_node = get_tree().get_first_node_in_group("game")
		if game_node:
			player = game_node.get_node_or_null("Player")
	
	if not player:
		# Search for Player node in the scene tree
		var root = get_tree().current_scene
		player = _search_for_player(root)
	
	if player:
		print("CassetteButtonlessUI: Found player - ", player.name)
		
		# Set up the connection between player and UI for health system
		if player.has_method("set_ui_reference"):
			player.set_ui_reference(self)
			print("CassetteButtonlessUI: Connected to player health system")
		
		# Initialize hearts system
		_initialize_hearts()
	else:
		print("CassetteButtonlessUI: Player not found")

func _search_for_player(node: Node) -> Node:
	if node.name == "Player":
		return node
	
	for child in node.get_children():
		var result = _search_for_player(child)
		if result:
			return result
	
	return null

func _find_player_manager():
	# Try to find the player manager in the scene tree
	player_manager = get_tree().get_first_node_in_group("player_manager")
	
	if not player_manager:
		# Search for PlayerManager node in the scene tree
		var root = get_tree().current_scene
		player_manager = _search_for_player_manager(root)
	
	if not player_manager:
		# Try looking for it as a parent or sibling node
		var parent_node = get_parent()
		while parent_node:
			if parent_node.name == "PlayerManager":
				player_manager = parent_node
				break
			parent_node = parent_node.get_parent()
	
	if player_manager:
		print("CassetteButtonlessUI: Found player manager - ", player_manager.name)
		
		# Connect to player manager signals if available
		if player_manager.has_signal("track_changed"):
			player_manager.connect("track_changed", Callable(self, "_on_player_manager_track_changed"))
	else:
		print("CassetteButtonlessUI: Player manager not found")

func _search_for_player_manager(node: Node) -> Node:
	if node.name == "PlayerManager":
		return node
	
	for child in node.get_children():
		var result = _search_for_player_manager(child)
		if result:
			return result
	
	return null

# Handle track changes from the player manager
func _on_player_manager_track_changed(track_number: int):
	# Convert from player manager track numbering (0-3) to UI numbering (1-4)
	var ui_track = track_number + 1
	if ui_track != current_track:
		switch_to_track(ui_track)

# Update the UI to reflect the current track without triggering track switching
func update_track_display_only(track_number: int):
	"""Update only the visual display without triggering track switching logic"""
	if track_number < 1 or track_number > 4:
		return
	
	current_track = track_number
	_update_timer_display()
	_update_progress_bar()
	
	# Update button visuals
	match track_number:
		1:
			_set_only_button_dropped("red")
		2:
			_set_only_button_dropped("yellow")
		3:
			_set_only_button_dropped("blue")
		4:
			_set_only_button_dropped("green")

func toggle_visibility():
	ui_visible = !ui_visible
	_animate_slide()
	ui_toggled.emit(ui_visible)

func show_ui():
	if not ui_visible:
		ui_visible = true
		_animate_slide()
		ui_toggled.emit(ui_visible)

func hide_ui():
	if ui_visible:
		ui_visible = false
		_animate_slide()
		ui_toggled.emit(ui_visible)

func _animate_slide():
	# Kill existing tween
	if slide_tween:
		slide_tween.kill()
	
	slide_tween = create_tween()
	slide_tween.set_ease(SLIDE_EASE_TYPE)
	slide_tween.set_trans(SLIDE_TRANS_TYPE)
	
	var target_position = original_position if ui_visible else hidden_position
	slide_tween.tween_property(self, "position", target_position, SLIDE_DURATION)

# Simplified display update since this is just button UI
func _update_display():
	# This version is just for button animations, no stats display
	pass

# Timer functions
func start_timer():
	"""Start the countdown timer for current track"""
	if timer_label:
		is_timer_running = true
		_update_timer_display()
		_update_progress_bar()
		print("Timer started for track ", current_track, " - time remaining: ", timer_per_track.get(current_track, default_track_time), " seconds")
	else:
		print("Error: TimerLabel not found! Cannot start timer.")

func start_rewind_timer():
	"""Begin rewinding the current track's timer (counts up towards default)."""
	is_timer_rewinding = true

func stop_rewind_timer():
	"""Stop rewinding the track timer; resume normal countdown if running."""
	is_timer_rewinding = false

func _process(delta):
	"""Update timer each frame"""
	if is_timer_running:
		# Ensure the current track has a timer entry to avoid out-of-bounds errors
		var time_left = timer_per_track.get(current_track, default_track_time)
		if is_timer_rewinding:
			# Rewind: increase remaining time, up to default_track_time
			time_left = min(default_track_time, time_left + delta)
		else:
			# Normal countdown
			time_left = max(0.0, time_left - delta)
		timer_per_track[current_track] = time_left
		_update_timer_display()
		_update_progress_bar()

		# Check if current track timer has finished
		if timer_per_track[current_track] <= 0.0:
			timer_per_track[current_track] = 0.0
			_update_timer_display()
			_update_progress_bar()

			# Store which track just finished before any track switching
			var finished_track = current_track

			print("Track ", finished_track, " timer finished!")
			timer_finished.emit("timer_finished")
			track_timer_finished.emit(finished_track)

			# Stop the timer before switching tracks
			is_timer_running = false

			# Auto-progress to next track
			_auto_progress_to_next_track()

func set_progress(_progress: float) -> void:
	"""Optional hook for external rewind progress (no-op for now)."""
	pass

func _auto_progress_to_next_track():
	"""Automatically move to the next track when current one finishes"""
	var next_track = current_track + 1
	
	# If we've completed all tracks (1-4), stop the timer system
	if next_track > 4:
			is_timer_running = false
			print("All tracks completed! Timer system stopped.")
			if player_manager and player_manager.has_method("reset_all_players"):
					player_manager.reset_all_players()
			reset_all_track_timers()
			switch_to_track(1)
			return
	
	# Move to next track in strict sequence
	print("Auto-progressing from track ", current_track, " to track ", next_track)
	switch_to_track(next_track)
	
	# Update button display to show new active track
	match next_track:
		2:
			_set_only_button_dropped("yellow")
		3:
			_set_only_button_dropped("blue")
		4:
			_set_only_button_dropped("green")

func _update_timer_display():
		"""Update the timer label with current time"""
		if not timer_label:
				print("Warning: TimerLabel is null, cannot update display")
				return

		var time_left = timer_per_track.get(current_track, default_track_time)
		# Convert to minutes and seconds
		var minutes = int(floor(time_left / 60.0))
		var seconds = int(floor(fmod(time_left, 60.0)))

		# Format as MM:SS
		var time_text = "%02d:%02d" % [minutes, seconds]
		timer_label.text = time_text

		# Debug output every 10 seconds
		if int(time_left) % 10 == 0 and time_left != 0:
				print("Timer: ", time_text)

func _update_progress_bar():
		"""Update the progress bar with current time remaining"""
		if not timer_progress_bar:
				print("Warning: ProgressBar is null, cannot update display")
				return

		# Ensure progress bar is configured correctly
		timer_progress_bar.max_value = 100.0
		timer_progress_bar.min_value = 0.0
		timer_progress_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END

		# Calculate progress percentage (elapsed time / total time * 100)
		# This will grow from 0 to 100 as time progresses
		var time_left = timer_per_track.get(current_track, default_track_time)
		var elapsed_time = default_track_time - time_left
		var progress_percentage = (elapsed_time / default_track_time) * 100.0
		progress_percentage = max(0.0, min(100.0, progress_percentage))  # Clamp between 0-100

		timer_progress_bar.value = progress_percentage
	
	# Debug output to verify progress bar is updating
		#if int(timer_per_track.get(current_track, 0)) % 5 == 0:  # Debug every 5 seconds
		#print("Progress bar updated: ", progress_percentage, "% - Elapsed: ", elapsed_time, "/", default_track_time, " - Track ", current_track)
		#print("Progress bar max_value: ", timer_progress_bar.max_value, ", current value: ", timer_progress_bar.value)

func get_time_remaining() -> float:
		"""Get the remaining time in seconds"""
		return timer_per_track.get(current_track, default_track_time)

func is_timer_active() -> bool:
	"""Check if the timer is currently running"""
	return is_timer_running

func stop_timer():
	"""Stop the timer"""
	is_timer_running = false

func reset_timer():
		"""Reset the current track timer to default track time"""
		timer_per_track[current_track] = default_track_time
		_update_timer_display()
		_update_progress_bar()
		print("Reset track ", current_track, " timer to: ", default_track_time)

func set_countdown_time(new_time: float):
		"""Set a new countdown time"""
		countdown_time = new_time
		if not is_timer_running:
				timer_per_track[current_track] = countdown_time
				_update_timer_display()
				_update_progress_bar()

# Multi-track timer system functions
func _initialize_timer_per_track():
		"""Initialize all track timers with default time"""
		for i in range(1, 5):  # Tracks 1-4
				timer_per_track[i] = default_track_time
		print("Track timers initialized: ", timer_per_track)

func _initialize_health_per_track():
		"""Initialize health values for all tracks"""
		for i in range(1, 5):
				health_per_track[i] = max_health
		print("Health per track initialized: ", health_per_track)

func switch_to_track(track_number: int):
		"""Switch to a different track, saving current progress and loading new track's progress"""
		if track_number < 1 or track_number > 4:
			print("Invalid track number: ", track_number)
			return

		if current_track == track_number:
			# Do nothing if the requested track is already active
			return

		var old_track = current_track
			
		# Ensure outgoing track data is stored
		if old_track >= 1 and old_track <= 4:
			timer_per_track[old_track] = timer_per_track.get(old_track, default_track_time)
			
		if player and player.has_method("get_health"):
			health_per_track[old_track] = player.get_health()
		else:
			health_per_track[old_track] = health_per_track.get(old_track, max_health)

		# Switch to new track
		current_track = track_number

		# Initialize dictionaries for new track if needed
		if not timer_per_track.has(current_track):
			timer_per_track[current_track] = default_track_time
			
		if not health_per_track.has(current_track):
			health_per_track[current_track] = max_health

		# enemy positions for new track
		_reset_enemy_positions()

		# the player manager before connecting to the new player
		track_changed.emit(current_track)
		
		if player_manager and player_manager.has_method("switch_to_track"):
			player_manager.switch_to_track(current_track - 1)  # Convert from 1-4 to 0-3

		# Connect to the new active player's health system
		_connect_to_active_player()

		# Update displays
		_update_hearts_display()
		_update_timer_display()
		_update_progress_bar()

		# Update button visuals to reflect the newly active track
		match current_track:
			1:
				_set_only_button_dropped("red")
			2:
				_set_only_button_dropped("yellow")
			3:
				_set_only_button_dropped("blue")
			4:
				_set_only_button_dropped("green")

		# Start timer if it wasn't running
		if not is_timer_running and timer_per_track[current_track] > 0:
			is_timer_running = true
			print("Started timer for track ", current_track)

func _reset_enemy_positions():
	"""Reset all enemy positions to their starting positions when switching tracks"""
	# Try to find all enemies in the scene
	var enemies = get_tree().get_nodes_in_group("enemies")
	
	for enemy in enemies:
		if enemy.has_method("reset_position"):
			enemy.reset_position()
			print("Reset enemy position: ", enemy.name)
		elif enemy.has_method("reset_to_spawn"):
			enemy.reset_to_spawn()
			print("Reset enemy to spawn: ", enemy.name)
	
	# If no enemies found in group, try searching the scene tree
	if enemies.is_empty():
		var root = get_tree().current_scene
		_search_and_reset_enemies(root)
	
	print("Enemy positions reset for track ", current_track)

func _search_and_reset_enemies(node: Node):
	"""Recursively search for enemy nodes and reset their positions"""
	# Check if this node is an enemy (you may need to adjust these conditions)
	if node.name.to_lower().contains("enemy") or node.has_method("reset_position"):
		if node.has_method("reset_position"):
			node.reset_position()
			print("Found and reset enemy: ", node.name)
		elif node.has_method("reset_to_spawn"):
			node.reset_to_spawn()
			print("Found and reset enemy to spawn: ", node.name)
	
	# Search children
	for child in node.get_children():
		_search_and_reset_enemies(child)

func _connect_to_active_player():
	"""Connect to the currently active player's health system"""
	if player_manager and player_manager.has_method("get_active_player"):
		var active_player = player_manager.get_active_player()
		if active_player and active_player.has_signal("health_changed"):
			# Disconnect from previous player if connected
			if player and player.has_signal("health_changed"):
				if player.health_changed.is_connected(_on_player_health_changed):
					player.health_changed.disconnect(_on_player_health_changed)

			# Connect to new active player
			active_player.health_changed.connect(_on_player_health_changed)
			player = active_player

			# Sync player's health with stored track health
			var hp = health_per_track.get(current_track, max_health)
			if active_player.has_method("set_health"):
				active_player.set_health(hp)
			
			health_per_track[current_track] = hp
			_update_hearts_display()
			print("UI synced with active player health: ", hp)

func _on_player_health_changed(new_health: int):
		"""Handle when the active player's health changes"""
		health_per_track[current_track] = clamp(new_health, 0, max_health)
		_update_hearts_display()
		health_changed.emit(health_per_track[current_track])
		print("UI: Player health changed to ", health_per_track[current_track], "/", max_health)

func get_current_track() -> int:
	"""Get the currently active track number"""
	return current_track

func get_track_time_remaining(track_number: int) -> float:
		"""Get the time remaining for a specific track"""
		if track_number >= 1 and track_number <= 4:
				return timer_per_track.get(track_number, default_track_time)
		return 0.0

func set_track_time(track_number: int, new_time: float):
		"""Set the time for a specific track"""
		if track_number >= 1 and track_number <= 4:
				timer_per_track[track_number] = new_time
				if track_number == current_track:
						_update_timer_display()
						_update_progress_bar()
				print("Set track ", track_number, " time to: ", new_time)

func reset_track_timer(track_number: int):
		"""Reset a specific track timer to default time"""
		if track_number >= 1 and track_number <= 4:
				timer_per_track[track_number] = default_track_time
				if track_number == current_track:
						_update_timer_display()
						_update_progress_bar()
				print("Reset track ", track_number, " timer to: ", default_track_time)

func reset_all_track_timers():
		"""Reset all track timers to default time"""
		for i in range(1, 5):
				timer_per_track[i] = default_track_time
		_update_timer_display()
		_update_progress_bar()
		print("Reset all track timers to: ", default_track_time)

func get_all_track_times() -> Dictionary:
		"""Get a dictionary of all track times"""
		var all_times = timer_per_track.duplicate()
		return all_times

# Public methods for external scripts to control button animations
func animate_red_button():
	if button_click_audio:
		button_click_audio.play()
	switch_to_track(1)
	_set_only_button_dropped("red")

func animate_yellow_button():
	if button_click_audio:
		button_click_audio.play()
	switch_to_track(2)
	_set_only_button_dropped("yellow")

func animate_blue_button():
	if button_click_audio:
		button_click_audio.play()
	switch_to_track(3)
	_set_only_button_dropped("blue")

func animate_green_button():
	if button_click_audio:
		button_click_audio.play()
	switch_to_track(4)
	_set_only_button_dropped("green")

# Public methods for external control
func set_player_reference(player_node: Node):
	"""Set the player reference manually"""
	player = player_node
	var name_text := "null"
	if player_node:
		name_text = player_node.name
	print("CassetteButtonlessUI: Player reference set to ", name_text)

func is_ui_visible() -> bool:
	"""Check if the UI is currently visible"""
	return ui_visible

func is_red_button_dropped() -> bool:
	"""Check if red button is currently dropped"""
	return red_button_dropped

func is_yellow_button_dropped() -> bool:
	"""Check if yellow button is currently dropped"""
	return yellow_button_dropped

func is_blue_button_dropped() -> bool:
	"""Check if blue button is currently dropped"""
	return blue_button_dropped

func is_green_button_dropped() -> bool:
	"""Check if green button is currently dropped"""
	return green_button_dropped

func force_drop_red_button():
	"""Force drop red button (external API)"""
	_drop_red_button()

func force_return_red_button():
	"""Force return red button (external API)"""
	_return_red_button()

func force_drop_yellow_button():
	"""Force drop yellow button (external API)"""
	_drop_yellow_button()

func force_return_yellow_button():
	"""Force return yellow button (external API)"""
	_return_yellow_button()

func force_drop_blue_button():
	"""Force drop blue button (external API)"""
	_drop_blue_button()

func force_return_blue_button():
	"""Force return blue button (external API)"""
	_return_blue_button()

func force_drop_green_button():
	"""Force drop green button (external API)"""
	_drop_green_button()

func force_return_green_button():
	"""Force return green button (external API)"""
	_return_green_button()

func clear_all_buttons():
	"""Clear all button states - return all to original positions"""
	_return_all_buttons()

# Health management functions following the requested pattern
func lose_heart():
	"""Remove one heart from UI following the signal pattern"""
	var current_health = health_per_track.get(current_track, max_health)
	if current_health > 0:
		current_health -= 1
		health_per_track[current_track] = current_health
		_update_hearts_display()
		health_changed.emit(current_health)
		print("UI: Lost heart, health now: ", current_health, "/", max_health)

func gain_heart():
	"""Add one heart to UI"""
	var current_health = health_per_track.get(current_track, max_health)
	if current_health < max_health:
		current_health += 1
		health_per_track[current_track] = current_health
		_update_hearts_display()
		health_changed.emit(current_health)
		print("UI: Gained heart, health now: ", current_health, "/", max_health)

func get_current_health() -> int:
	"""Get current health for the active track"""
	return health_per_track.get(current_track, max_health)
