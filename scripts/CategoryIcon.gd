extends Control
class_name CategoryIcon

# Draws category icons - dice faces for upper section, symbols for lower section

signal icon_pressed(category: String)

const ICON_BG := Color(0.25, 0.23, 0.22)  # Dark background
const ICON_FG := Color(0.96, 0.93, 0.87)  # Cream foreground
const DOT_COLOR := Color(0.15, 0.12, 0.10)  # Dark dots on dice
const GOLD_COLOR := Color(1.0, 0.84, 0.0)  # Gold for Yahtzee

# Dot positions for dice faces (normalized 0-1)
const DOT_POSITIONS := {
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.3, 0.3), Vector2(0.7, 0.7)],
	3: [Vector2(0.3, 0.3), Vector2(0.5, 0.5), Vector2(0.7, 0.7)],
	4: [Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 0.7)],
	5: [Vector2(0.3, 0.3), Vector2(0.7, 0.3), Vector2(0.5, 0.5), Vector2(0.3, 0.7), Vector2(0.7, 0.7)],
	6: [Vector2(0.25, 0.3), Vector2(0.5, 0.3), Vector2(0.75, 0.3), Vector2(0.25, 0.7), Vector2(0.5, 0.7), Vector2(0.75, 0.7)]
}

# Category display names and score hints
const CATEGORY_TOOLTIPS := {
	"ones": "Count and add only Aces (1s)",
	"twos": "Count and add only Twos",
	"threes": "Count and add only Threes",
	"fours": "Count and add only Fours",
	"fives": "Count and add only Fives",
	"sixes": "Count and add only Sixes",
	"three_of_a_kind": "3 of a kind: Add total of all 5 dice",
	"four_of_a_kind": "4 of a kind: Add total of all 5 dice",
	"full_house": "3 of one + 2 of another: Score 25",
	"small_straight": "Sequence of 4: Score 30",
	"large_straight": "Sequence of 5: Score 40",
	"yahtzee": "5 of a kind: Score 50!"
}

var category: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(56, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			icon_pressed.emit(category)
			accept_event()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	
	# Draw dark background
	draw_rect(rect, ICON_BG)
	
	# Draw category-specific icon
	match category:
		"ones": _draw_dice_face(1)
		"twos": _draw_dice_face(2)
		"threes": _draw_dice_face(3)
		"fours": _draw_dice_face(4)
		"fives": _draw_dice_face(5)
		"sixes": _draw_dice_face(6)
		"three_of_a_kind": _draw_three_of_a_kind()
		"four_of_a_kind": _draw_four_of_a_kind()
		"full_house": _draw_full_house()
		"small_straight": _draw_small_straight()
		"large_straight": _draw_large_straight()
		"yahtzee": _draw_yahtzee()
		"upper_bonus": _draw_bonus()
		"upper_total": _draw_sigma()
		"grand_total": _draw_sigma()

func _draw_dice_face(face: int) -> void:
	# Draw a small dice icon
	var dice_size := minf(size.x, size.y) * 0.75
	var dice_rect := Rect2(
		Vector2((size.x - dice_size) / 2, (size.y - dice_size) / 2),
		Vector2(dice_size, dice_size)
	)
	
	# Draw dice background (cream colored)
	_draw_rounded_rect_filled(dice_rect, ICON_FG, 4.0)
	
	# Draw dots
	var dot_radius := dice_size * 0.1
	if DOT_POSITIONS.has(face):
		for pos: Vector2 in DOT_POSITIONS[face]:
			var dot_pos := dice_rect.position + Vector2(pos.x * dice_size, pos.y * dice_size)
			draw_circle(dot_pos, dot_radius, DOT_COLOR)

func _draw_three_of_a_kind() -> void:
	# Draw "3×" text to indicate 3 of a kind = sum of all dice
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.45)
	var text := "3×"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_four_of_a_kind() -> void:
	# Draw "4×" text to indicate 4 of a kind = sum of all dice
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.45)
	var text := "4×"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_full_house() -> void:
	# Draw "3+2" or house-like icon for Full House (25 pts)
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.38)
	var text := "3+2"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_small_straight() -> void:
	# Draw 4 sequential numbers to indicate sequence of 4 (30 pts)
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.32)
	var text := "1234"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_large_straight() -> void:
	# Draw 5 sequential numbers to indicate sequence of 5 (40 pts)
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.32)
	var text := "12345"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_yahtzee() -> void:
	# Draw "5×" in gold with a star - YAHTZEE! (50 pts)
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.45)
	var text := "5×"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2 - 6, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GOLD_COLOR)
	
	# Draw a small star next to it
	var star_center := Vector2(size.x * 0.78, size.y * 0.5)
	_draw_star(star_center, size.y * 0.22, GOLD_COLOR)

func _draw_bonus() -> void:
	# Draw a "+" symbol
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.5)
	var text := "+35"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_sigma() -> void:
	# Draw sigma/sum symbol
	var font := ThemeDB.fallback_font
	var font_size := int(size.y * 0.5)
	var text := "Σ"
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := Vector2((size.x - text_size.x) / 2, (size.y + text_size.y) / 2 - 4)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ICON_FG)

func _draw_diamond(center: Vector2, size_val: float, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0, -size_val),
		center + Vector2(size_val, 0),
		center + Vector2(0, size_val),
		center + Vector2(-size_val, 0)
	])
	draw_colored_polygon(points, color)

func _draw_star(center: Vector2, size_val: float, color: Color) -> void:
	var points := PackedVector2Array()
	var inner_radius := size_val * 0.4
	
	for i in range(10):
		var angle := (i * PI / 5) - PI / 2
		var radius := size_val if i % 2 == 0 else inner_radius
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	
	draw_colored_polygon(points, color)

func _draw_rounded_rect_filled(rect: Rect2, color: Color, radius: float) -> void:
	var points := PackedVector2Array()
	var segments := 6
	
	for i in range(4):
		var corner_center: Vector2
		var start_angle: float
		match i:
			0:  # Top-left
				corner_center = rect.position + Vector2(radius, radius)
				start_angle = PI
			1:  # Top-right
				corner_center = rect.position + Vector2(rect.size.x - radius, radius)
				start_angle = -PI / 2
			2:  # Bottom-right
				corner_center = rect.position + Vector2(rect.size.x - radius, rect.size.y - radius)
				start_angle = 0
			3:  # Bottom-left
				corner_center = rect.position + Vector2(radius, rect.size.y - radius)
				start_angle = PI / 2
		
		for j in range(segments + 1):
			var angle := start_angle + (PI / 2) * (float(j) / segments)
			points.append(corner_center + Vector2(cos(angle), sin(angle)) * radius)
	
	draw_colored_polygon(points, color)

func set_category(cat: String) -> void:
	category = cat
	queue_redraw()
