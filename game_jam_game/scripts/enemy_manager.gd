class_name EnemyManager
extends Node

var _next_id:int = 1
var _enemies_by_id:Dictionary = {}
var _enemy_to_id:Dictionary = {}
var _dead_enemies:Dictionary = {}
var _name_to_id:Dictionary = {}

func _ready() -> void:
    add_to_group("enemy_manager")
    _register_enemies()
    if Engine.has_singleton("EventManager"):
        var em = Engine.get_singleton("EventManager")
        if em.has_signal("entity_killed"):
            em.entity_killed.connect(_on_entity_killed)

func _register_enemies() -> void:
    _enemies_by_id.clear()
    _enemy_to_id.clear()
    _name_to_id.clear()
    var nodes = get_tree().get_nodes_in_group("enemy")
    for enemy in nodes:
        var track_id = _find_track_id(enemy)
        var key = enemy.name
        var id:int
        if _name_to_id.has(key):
            id = _name_to_id[key]
        else:
            id = _next_id
            _next_id += 1
            _name_to_id[key] = id
        _enemy_to_id[enemy] = id
        if not _enemies_by_id.has(id):
            _enemies_by_id[id] = {}
        _enemies_by_id[id][track_id] = enemy

func _find_track_id(node:Node) -> int:
    var current = node
    while current:
        var n := current.name
        if n.begins_with("Track"):
            return int(n.substr(5, n.length()))
        current = current.get_parent()
    return 0

func _on_entity_killed(killed_track_id:int, enemy_id:int) -> void:
    _dead_enemies[enemy_id] = true
    if not _enemies_by_id.has(enemy_id):
        return
    for track_id in _enemies_by_id[enemy_id].keys():
        if track_id == killed_track_id:
            continue
        var enemy = _enemies_by_id[enemy_id][track_id]
        if is_instance_valid(enemy):
            enemy.queue_free()

func reset_enemies(track_id:int) -> void:
    for enemy_id in _enemies_by_id.keys():
        var enemy = _enemies_by_id[enemy_id].get(track_id)
        if enemy == null:
            continue
        if _dead_enemies.has(enemy_id):
            if is_instance_valid(enemy):
                enemy.queue_free()
        else:
            if is_instance_valid(enemy) and enemy.has_method("reset_to_spawn"):
                enemy.reset_to_spawn()

static func get_manager() -> EnemyManager:
    var nodes = Engine.get_main_loop().get_nodes_in_group("enemy_manager")
    return nodes.size() > 0 ? nodes[0] : null
