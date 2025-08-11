extends Node
class_name EventManager

signal entity_killed(entity_id, track_id, timestamp)

const DEFAULT_BUFFER_SIZE := 256

var _track_buffers: Dictionary = {}
var _track_indices: Dictionary = {}

func record_event(event_data: Dictionary, track_id: int) -> void:
	var buffer: RingBuffer = _track_buffers.get(track_id)
	if buffer == null:
		buffer = RingBuffer.new(DEFAULT_BUFFER_SIZE)
		_track_buffers[track_id] = buffer
		_track_indices[track_id] = 0
	var timestamp: float = Time.get_ticks_msec() / 1000.0
	buffer.push([timestamp, event_data])

func replay_events(current_time: float, track_id: int) -> void:
	var buffer: RingBuffer = _track_buffers.get(track_id)
	if buffer == null:
		return
	var idx: int = _track_indices.get(track_id, 0)
	while idx < buffer.length:
		var entry = buffer.get_at(idx)
		if entry == null:
			break
		var timestamp: float = entry[0]
		if timestamp > current_time:
			break
		var data: Dictionary = entry[1]
		_handle_event(data, track_id, timestamp)
		idx += 1
	_track_indices[track_id] = idx

func _handle_event(event_data: Dictionary, track_id: int, timestamp: float) -> void:
	var event_type: String = event_data.get("type", "")
	match event_type:
		"entity_killed":
			entity_killed.emit(event_data.get("entity_id"), track_id, timestamp)
		_:
			pass
