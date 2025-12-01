extends PanelContainer

const CategoryIconScript := preload("res://scripts/CategoryIcon.gd")
const ScoreCellScript := preload("res://scripts/ScoreCell.gd")

signal category_chosen(category_name: String)

# Visual constants
const PANEL_BG_COLOR := Color(0.96, 0.93, 0.87)  # Cream/beige background
const PANEL_BORDER_COLOR := Color(0.25, 0.23, 0.22)  # Dark border
const HEADER_BG_COLOR := Color(0.35, 0.32, 0.30)  # Dark header
const HEADER_TEXT_COLOR := Color(0.96, 0.93, 0.87)  # Light text
const ACTIVE_TURN_COLOR := Color(1.0, 0.95, 0.7)  # Soft yellow highlight for active turn

# Player colors (matching ScoreCell)
const PLAYER_COLORS := [
	Color(0.91, 0.45, 0.42),  # Coral/salmon red
	Color(0.55, 0.78, 0.73),  # Teal/mint green
	Color(0.65, 0.55, 0.85),  # Purple
	Color(0.95, 0.75, 0.45),  # Orange/gold
]

# Categories in display order
const UPPER_CATEGORIES := ["ones", "twos", "threes", "fours", "fives", "sixes"]
const LOWER_CATEGORIES := ["three_of_a_kind", "four_of_a_kind", "full_house", "small_straight", "large_straight", "yahtzee"]

var all_categories: Array[String] = []
var player_count: int = 2
var local_player_index: int = 0
var current_turn_player: int = 0  # Which player's turn it is
var player_names: Array[String] = []

# UI references
var main_container: VBoxContainer
var header_container: HBoxContainer
var grid: GridContainer
var totals_container: HBoxContainer
var player_headers: Array = []  # PanelContainer for each player header
var total_labels: Array = []  # Labels showing each player's total
var category_icons: Dictionary = {}  # category -> CategoryIcon
var category_rows: Dictionary = {}  # category -> row HBoxContainer for highlighting
var score_cells: Dictionary = {}  # category -> Array of ScoreCell (one per player)
var taken_categories: Dictionary = {}  # category -> Array of bool (one per player)
var locked_scores: Dictionary = {}  # category -> Array of int (score values, -1 if not set)
var scores_by_player_id: Dictionary = {}  # player_id -> {category -> score} - persists across rebuilds
var current_player_order: Array = []  # Current order of player IDs for index mapping
var preview_scores: Dictionary = {}
var info_overlay: Control = null  # Overlay for showing category info

func _ready() -> void:
	# Build category list
	all_categories.clear()
	for cat in UPPER_CATEGORIES:
		all_categories.append(cat)
	for cat in LOWER_CATEGORIES:
		all_categories.append(cat)
	
	_setup_panel_style()
	_build_ui()

func _setup_panel_style() -> void:
	# Create a styled panel
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)

func _build_ui() -> void:
	# Clear existing children immediately to avoid duplication
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
	# Main scroll container
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	
	main_container = VBoxContainer.new()
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_theme_constant_override("separation", 0)
	scroll.add_child(main_container)
	
	_build_header()
	_build_grid()
	_build_totals()

func _build_header() -> void:
	# Header row with player names
	header_container = HBoxContainer.new()
	header_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_theme_constant_override("separation", 0)
	main_container.add_child(header_container)
	
	player_headers.clear()
	
	# Empty space for category icon column
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(56, 36)
	header_container.add_child(spacer)
	
	# Player name headers
	for i in range(player_count):
		var header := PanelContainer.new()
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.custom_minimum_size = Vector2(80, 36)
		
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if i < player_names.size():
			label.text = player_names[i]
		else:
			label.text = "P%d" % (i + 1)
		label.add_theme_font_size_override("font_size", 14)
		
		header.add_child(label)
		header_container.add_child(header)
		player_headers.append(header)
	
	_update_header_styles()

func _update_header_styles() -> void:
	for i in range(player_headers.size()):
		var header: PanelContainer = player_headers[i]
		var style := StyleBoxFlat.new()
		
		# Base color is player's color
		var base_color: Color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
		
		# Highlight current player's turn
		if i == current_turn_player:
			style.bg_color = ACTIVE_TURN_COLOR
			style.border_color = base_color
			style.set_border_width_all(3)
		else:
			style.bg_color = base_color.darkened(0.1)
			style.border_color = PANEL_BORDER_COLOR
			style.set_border_width_all(1)
		
		style.set_corner_radius_all(4)
		header.add_theme_stylebox_override("panel", style)
		
		# Update label color
		var label: Label = header.get_child(0)
		if i == current_turn_player:
			label.add_theme_color_override("font_color", Color(0.15, 0.12, 0.10))
		else:
			label.add_theme_color_override("font_color", HEADER_TEXT_COLOR)

