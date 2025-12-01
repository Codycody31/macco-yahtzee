extends Control

## Optional in-game debug panel for viewing logs
## Toggle with F3 key or call show()/hide() programmatically

@onready var panel: PanelContainer = $Panel
@onready var log_display: RichTextLabel = $Panel/VBox/LogDisplay
@onready var filter_buttons: HBoxContainer = $Panel/VBox/FilterButtons
@onready var info_label: Label = $Panel/VBox/InfoLabel
@onready var clear_button: Button = $Panel/VBox/Buttons/ClearButton
@onready var close_button: Button = $Panel/VBox/Buttons/CloseButton

var visible_log_levels: Array[int] = [0, 1, 2, 3]  # All levels by default
var panel_visible: bool = false

const LEVEL_COLORS := {
	0: Color(0.7, 0.7, 0.7),  # DEBUG - Gray
	1: Color(0.9, 0.9, 0.9),    # INFO - Light gray
	2: Color(1.0, 0.84, 0.0), # WARNING - Yellow
	3: Color(1.0, 0.3, 0.3)     # ERROR - Red
}

const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]

func _get_logger() -> Node:
	## Helper to get Logger node (returns GameLogger instance)
	## The actual type is GameLogger, but using Node to avoid linter cache issues
	if has_node("/root/Logger"):
		return get_node("/root/Logger")
	return null

func _ready() -> void:
	visible = false
	# Ensure we're on top
	z_index = 100
	
	# Wait for tree to be ready before setting up UI
	await get_tree().process_frame
	_setup_ui()
	_setup_filters()
	
	# Connect to Logger
	var logger = _get_logger()
	if logger != null:
		logger.register_debug_panel(self)
		logger.log_added.connect(_on_log_added)
	
	# Set up keyboard shortcut (F3)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			toggle()

func _setup_ui() -> void:
	# Ensure panel fills screen with proper anchors
	# (Anchors should be set in scene, but ensure they're correct here too)
	if not is_inside_tree():
		await ready
	
	# Style panel
	if panel:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
		style.border_color = Color(0.3, 0.3, 0.4)
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)
	
	# Style log display
	if log_display:
		log_display.bbcode_enabled = true
		log_display.scroll_following = true
		var log_style := StyleBoxFlat.new()
		log_style.bg_color = Color(0.05, 0.05, 0.08, 1.0)
		log_style.set_corner_radius_all(4)
		log_style.set_content_margin_all(8)
		log_display.add_theme_stylebox_override("normal", log_style)
		log_display.add_theme_font_size_override("normal_font_size", 12)
	
	# Style buttons
	if clear_button:
		clear_button.text = "Clear"
		clear_button.pressed.connect(_on_clear_pressed)
	
	if close_button:
		close_button.text = "Close (F3)"
		close_button.pressed.connect(hide_panel)

func _setup_filters() -> void:
	if not filter_buttons:
		return
	
	# Create filter buttons for each log level
	for level in range(4):
		var btn := CheckBox.new()
		btn.text = LEVEL_NAMES[level]
		btn.button_pressed = true  # All enabled by default
		btn.toggled.connect(_on_filter_toggled.bind(level))
		filter_buttons.add_child(btn)

func _on_filter_toggled(toggled_on: bool, level: int) -> void:
	if toggled_on:
		if not visible_log_levels.has(level):
			visible_log_levels.append(level)
	else:
		visible_log_levels.erase(level)
	
	_update_logs()

func _on_log_added(_level: int, _message: String, _context: Dictionary) -> void:
	# Only update if panel is visible
	if panel_visible:
		_update_logs()

func _update_logs() -> void:
	if not log_display:
		return
	
	log_display.clear()
	
	var logger = _get_logger()
	if logger == null:
		return
	
	var logs: Array[Dictionary] = logger.get_panel_logs()
	var count := 0
	
	for log_entry in logs:
		var level: int = log_entry.get("level", 0)  # Default to DEBUG
		
		# Filter by level
		if not visible_log_levels.has(level):
			continue
		
		var formatted_msg: String = log_entry.get("message", "")
		var color: Color = LEVEL_COLORS.get(level, Color.WHITE)
		
		# Format with color (formatted_msg already contains [LEVEL] [TIME] prefix)
		var colored_msg := "[color=#%s]%s[/color]" % [
			_color_to_hex(color),
			formatted_msg
		]
		
		log_display.append_text(colored_msg + "\n")
		count += 1
	
	# Update info label
	if info_label:
		info_label.text = "Showing %d logs (filtered)" % count

func _color_to_hex(color: Color) -> String:
	var r := int(color.r * 255)
	var g := int(color.g * 255)
	var b := int(color.b * 255)
	return "%02x%02x%02x" % [r, g, b]

func _on_clear_pressed() -> void:
	var logger = _get_logger()
	if logger != null:
		logger.clear_panel_logs()
		_update_logs()

func show_panel() -> void:
	panel_visible = true
	visible = true
	_update_logs()
	_update_info()

func hide_panel() -> void:
	panel_visible = false
	visible = false

func toggle() -> void:
	if panel_visible:
		hide_panel()
	else:
		show_panel()

func _update_info() -> void:
	if not info_label:
		return
	
	var info_parts: Array[String] = []
	
	if has_node("/root/GameConfig"):
		if GameConfig.room_code != "":
			info_parts.append("Room: %s" % GameConfig.room_code)
		if GameConfig.player_id != "":
			info_parts.append("Player: %s" % GameConfig.player_id)
		info_parts.append("Mode: %s" % GameConfig.NetworkMode.keys()[GameConfig.network_mode])
	
	# GameNetwork connection state could be added here if needed
	
	if info_parts.size() > 0:
		info_label.text = " | ".join(info_parts)
	else:
		info_label.text = "Debug Panel - Press F3 to toggle"
