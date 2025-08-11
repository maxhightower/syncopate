class_name Track

extends Node

const PLAYER_SCENE := preload("res://scenes/player.tscn")

var _player: Player

func _ready() -> void:
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)

func get_player() -> Player:
	return _player

func receive_input(event: InputEvent) -> void:
	if _player:
		_player._unhandled_input(event)

func set_ghost_mode(enabled: bool, as_spirit: bool = false) -> void:
	if _player:
		_player.set_ghost_mode(enabled, as_spirit)