func _build_grid() -> void:
	# Clear UI references only - taken_categories and locked_scores are now
	# managed by set_players_ordered based on scores_by_player_id
	category_icons.clear()
	score_cells.clear()
	
	# Grid: 1 column for icons + player_count columns for scores
	grid = GridContainer.new()
	grid.columns = 1 + player_count
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	main_container.add_child(grid)
	
	# Ensure tracking arrays exist for all categories (may already be set by set_players_ordered)
	for cat in all_categories:
		if not taken_categories.has(cat):
			taken_categories[cat] = []
			for _i in range(player_count):
				taken_categories[cat].append(false)
		if not locked_scores.has(cat):
			locked_scores[cat] = []
			for _i in range(player_count):
				locked_scores[cat].append(-1)
	
	# Build rows for each category
	for cat in all_categories:
		_add_category_row(cat)

func _add_category_row(cat: String) -> void:
	# Category icon column
	var icon := Control.new()
	icon.set_script(CategoryIconScript)
	icon.set_category(cat)
	icon.custom_minimum_size = Vector2(56, 44)
	icon.icon_pressed.connect(_on_icon_pressed)
	grid.add_child(icon)
	category_icons[cat] = icon
	
	# Score cells for each player
	score_cells[cat] = []
	for p_idx in range(player_count):
		var cell := Control.new()
		cell.set_script(ScoreCellScript)
		cell.category = cat
		cell.player_index = p_idx
		cell.custom_minimum_size = Vector2(80, 44)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.cell_pressed.connect(_on_cell_pressed)
		grid.add_child(cell)
		score_cells[cat].append(cell)
		
		# If this category was already taken, restore the score and mark as taken
		if taken_categories.has(cat) and p_idx < taken_categories[cat].size():
			if taken_categories[cat][p_idx]:
				var saved_score: int = -1
				if locked_scores.has(cat) and p_idx < locked_scores[cat].size():
					saved_score = locked_scores[cat][p_idx]
				cell.set_score(saved_score, true, false)
				cell.set_interactive(false)

func _build_totals() -> void:
	total_labels.clear()
	
	# Totals row container
	totals_container = HBoxContainer.new()
	totals_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	totals_container.add_theme_constant_override("separation", 0)
	main_container.add_child(totals_container)
	
	# "Total" label in icon column
	var total_icon := PanelContainer.new()
	total_icon.custom_minimum_size = Vector2(56, 48)
	var total_icon_style := StyleBoxFlat.new()
	total_icon_style.bg_color = HEADER_BG_COLOR
	total_icon_style.set_corner_radius_all(0)
	total_icon.add_theme_stylebox_override("panel", total_icon_style)
	var total_text := Label.new()
	total_text.text = "Σ"
	total_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_text.add_theme_font_size_override("font_size", 20)
	total_text.add_theme_color_override("font_color", HEADER_TEXT_COLOR)
	total_icon.add_child(total_text)
	totals_container.add_child(total_icon)
	
	# Total score for each player
	for i in range(player_count):
		var total_panel := PanelContainer.new()
		total_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		total_panel.custom_minimum_size = Vector2(80, 48)
		
		var style := StyleBoxFlat.new()
		style.bg_color = PLAYER_COLORS[i % PLAYER_COLORS.size()].lightened(0.2)
		style.border_color = PANEL_BORDER_COLOR
		style.set_border_width_all(1)
		total_panel.add_theme_stylebox_override("panel", style)
		
		var score_label := Label.new()
		score_label.text = "0"
		score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_label.add_theme_font_size_override("font_size", 18)
		score_label.add_theme_color_override("font_color", Color(0.15, 0.12, 0.10))
		total_panel.add_child(score_label)
		
		totals_container.add_child(total_panel)
		total_labels.append(score_label)
	
	_update_totals()

func _update_totals() -> void:
	for i in range(total_labels.size()):
		var total := get_grand_total(i)
		var bonus := get_upper_bonus(i)
		var label: Label = total_labels[i]
		if bonus > 0:
			label.text = "%d (+%d)" % [total, bonus]
		else:
			label.text = str(total)

func set_player_count(count: int) -> void:
	player_count = clampi(count, 1, 4)
	if main_container:
		# Rebuild the UI with new player count
		for child in main_container.get_children():
			child.queue_free()
		_build_header()
		_build_grid()
		_build_totals()

func set_players(players_dict: Dictionary, local_id: String) -> void:
	# Fallback - use dictionary order (may be inconsistent)
	var order: Array = []
	for pid in players_dict.keys():
		order.append(pid)
	set_players_ordered(players_dict, order, local_id)

