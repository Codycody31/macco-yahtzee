extends Control

# UI Color Scheme (matching MainMenu)
const PANEL_BG := Color(0.96, 0.93, 0.87)  # Cream background
const PANEL_BORDER := Color(0.25, 0.23, 0.22)  # Dark border
const BUTTON_BG := Color(0.25, 0.23, 0.22)  # Dark button
const BUTTON_BG_HOVER := Color(0.35, 0.32, 0.30)
const BUTTON_TEXT := Color(0.96, 0.93, 0.87)  # Light text
const ACCENT_COLOR := Color(0.91, 0.52, 0.45)  # Coral accent
const TITLE_COLOR := Color(0.25, 0.23, 0.22)  # Dark title
const LABEL_COLOR := Color(0.4, 0.38, 0.35)  # Muted label

@onready var main_panel: PanelContainer = %MainPanel
@onready var title_label: Label = %Title
@onready var player_name_label: Label = %PlayerNameLabel
@onready var player_name_edit: LineEdit = %PlayerName
@onready var server_url_label: Label = %ServerUrlLabel
@onready var server_url_edit: LineEdit = %ServerUrl
@onready var debug_mode_checkbox: CheckBox = %DebugModeCheckBox
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton
@onready var reset_button: Button = %ResetButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_setup_styles()
	
	# Load current values
	player_name_edit.text = GameConfig.player_name
	server_url_edit.text = GameConfig.server_url
	debug_mode_checkbox.button_pressed = GameConfig.debug_mode
	
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	reset_button.pressed.connect(_on_reset_pressed)


func _setup_styles() -> void:
	# Style the main panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_BORDER
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Style title
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	
	# Style labels
	for label in [player_name_label, server_url_label]:
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", LABEL_COLOR)
	
	# Style debug mode label
	var debug_label = get_node_or_null("%DebugModeLabel")
	if debug_label:
		debug_label.add_theme_font_size_override("font_size", 14)
		debug_label.add_theme_color_override("font_color", LABEL_COLOR)
	
	# Style debug mode checkbox text
	if debug_mode_checkbox:
		debug_mode_checkbox.add_theme_font_size_override("font_size", 14)
		debug_mode_checkbox.add_theme_color_override("font_color", TITLE_COLOR)
	
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", ACCENT_COLOR)
	
	# Style input fields
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(1, 1, 1, 0.9)
	input_style.border_color = PANEL_BORDER
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(8)
	input_style.set_content_margin_all(12)
	
	for edit in [player_name_edit, server_url_edit]:
		edit.add_theme_stylebox_override("normal", input_style)
		edit.add_theme_stylebox_override("focus", input_style)
		edit.add_theme_font_size_override("font_size", 16)
		edit.add_theme_color_override("font_color", TITLE_COLOR)
	
	# Style buttons
	_style_button(save_button, true)
	_style_button(cancel_button, false)
	_style_button(reset_button, false)


func _style_button(btn: Button, is_primary: bool) -> void:
	var style := StyleBoxFlat.new()
	var hover_style := StyleBoxFlat.new()
	var pressed_style := StyleBoxFlat.new()
	
	if is_primary:
		style.bg_color = BUTTON_BG
		hover_style.bg_color = BUTTON_BG_HOVER
		pressed_style.bg_color = ACCENT_COLOR
	else:
		style.bg_color = Color(0.7, 0.68, 0.65)
		hover_style.bg_color = Color(0.6, 0.58, 0.55)
		pressed_style.bg_color = Color(0.5, 0.48, 0.45)
	
	for s in [style, hover_style, pressed_style]:
		s.set_corner_radius_all(10)
		s.set_content_margin_all(12)
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_color_override("font_color", BUTTON_TEXT if is_primary else TITLE_COLOR)
	btn.add_theme_color_override("font_hover_color", BUTTON_TEXT if is_primary else TITLE_COLOR)
	btn.add_theme_color_override("font_pressed_color", BUTTON_TEXT)
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(100, 44)


func _on_save_pressed() -> void:
	var player_name := player_name_edit.text.strip_edges()
	if player_name == "":
		player_name = "Player"
	
	var url := server_url_edit.text.strip_edges()
	if url == "":
		url = "https://games.macco.dev/api/v1/g/yahtzee"
	
	GameConfig.player_name = player_name
	GameConfig.server_url = url
	GameConfig.debug_mode = debug_mode_checkbox.button_pressed
	GameConfig.save_settings()
	
	status_label.text = "[OK] Settings saved!"
	
	# Return to main menu after brief delay
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_cancel_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _on_reset_pressed() -> void:
	player_name_edit.text = "Player"
	server_url_edit.text = "https://games.macco.dev/api/v1/g/yahtzee"
	debug_mode_checkbox.button_pressed = false
	status_label.text = "Settings reset to defaults"
