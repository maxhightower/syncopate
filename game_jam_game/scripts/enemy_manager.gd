extends Node
class_name EnemyManager

var enemies: Array[Node] = []

func _ready() -> void:
        add_to_group("enemy_manager")
        _refresh_enemy_list()

func _refresh_enemy_list() -> void:
        enemies.clear()
        for e in get_tree().get_nodes_in_group("enemies"):
                enemies.append(e)

func register_enemy(enemy: Node) -> void:
        if enemy not in enemies:
                enemies.append(enemy)

func reset_enemies() -> void:
        for e in enemies:
                if e and e.has_method("reset_for_new_loop"):
                        e.reset_for_new_loop()
