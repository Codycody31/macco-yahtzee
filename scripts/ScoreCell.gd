extends Control
class_name ScoreCell

signal cell_pressed(category: String)

# Colors matching the reference image - supports up to 6 players
const COLOR_PLAYER_1 := Color(0.91, 0.45, 0.42)  # Coral/salmon red
const COLOR_PLAYER_2 := Color(0.55, 0.78, 0.73)  # Teal/mint green
const COLOR_PLAYER_3 := Color(0.65, 0.55, 0.85)  # Purple
const COLOR_PLAYER_4 := Color(0.95, 0.75, 0.45)  # Orange/gold
const COLOR_PLAYER_5 := Color(0.75, 0.85, 0.55)  # Light green
const COLOR_PLAYER_6 := Color(0.85, 0.65, 0.75)  # Pink
const COLOR_DISABLED := Color(0.75, 0.72, 0.68)  # Grayish beige
const COLOR_AVAILABLE := Color(0.96, 0.93, 0.87)  # Cream/beige (available to select)
const COLOR_HOVER := Color(1.0, 0.98, 0.92)  # Lighter on hover
const BORDER_COLOR := Color(0.35, 0.32, 0.30)  # Dark border

var category: String = ""
var player_index: int = 0  # 0-based player index
var score_value: int = -1  # -1 means not set
var is_taken: bool = false
var is_interactive: bool = false
var is_preview: bool = false
var is_hovered: bool = false

static func get_player_color(idx: int) -> Color:
	match idx % 6:
		0: return COLOR_PLAYER_1
		1: return COLOR_PLAYER_2
		2: return COLOR_PLAYER_3
		3: return COLOR_PLAYER_4
		4: return COLOR_PLAYER_5
		5: return COLOR_PLAYER_6
	return COLOR_PLAYER_1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	custom_minimum_size = Vector2(75, 40)  # Tighter default sizing

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	
	# Determine background color
	var bg_color: Color
	if is_taken:
		bg_color = get_player_color(player_index)
	elif is_preview and is_interactive:
		bg_color = COLOR_AVAILABLE if not is_hovered else COLOR_HOVER
	else:
		bg_color = COLOR_DISABLED
	
	# Draw background
	draw_rect(rect, bg_color)
	
	# Draw border - thinner for cleaner look
	draw_rect(rect, BORDER_COLOR, false, 1.0)
	
	# Draw score text - slightly smaller font
	if score_value >= 0:
		var font := ThemeDB.fallback_font
		var font_size := 18  # Reduced from 20
		var text := str(score_value)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 2)
		var text_color := Color(0.15, 0.12, 0.10) if is_taken else Color(0.3, 0.28, 0.25)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if not is_interactive or is_taken:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("cell_pressed", category)

func set_score(value: int, taken: bool = false, preview: bool = false) -> void:
	score_value = value
	is_taken = taken
	is_preview = preview
	queue_redraw()

func set_interactive(enabled: bool) -> void:
	is_interactive = enabled
	queue_redraw()
