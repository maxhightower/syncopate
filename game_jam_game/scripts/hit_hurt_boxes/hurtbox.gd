class_name HurtBox

extends Area2D

# Damage cooldown to prevent multiple hits in rapid succession
@export var damage_cooldown: float = 0.5  # Half second between taking damage
var last_damage_time: float = 0.0


func _init() -> void:
	collision_layer = 0
	collision_mask = 4

func _ready() -> void:
	connect("area_entered", self._on_area_entered)

func _on_area_entered(hitbox: HitBox) -> void:
	if hitbox == null:
		return

	print("=== HURTBOX COLLISION DETECTED ===")
	var owner_name = "no owner"
	if owner:
		owner_name = String(owner.name)
	var src_parent = hitbox.get_parent()
	var src_name = "no parent"
	if src_parent:
		src_name = String(src_parent.name)
	print("Hurtbox owner: ", owner_name)
	print("Hitbox source: ", src_name)
	print("Hitbox damage: ", hitbox.damage)

	# Prevent self-damage: if the hitbox's owner is the same as the hurtbox's owner, ignore
	if hitbox.hitbox_owner == owner:
		print("Self-damage prevented: hitbox owner matches hurtbox owner.")
		return

	# Check if damage source is active (causality: dead sources shouldn't deal damage)
	var pm = get_tree().get_first_node_in_group("player_manager")
	var registry = get_tree().get_first_node_in_group("combat_registry")
	if pm and registry and registry.has_method("is_source_active_at"):
		var source_node = hitbox.get_parent()
		if source_node and not registry.is_source_active_at(source_node, pm.global_time):
			print("Damage ignored: source inactive at time ", pm.global_time)
			return

	# Check if the owner is the player
	var is_player = owner.is_in_group("player") or (owner.has_method("get_script") and owner.get_script() and owner.get_script().get_global_name() == "Player")

	print("Is player: ", is_player)

	# For player, check invincibility status instead of damage cooldown
	if is_player and owner.has_method("is_player_invincible") and owner.is_player_invincible():
		print("Player is invincible! Damage ignored by hurtbox.")
		return

	# For non-player entities, use the legacy damage cooldown system
	if not is_player:
		# Check damage cooldown to prevent multiple hits in rapid succession
		var current_time = Time.get_time_dict_from_system()
		var current_timestamp = current_time["hour"] * 3600 + current_time["minute"] * 60 + current_time["second"]

		if (current_timestamp - last_damage_time) < damage_cooldown and last_damage_time > 0.0:
			print("Damage blocked by cooldown! Time since last damage: ", current_timestamp - last_damage_time)
			return

		last_damage_time = current_timestamp

	# Get the actual damage (which may include fast fall multiplier)
	var actual_damage = hitbox.get_damage()
	print("Taking damage: ", actual_damage, " at time: ", Time.get_time_dict_from_system())

	if is_player and owner.has_method("take_damage"):
		# Player takes damage through the health system (which will handle invincibility)
		owner.take_damage(actual_damage)
	elif owner.has_method("take_damage"):
		# Non-player entities (like enemies) take damage directly
		owner.take_damage(actual_damage)

		# Trigger camera shake based on damage amount (only for player hits)
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("shake_camera_for_damage"):
			player.shake_camera_for_damage(actual_damage)

		# Calculate spawn position based on the collision shape bounds
		var collision_shape = $CollisionShape2D
		if collision_shape and collision_shape.shape:
			# Get the top of the collision bounds
			var shape_top = collision_shape.global_position.y - (collision_shape.shape.get_rect().size.y * collision_shape.scale.y / 2)
			var spawn_position = Vector2(
				collision_shape.global_position.x + randf_range(-20, 20),
				shape_top - 20  # Spawn 20 pixels above the top of the collision shape
			)
			DamageParticleManager.spawn_damage_text(actual_damage, spawn_position)
		else:
			# Fallback: use hurtbox position with upward offset
			var spawn_position = global_position + Vector2(randf_range(-15, 15), -80)
			DamageParticleManager.spawn_damage_text(actual_damage, spawn_position)

	if owner.has_method("apply_knockback"):
		# Use the hitbox's complete knockback vector calculation
		var knockback_vector = hitbox.get_knockback_vector()
		var debug_info = hitbox.get_attack_debug_info()

		print("Knockback Debug - Attack: ", debug_info.attack_type, 
			  " | Force: ", debug_info.knockback_force, 
			  " | Direction: ", debug_info.direction_modifier, 
			  " | Final Vector: ", debug_info.final_knockback_vector)

		owner.apply_knockback(knockback_vector)
