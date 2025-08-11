extends Control
class_name PauseMenu

signal resume_requested
signal restart_requested
signal quit_requested

@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var restart_button: Button = $Panel/VBoxContainer/RestartButton
@onready var quit_button: Button = $Panel/VBoxContainer/QuitButton


func _ready() -> void:
	# Ensure the menu keeps processing while the tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func show_menu():
	visible = true
	get_tree().paused = true

func hide_menu():
	visible = false
	get_tree().paused = false

func toggle():
	if visible:
		hide_menu()
	else:
		show_menu()

func _on_resume_pressed():
	hide_menu()
	resume_requested.emit()

func _on_restart_pressed():
	# Try to reload the current scene safely in Godot 4
	var current := get_tree().current_scene
	if current and current.scene_file_path != "":
		var path := current.scene_file_path
		get_tree().paused = false
		var err = get_tree().change_scene_to_file(path)
		if err != OK:
			push_warning("Failed to restart scene: %s" % path)
	else:
		# Fallback
		get_tree().paused = false
	restart_requested.emit()

func _on_quit_pressed():
	quit_requested.emit()
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	# Allow ESC to resume while paused
	if event is InputEventKey and not event.echo and event.pressed:
		if event.keycode == KEY_ESCAPE:
			toggle()