func set_players_ordered(players_dict: Dictionary, order: Array, local_id: String) -> void:
	# Store the new player order for index mapping
	current_player_order.clear()
	for pid in order:
		current_player_order.append(str(pid))
	
	player_names.clear()
	var idx := 0
	for pid in order:
		var pid_str := str(pid)
		if players_dict.has(pid_str):
			var pdata = players_dict[pid_str]
			var pname: String = "P%d" % (idx + 1)
			# Handle both Dictionary and other types
			if pdata is Dictionary:
				var n = str(pdata.get("name", pdata.get("player_name", "")))
				if n != "":
					pname = n
			elif typeof(pdata) == TYPE_DICTIONARY:
				var n = str(pdata.get("name", pdata.get("player_name", "")))
				if n != "":
					pname = n
			player_names.append(pname)
			if pid_str == local_id:
				local_player_index = idx
			idx += 1
	
	player_count = player_names.size()
	if player_count < 1:
		player_count = 1
	
	get_node("/root/Logger").debug("Players ordered in scorecard", {
		"player_count": player_count,
		"player_names": player_names,
		"local_player_index": local_player_index,
		"function": "set_players_ordered"
	})
	
	# Clear index-based tracking (will be rebuilt from player ID tracking)
	taken_categories.clear()
	locked_scores.clear()
	
	# Initialize index-based tracking from player ID tracking
	for cat in all_categories:
		taken_categories[cat] = []
		locked_scores[cat] = []
		for i in range(player_count):
			var player_id: String = current_player_order[i] if i < current_player_order.size() else ""
			if player_id != "" and scores_by_player_id.has(player_id):
				var player_scores: Dictionary = scores_by_player_id[player_id]
				if player_scores.has(cat):
					taken_categories[cat].append(true)
					locked_scores[cat].append(player_scores[cat])
				else:
					taken_categories[cat].append(false)
					locked_scores[cat].append(-1)
			else:
				taken_categories[cat].append(false)
				locked_scores[cat].append(-1)
	
	# Rebuild the UI completely
	_build_ui()

func set_current_turn(player_idx: int) -> void:
	current_turn_player = player_idx
	_update_header_styles()

func set_current_turn_by_id(player_id: String, order: Array) -> void:
	# Use the ordered array to find the correct index
	var idx := 0
	for pid in order:
		if str(pid) == player_id:
			set_current_turn(idx)
			return
		idx += 1

func remove_player_scores(player_id: String) -> void:
	# Remove a player's scores when they leave the game
	if scores_by_player_id.has(player_id):
		scores_by_player_id.erase(player_id)

func set_player_score(player_id: String, category: String, score: int) -> void:
	# Set a score for a player by ID (before UI is built)
	# This populates scores_by_player_id so set_players_ordered can use it
	if not scores_by_player_id.has(player_id):
		scores_by_player_id[player_id] = {}
	scores_by_player_id[player_id][category] = score

func set_local_player_index(idx: int) -> void:
	local_player_index = idx

func set_previews(dice: Array[int]) -> void:
	# Show preview scores for local player's available categories
	preview_scores = ScoreLogic.score_all(dice)
	
	for cat in all_categories:
		if cat in score_cells:
			var cells: Array = score_cells[cat]
			if local_player_index < cells.size():
				var cell = cells[local_player_index]
				if not taken_categories[cat][local_player_index]:
					var score_val: int = int(preview_scores.get(cat, 0))
					cell.set_score(score_val, false, true)

func lock_category(category_name: String, score: int, player_idx: int = -1) -> void:
	if player_idx < 0:
		player_idx = local_player_index
	
	var player_id: String = ""
	if player_idx < current_player_order.size():
		player_id = current_player_order[player_idx]
	
	get_node("/root/Logger").debug("Locking category", {
		"category": category_name,
		"score": score,
		"player_idx": player_idx,
		"player_id": player_id,
		"function": "lock_category"
	})
	
	# Mark as taken in index-based tracking
	if category_name in taken_categories and player_idx < taken_categories[category_name].size():
		taken_categories[category_name][player_idx] = true
	
	# Store the score value in index-based tracking
	if category_name in locked_scores and player_idx < locked_scores[category_name].size():
		locked_scores[category_name][player_idx] = score
	
	# ALSO store by player ID for persistence across player order changes
	if player_id != "":
		if not scores_by_player_id.has(player_id):
			scores_by_player_id[player_id] = {}
		scores_by_player_id[player_id][category_name] = score
	
	# Update the cell visually
	if category_name in score_cells:
		var cells: Array = score_cells[category_name]
		if player_idx < cells.size():
			var cell = cells[player_idx]
			cell.set_score(score, true, false)
			cell.set_interactive(false)
	
	# Update totals after locking a score
	_update_totals()

