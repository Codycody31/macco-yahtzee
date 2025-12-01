extends Control

signal dice_toggled(is_held: bool)

# Dot positions for each dice face (1-6), normalized to 0-1 range
const DOT_POSITIONS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.28, 0.28), Vector2(0.72, 0.72)],
	3: [Vector2(0.28, 0.28), Vector2(0.5, 0.5), Vector2(0.72, 0.72)],
	4: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	5: [Vector2(0.28, 0.28), Vector2(0.72, 0.28), Vector2(0.5, 0.5), Vector2(0.28, 0.72), Vector2(0.72, 0.72)],
	6: [Vector2(0.25, 0.28), Vector2(0.5, 0.28), Vector2(0.75, 0.28), Vector2(0.25, 0.72), Vector2(0.5, 0.72), Vector2(0.75, 0.72)]
}

# Updated colors for cleaner look
const DICE_BG_COLOR := Color(0.96, 0.93, 0.87)  # Cream/beige dice
const DICE_HELD_COLOR := Color(0.55, 0.78, 0.73)  # Teal when held (matches player 2 color)
const DOT_COLOR := Color(0.2, 0.18, 0.16)  # Dark brown dots
const STAR_COLOR := Color(0.7, 0.65, 0.55)  # Muted star color for placeholder
const BORDER_COLOR := Color(0.25, 0.23, 0.22)  # Dark border
const CORNER_RADIUS := 10.0
const BORDER_WIDTH := 2.0

var value: int = 0:  # 0 = placeholder star, 1-6 = dice face
	set(val):
		value = clampi(val, 0, 6)
		queue_redraw()

var held: bool = false:
	set(val):
		held = val
		queue_redraw()
		emit_signal("dice_toggled", held)

var interactive: bool = true

var _is_animating: bool = false
var _animation_tween: Tween = null

func _ready() -> void:
	# Remove old nodes we don't need anymore (Label, Background, HoldLabel)
	for child in get_children():
		child.queue_free()
	
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var inner_rect := rect.grow(-BORDER_WIDTH)
	
	# Draw shadow for depth
	var shadow_offset := Vector2(2, 2)
	var shadow_rect := Rect2(rect.position + shadow_offset, rect.size)
	_draw_rounded_rect(shadow_rect, Color(0, 0, 0, 0.2), CORNER_RADIUS)
	
	# Draw border
	_draw_rounded_rect(rect, BORDER_COLOR, CORNER_RADIUS)
	
	# Draw dice background
	var bg_color := DICE_HELD_COLOR if held else DICE_BG_COLOR
	_draw_rounded_rect(inner_rect, bg_color, CORNER_RADIUS - 1)
	
	# Draw dots or star placeholder
	if value == 0:
		# Draw star placeholder
		var center := size / 2
		var star_size := minf(size.x, size.y) * 0.35
		_draw_star(center, star_size, STAR_COLOR)
	else:
		# Draw dots
		var dice_size := minf(size.x, size.y)
		var dot_radius := dice_size * 0.09
		var padding := dice_size * 0.1
		var draw_area := Vector2(size.x - padding * 2, size.y - padding * 2)
		var offset := Vector2(padding, padding)
		
		if DOT_POSITIONS.has(value):
			for pos: Vector2 in DOT_POSITIONS[value]:
				var dot_pos := offset + Vector2(pos.x * draw_area.x, pos.y * draw_area.y)
				draw_circle(dot_pos, dot_radius, DOT_COLOR)

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	var inner_radius := radius * 0.4
	
	for i in range(10):
		var angle := (i * PI / 5) - PI / 2
		var r := radius if i % 2 == 0 else inner_radius
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	
	draw_colored_polygon(points, color)

func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	var points := PackedVector2Array()
	var segments := 8
	
	for i in range(4):
		var center: Vector2
		var start_angle: float
		match i:
			0:  # Top-left
				center = rect.position + Vector2(radius, radius)
				start_angle = PI
			1:  # Top-right
				center = rect.position + Vector2(rect.size.x - radius, radius)
				start_angle = -PI / 2
			2:  # Bottom-right
				center = rect.position + Vector2(rect.size.x - radius, rect.size.y - radius)
				start_angle = 0
			3:  # Bottom-left
				center = rect.position + Vector2(radius, rect.size.y - radius)
				start_angle = PI / 2
		
		for j in range(segments + 1):
			var angle := start_angle + (PI / 2) * (float(j) / segments)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	draw_colored_polygon(points, color)

func _on_gui_input(event: InputEvent) -> void:
	if not interactive or _is_animating:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		held = not held
		_animate_toggle()

func _animate_toggle() -> void:
	if _animation_tween and _animation_tween.is_valid():
		_animation_tween.kill()
	
	_animation_tween = create_tween()
	_animation_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.08)
	_animation_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func animate_roll(final_value: int, duration: float = 0.6) -> void:
	if _animation_tween and _animation_tween.is_valid():
		_animation_tween.kill()
	
	_is_animating = true
	var iterations := 8
	var interval := duration / iterations
	
	_animation_tween = create_tween()
	
	for i in range(iterations - 1):
		_animation_tween.tween_callback(_set_random_value)
		_animation_tween.tween_interval(interval)
	
	_animation_tween.tween_callback(func(): value = final_value)
	_animation_tween.tween_callback(func(): _is_animating = false)
	_animation_tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.05)
	_animation_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func _set_random_value() -> void:
	value = randi_range(1, 6)

func set_value_animated(new_value: int) -> void:
	if not held:
		animate_roll(new_value)
	else:
		value = new_value
