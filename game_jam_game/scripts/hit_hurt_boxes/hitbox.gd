
class_name HitBox

extends Area2D

@export var damage := 1
# Reference to the owner of this hitbox (the entity that created it)
@export var hitbox_owner: Node = null
@export var knockback_multiplier: float = 400.0

# Different knockback multipliers for different attack types
@export var upward_attack_knockback_multiplier: float = 300.0  # Increased for better juggling
@export var downward_attack_knockback_multiplier: float = 600.0  # Increased for powerful slams
@export var regular_attack_knockback_multiplier: float = 400.0  # Increased standard knockback

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	collision_shape_2d.disabled = true

	# Try to auto-assign hitbox_owner if not set
	if hitbox_owner == null and get_parent():
		hitbox_owner = get_parent()

# Get the current knockback multiplier based on the active attack
func get_current_knockback_multiplier() -> float:
	# Try to get the sword's animation player to see what attack is playing
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var sword_anim = player.get_node_or_null("AnimatedSprite2D/Sword/AnimationPlayer")
		if sword_anim and sword_anim.is_playing():
			var current_animation = sword_anim.current_animation
			
			match current_animation:
				"up_ward_swing":
					return upward_attack_knockback_multiplier
				"down_ward_swing":
					return downward_attack_knockback_multiplier
				"swing":
					return regular_attack_knockback_multiplier
				_:
					return knockback_multiplier
	
	# Fallback to default knockback multiplier
	return knockback_multiplier

# Get the directional modifier for knockback based on attack type
func get_knockback_direction_modifier() -> Vector2:
	# Try to get the sword's animation player to see what attack is playing
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var sword_anim = player.get_node_or_null("AnimatedSprite2D/Sword/AnimationPlayer")
		if sword_anim and sword_anim.is_playing():
			var current_animation = sword_anim.current_animation
			var player_facing_left = player.animations.flip_h
			
			print("Attack type: ", current_animation, " | Player facing left: ", player_facing_left)
			
			match current_animation:
				"up_ward_swing":
					# Upward attacks knock enemies up and back with strong vertical force
					if player_facing_left:
						return Vector2(-0.5, -1.8)  # Up and to the left (much stronger vertical)
					else:
						return Vector2(0.5, -1.8)   # Up and to the right (much stronger vertical)
				"down_ward_swing":
					# Downward attacks slam enemies down with strong downward force
					if player_facing_left:
						return Vector2(-0.5, 1.5)   # Left and strongly down
					else:
						return Vector2(0.5, 1.5)    # Right and strongly down
				"swing":
					# Regular attacks push enemies horizontally with noticeable upward lift
					if player_facing_left:
						return Vector2(-1.0, -0.6)  # Left and up (increased upward)
					else:
						return Vector2(1.0, -0.6)   # Right and up (increased upward)
	
	# Fallback to horizontal knockback
	return Vector2(1.0, 0.0)

# Get the complete knockback vector (direction + force) for the current attack
func get_knockback_vector() -> Vector2:
	var force = get_current_knockback_multiplier()
	var direction = get_knockback_direction_modifier()
	return direction * force

# Get the current attack type as a string for debugging
func get_current_attack_type() -> String:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var sword_anim = player.get_node_or_null("AnimatedSprite2D/Sword/AnimationPlayer")
		if sword_anim and sword_anim.is_playing():
			return sword_anim.current_animation
	return "none"

# Get debug info about the current attack
func get_attack_debug_info() -> Dictionary:
	return {
		"attack_type": get_current_attack_type(),
		"knockback_force": get_current_knockback_multiplier(),
		"direction_modifier": get_knockback_direction_modifier(),
		"final_knockback_vector": get_knockback_vector(),
		"damage": get_damage()
	}

# Calculate the actual damage to deal, considering fast fall multiplier
func get_damage() -> int:
	# Check if this hitbox belongs to the player (for fast fall damage multiplier)
	var hitbox_owner = get_parent()
	var is_player_hitbox = false
	
	# Check if the hitbox owner is the player or player's sword
	if hitbox_owner:
		# Check if owner is player directly
		if hitbox_owner.is_in_group("player"):
			is_player_hitbox = true
		# Check if owner is player's sword (nested under player)
		elif hitbox_owner.get_parent() and hitbox_owner.get_parent().is_in_group("player"):
			is_player_hitbox = true
	
	# Only apply fast fall multiplier for player attacks
	if is_player_hitbox:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_fast_fall_damage_multiplier"):
			var multiplier = player.get_fast_fall_damage_multiplier()
			var final_damage = int(damage * multiplier)
			
			# Trigger motion blur for high-damage attacks
			if player.has_method("trigger_motion_blur_burst") and final_damage > damage * 2.0:
				var blur_intensity = clamp((multiplier - 1.0) * 0.3, 0.1, 0.6)
				player.trigger_motion_blur_burst(blur_intensity, 0.2)
			
			return final_damage
	
	# For enemy attacks or when fast fall logic doesn't apply, return base damage
	return damage

func _on_animation_player_animation_started(anim_name: StringName) -> void:
	print("animation start")
	collision_shape_2d.disabled = false

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	collision_shape_2d.disabled = true
