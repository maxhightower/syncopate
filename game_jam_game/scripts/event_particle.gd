class_name EventParticle

extends Label

@export var float_speed: float = 120.0  # Increased for more spring
@export var fade_speed: float = 2.0
@export var lifetime: float = 2.0
@export var bounce_strength: float = 30.0  # New: adds bounce effect

var velocity: Vector2 = Vector2.ZERO
var initial_position: Vector2
var elapsed_time: float = 0.0

func _ready() -> void:
	# Set up the label appearance with pixel art styling
	add_theme_font_size_override("font_size", 32)  # Larger for more impact
        add_theme_color_override("font_color", Color(1,1,0))
	add_theme_color_override("font_shadow_color", Color.BLACK)
	add_theme_constant_override("shadow_offset_x", 3)
	add_theme_constant_override("shadow_offset_y", 3)
	
	# Load and apply the pixel font
	var pixel_font = load("res://assets/fonts/Jersey15-Regular.ttf")
	if pixel_font:
		add_theme_font_override("font", pixel_font)
	
	# Set initial position and random velocity with more spring
	initial_position = global_position
	velocity = Vector2(randf_range(-40, 40), -float_speed - randf_range(0, 40))  # More random upward velocity
	
	# Set pivot to center for proper scaling
	pivot_offset = size / 2

func setup_event_text(event:String, spawn_position:Vector2) -> void:
        text = event
        global_position = spawn_position
        initial_position = spawn_position

func _process(delta: float) -> void:
	elapsed_time += delta
	
	# Move the particle
	global_position += velocity * delta
	
	# Apply stronger gravity-like effect for more spring
	velocity.y += 80 * delta  # Increased gravity for more arc
	
	# Add slight air resistance to horizontal movement
	velocity.x *= 0.98
	
	# Fade out over time
	var alpha = 1.0 - (elapsed_time / lifetime)
	modulate.a = alpha
	
	# More dramatic scale effect - starts bigger, bouncy scaling
	var progress = elapsed_time / lifetime
	var scale_factor = 1.2 + (0.8 * (1.0 - progress)) + sin(progress * 12.0) * 0.1 * (1.0 - progress)
	scale = Vector2(scale_factor, scale_factor)
	
	# Remove when lifetime expires
	if elapsed_time >= lifetime:
		queue_free()
