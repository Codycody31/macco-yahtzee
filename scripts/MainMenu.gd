extends Control

# UI Color Scheme (matching GameTable)
const PANEL_BG := Color(0.96, 0.93, 0.87)  # Cream background
const PANEL_BORDER := Color(0.25, 0.23, 0.22)  # Dark border
const BUTTON_BG := Color(0.25, 0.23, 0.22)  # Dark button
const BUTTON_BG_HOVER := Color(0.35, 0.32, 0.30)
const BUTTON_TEXT := Color(0.96, 0.93, 0.87)  # Light text
const ACCENT_COLOR := Color(0.91, 0.52, 0.45)  # Coral accent
const TITLE_COLOR := Color(0.25, 0.23, 0.22)  # Dark title
const LABEL_COLOR := Color(0.4, 0.38, 0.35)  # Muted label

@onready var main_panel: PanelContainer = %MainPanel
@onready var title_icon: TextureRect = %Icon
@onready var title_label: Label = %Title
@onready var subtitle_label: Label = %Subtitle
@onready var player_name_label: Label = %PlayerNameLabel
@onready var player_name_edit: LineEdit = %PlayerName
@onready var mode_label: Label = %ModeLabel
@onready var mode_select: OptionButton = %ModeSelect
@onready var bot_count_section: VBoxContainer = %BotCountSection
@onready var bot_count_label: Label = %BotCountLabel
@onready var bot_count_select: OptionButton = %BotCountSelect
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var quit_button: Button = %QuitButton
@onready var join_popup: AcceptDialog = %JoinPopup
@onready var room_input: LineEdit = %RoomInput
@onready var info_label: Label = %InfoLabel
@onready var main_buttons: HBoxContainer = %HostButton.get_parent()
@onready var buttons_section: VBoxContainer = %HostButton.get_parent().get_parent()

var start_match_button: Button
var settings_button: Button

func _ready() -> void:
	_setup_styles()
	
	mode_select.clear()
	# mode_select.add_item("🏠 Local Hotseat")
	# mode_select.add_item("📡 P2P Host")
	# mode_select.add_item("🔗 P2P Client")
	mode_select.add_item("Online Server")
	mode_select.add_item("Practice (vs Bots)")
	mode_select.selected = 0  # Default to online server mode

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	join_popup.confirmed.connect(_on_join_popup_confirmed)
	mode_select.item_selected.connect(_on_mode_changed)
	room_input.text_changed.connect(_on_room_input_changed)
	
	# Setup bot count selector
	_setup_bot_count_selector()

	# Create start match button (hidden by default)
	start_match_button = Button.new()
	start_match_button.text = "Start Match"
	start_match_button.pressed.connect(_on_start_match_pressed)
	main_buttons.add_child(start_match_button)
	start_match_button.visible = false

	# Create settings button
	settings_button = Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_on_settings_pressed)
	# No icon - text-only button looks cleaner
	buttons_section.add_child(settings_button)

	# Load saved name from settings
	_refresh_player_name()

	# Update button visibility based on initial mode
	_on_mode_changed(mode_select.selected)

func _enter_tree() -> void:
	# Refresh player name when scene becomes active (e.g., returning from Settings)
	# Only refresh if the node is ready (onready vars initialized)
	if player_name_edit:
		_refresh_player_name()

func _refresh_player_name() -> void:
	# Reload settings to ensure we have the latest saved value
	GameConfig.load_settings()
	if player_name_edit:
		player_name_edit.text = GameConfig.player_name

func _set_button_icon(btn: Button, icon_name: String, icon_color: Color) -> void:
	var icon_texture := IconLoader.load_icon(icon_name)
	if icon_texture != null:
		btn.icon = icon_texture
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_color_override("icon_normal_color", icon_color)
		btn.add_theme_color_override("icon_hover_color", icon_color)
		btn.add_theme_color_override("icon_pressed_color", icon_color)
		# Ensure icon scales properly
		btn.expand_icon = true

func _setup_styles() -> void:
	# Style the main panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_BORDER
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Load and set the icon
	var icon_texture := load("res://icon.svg") as Texture2D
	if icon_texture == null:
		icon_texture = load("res://icon.png") as Texture2D
	if icon_texture != null:
		title_icon.texture = icon_texture
	
	# Style title
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", ACCENT_COLOR)
	
	# Style labels
	player_name_label.add_theme_font_size_override("font_size", 14)
	player_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", LABEL_COLOR)
	bot_count_label.add_theme_font_size_override("font_size", 14)
	bot_count_label.add_theme_color_override("font_color", LABEL_COLOR)
	
	# Style input field
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(1, 1, 1, 0.9)
	input_style.border_color = PANEL_BORDER
	input_style.set_border_width_all(2)
	input_style.set_corner_radius_all(8)
	input_style.set_content_margin_all(12)
	player_name_edit.add_theme_stylebox_override("normal", input_style)
	player_name_edit.add_theme_stylebox_override("focus", input_style)
	player_name_edit.add_theme_font_size_override("font_size", 16)
	player_name_edit.add_theme_color_override("font_color", TITLE_COLOR)
	
	# Style buttons
	_style_button(host_button, true)
	_style_button(join_button, true)
	_style_button(quit_button, false)
	if start_match_button:
		_style_button(start_match_button, true)
	if settings_button:
		_style_button(settings_button, false)

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
	btn.custom_minimum_size = Vector2(120, 44)

