extends Node

## SETTINGS ##
@export var track_scene		: Track		# Packed scene that contains a Track node with a Player inside.
@export var num_tracks		: int = 4
@export var recording_secs	: float = 15.0		# Length of one cassette loop.

## RUNTIME ##
var tracks				: Array[Track] = []
var active_index		: int = 0
var switching_locked	: bool = false		# Flip this when no overwrite is permitted.

### ----------------------------------------------------------------
func start_level() -> void:
	# Create & configure all tracks.
	for i in range(num_tracks):
		var t := track_scene._init()
		add_child(t)
		tracks.append(t)
	
	_set_active_track(0)

### ----------------------------------------------------------------
# INPUT “HUB” #######################################################

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	# ---- Handle track-switch keys first --------------------------
	if event.is_action_pressed("switch_next"):
		_switch_to((active_index + 1) % tracks.size())
		event.consume()
		return
	elif event.is_action_pressed("switch_prev"):
		_switch_to((active_index - 1 + tracks.size()) % tracks.size())
		event.consume()
		return
	elif event.is_action_pressed("switch_1"):
		_switch_to(0);	event.consume();	return
	elif event.is_action_pressed("switch_2"):
		_switch_to(1);	event.consume();	return
	elif event.is_action_pressed("switch_3"):
		_switch_to(2);	event.consume();	return
	elif event.is_action_pressed("switch_4"):
		_switch_to(3);	event.consume();	return
	
	# ---- Any other input goes to the active track ----------------
	if tracks.size() > 0:
		tracks[active_index].receive_input(event)
		event.consume()

### ----------------------------------------------------------------
func _switch_to(new_idx: int) -> void:
	if switching_locked or new_idx == active_index:
		return
	
	tracks[active_index].set_ghost_mode(true, false)
	active_index = clamp(new_idx, 0, tracks.size() - 1)
	tracks[active_index].set_ghost_mode(false, false)

func _set_active_track(idx: int) -> void:
	active_index = idx
	for i in range(tracks.size()):
		tracks[i].set_ghost_mode(i != idx, false)
