extends Node
class_name CombatRegistry

var earliest_kill_time: Dictionary = {}

func _ready() -> void:
	add_to_group("combat_registry")

func _get_id(node: Node) -> String:
	if node == null:
		return ""
	return str(node.get_instance_id())

func record_kill(entity: Node, time: float) -> void:
	var id = _get_id(entity)
	if id == "":
		return
	if not earliest_kill_time.has(id) or time < float(earliest_kill_time[id]):
		earliest_kill_time[id] = time

func is_entity_alive_at(entity: Node, t: float) -> bool:
	var id = _get_id(entity)
	if id == "":
		return true
	if not earliest_kill_time.has(id):
		return true
	return t < float(earliest_kill_time[id])

func is_source_active_at(source: Node, t: float) -> bool:
	return is_entity_alive_at(source, t)