func _apply_config_from_ui() -> void:
	GameConfig.player_name = player_name_edit.text.strip_edges()
	if GameConfig.player_name == "":
		GameConfig.player_name = "Player"

	match mode_select.selected:
		0:
			GameConfig.network_mode = GameConfig.NetworkMode.SERVER
		1:
			GameConfig.network_mode = GameConfig.NetworkMode.MOCK

func _on_host_pressed() -> void:
	_apply_config_from_ui()

	get_node("/root/Logger").info("Host button pressed", {
		"player_name": GameConfig.player_name,
		"network_mode": GameConfig.NetworkMode.keys()[GameConfig.network_mode],
		"function": "_on_host_pressed"
	})

	if GameConfig.network_mode == GameConfig.NetworkMode.MOCK:
		# Practice mode: skip lobby, go straight to game
		GameConfig.is_host = true
		# Get selected bot count (1-5 bots) + 1 player = 2-6 total players
		var bot_count: int = bot_count_select.selected + 1  # 0-4 index -> 1-5 bots
		GameConfig.max_players = bot_count + 1  # bots + player
		get_node("/root/Logger").debug("Practice mode - going directly to game", {
			"bot_count": bot_count,
			"max_players": GameConfig.max_players,
			"function": "_on_host_pressed"
		})
		get_tree().change_scene_to_file("res://scenes/GameTable.tscn")
		return

	GameConfig.is_host = true
	GameConfig.room_code = ""
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_join_pressed() -> void:
	_apply_config_from_ui()
	GameConfig.is_host = false

	get_node("/root/Logger").info("Join button pressed", {
		"player_name": GameConfig.player_name,
		"network_mode": GameConfig.NetworkMode.keys()[GameConfig.network_mode],
		"function": "_on_join_pressed"
	})

	info_label.text = ""
	room_input.text = ""
	join_popup.popup_centered()

func _on_room_input_changed(new_text: String) -> void:
	# Convert input to uppercase as user types
	var cursor_pos := room_input.caret_column
	room_input.text = new_text.to_upper()
	# Restore cursor position after converting to uppercase
	room_input.caret_column = cursor_pos

func _on_join_popup_confirmed() -> void:
	var code := room_input.text.strip_edges().to_upper()
	GameConfig.room_code = code
	
	get_node("/root/Logger").info("Joining room", {
		"room_code": code,
		"player_name": GameConfig.player_name,
		"function": "_on_join_popup_confirmed"
	})
	
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()


func _setup_bot_count_selector() -> void:
	# Populate bot count options (1-5 bots)
	bot_count_select.clear()
	for i in range(1, 6):  # 1 to 5 bots
		var bot_text := "%d Bot" % i
		if i > 1:
			bot_text += "s"
		bot_count_select.add_item(bot_text)
	
	# Default to 1 bot
	bot_count_select.selected = 0
	
	# Style the bot count selector to match mode select
	bot_count_select.add_theme_font_size_override("font_size", 16)
	bot_count_select.add_theme_color_override("font_color", TITLE_COLOR)

func _on_mode_changed(index: int) -> void:
	# 0 = Online Server, 1 = Practice
	var is_practice := index == 1
	
	get_node("/root/Logger").debug("Network mode changed", {
		"mode_index": index,
		"is_practice": is_practice,
		"function": "_on_mode_changed"
	})
	
	host_button.visible = not is_practice
	join_button.visible = not is_practice
	start_match_button.visible = is_practice
	bot_count_section.visible = is_practice


func _on_start_match_pressed() -> void:
	_apply_config_from_ui()
	GameConfig.is_host = true
	
	# Get selected bot count (1-5 bots) + 1 player = 2-6 total players
	var bot_count: int = bot_count_select.selected + 1  # 0-4 index -> 1-5 bots
	GameConfig.max_players = bot_count + 1  # bots + player
	
	get_node("/root/Logger").info("Start match button pressed (practice mode)", {
		"player_name": GameConfig.player_name,
		"bot_count": bot_count,
		"max_players": GameConfig.max_players,
		"function": "_on_start_match_pressed"
	})
	
	get_tree().change_scene_to_file("res://scenes/GameTable.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Settings.tscn")