func set_all_interactive(enabled: bool) -> void:
	for cat in all_categories:
		if cat in score_cells:
			var cells: Array = score_cells[cat]
			if local_player_index < cells.size():
				var cell = cells[local_player_index]
				if not taken_categories[cat][local_player_index]:
					cell.set_interactive(enabled)

func clear_previews() -> void:
	for cat in all_categories:
		if cat in score_cells:
			var cells: Array = score_cells[cat]
			if local_player_index < cells.size():
				var cell = cells[local_player_index]
				if not taken_categories[cat][local_player_index]:
					cell.set_score(-1, false, false)

func _on_cell_pressed(cat: String) -> void:
	if taken_categories.has(cat) and local_player_index < taken_categories[cat].size():
		if taken_categories[cat][local_player_index]:
			return
	emit_signal("category_chosen", cat)

func get_upper_total(player_idx: int) -> int:
	var total := 0
	for cat in UPPER_CATEGORIES:
		if locked_scores.has(cat) and player_idx < locked_scores[cat].size():
			var score_val: int = locked_scores[cat][player_idx]
			if score_val >= 0:
				total += score_val
	return total

func get_upper_bonus(player_idx: int) -> int:
	return 35 if get_upper_total(player_idx) >= 63 else 0

func get_grand_total(player_idx: int) -> int:
	var total := 0
	for cat in all_categories:
		if locked_scores.has(cat) and player_idx < locked_scores[cat].size():
			var score_val: int = locked_scores[cat][player_idx]
			if score_val >= 0:
				total += score_val
	return total + get_upper_bonus(player_idx)

func _on_icon_pressed(category_name: String) -> void:
	if info_overlay and is_instance_valid(info_overlay):
		info_overlay.queue_free()
		info_overlay = null
		return
	
	_show_category_info(category_name)

func _show_category_info(category_name: String) -> void:
	# Get the root viewport
	var root := get_tree().root
	
	# Create overlay container
	info_overlay = Control.new()
	info_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	info_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(info_overlay)
	
	# Semi-transparent dark background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	info_overlay.add_child(bg)
	
	# Find the row for this category by using the icon and cells
	var row_rect: Rect2 = Rect2()
	if category_name in category_icons and category_name in score_cells:
		var icon: Control = category_icons[category_name]
		var cells: Array = score_cells[category_name]
		var icon_rect := icon.get_global_rect()
		row_rect = icon_rect
		# Extend to include all cells
		for cell in cells:
			var cell_control: Control = cell as Control
			if cell_control:
				var cell_rect := cell_control.get_global_rect()
				row_rect = row_rect.merge(cell_rect)
	
	# Create highlight for the row (cut-out effect)
	if row_rect.size.x > 0:
		var highlight := ColorRect.new()
		highlight.position = row_rect.position
		highlight.size = row_rect.size
		highlight.color = Color(0.3, 0.25, 0.2, 1.0)  # Match row background
		info_overlay.add_child(highlight)
		
		# Add border around highlight
		var border := ReferenceRect.new()
		border.position = row_rect.position - Vector2(2, 2)
		border.size = row_rect.size + Vector2(4, 4)
		border.border_color = Color(1.0, 0.84, 0.0)  # Gold border
		border.border_width = 3.0
		border.editor_only = false
		info_overlay.add_child(border)
	
	# Create info panel on the right side
	var info_panel := PanelContainer.new()
	var panel_width := 280.0
	var panel_height := 120.0
	var screen_size := get_viewport().get_visible_rect().size
	
	# Position info panel - center it vertically, on the right side
	var panel_x := (screen_size.x - panel_width) / 2
	var panel_y := (screen_size.y - panel_height) / 2
	
	# If row is visible, position panel below/above it
	if row_rect.size.x > 0:
		panel_y = row_rect.position.y + row_rect.size.y + 20
		if panel_y + panel_height > screen_size.y - 20:
			panel_y = row_rect.position.y - panel_height - 20
	
	info_panel.position = Vector2(panel_x, panel_y)
	info_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	
	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.1, 0.95)
	style.border_color = Color(1.0, 0.84, 0.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	info_panel.add_theme_stylebox_override("panel", style)
	info_overlay.add_child(info_panel)
	
	# Add info text
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	info_panel.add_child(vbox)
	
	# Category name as title
	var title := Label.new()
	title.text = category_name.replace("_", " ").capitalize()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Tooltip/description
	var desc := Label.new()
	desc.text = CategoryIcon.CATEGORY_TOOLTIPS.get(category_name, "")
	desc.add_theme_font_size_override("font_size", 16)
	desc.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)
	
	# Tap to close hint
	var hint := Label.new()
	hint.text = "Tap anywhere to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	
	# Connect click to close
	bg.gui_input.connect(_on_overlay_input)

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if info_overlay and is_instance_valid(info_overlay):
				info_overlay.queue_free()
				info_overlay = null
