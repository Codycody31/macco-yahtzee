extends Control

# UI Color Scheme (matching GameTable and MainMenu)
const PANEL_BG := Color(0.96, 0.93, 0.87)  # Cream background
const PANEL_BORDER := Color(0.25, 0.23, 0.22)  # Dark border
const BUTTON_BG := Color(0.25, 0.23, 0.22)  # Dark button
const BUTTON_BG_HOVER := Color(0.35, 0.32, 0.30)
const BUTTON_TEXT := Color(0.96, 0.93, 0.87)  # Light text
const ACCENT_COLOR := Color(0.91, 0.52, 0.45)  # Coral accent
const READY_COLOR := Color(0.55, 0.78, 0.73)  # Teal for ready
const TITLE_COLOR := Color(0.25, 0.23, 0.22)  # Dark title
const LABEL_COLOR := Color(0.4, 0.38, 0.35)  # Muted label

@onready var main_panel: PanelContainer = %MainPanel
@onready var title_label: Label = %Title
@onready var players_header: Label = %PlayersHeader
@onready var mode_label: Label = %ModeLabel
@onready var room_label: Label = %RoomLabel
@onready var players_list: ItemList = %PlayersList
@onready var ready_button: Button = %ReadyButton
@onready var start_button: Button = %StartButton
@onready var leave_button: Button = %LeaveButton
@onready var status_log: RichTextLabel = %StatusLog

var players: Dictionary = {} # player_id -> {name, ready, is_local}
var local_player_id: String = ""
var is_ready: bool = false
var _intentional_leave: bool = false

func _ready() -> void:
	_setup_styles()
	_update_mode_labels()

	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	get_node("/root/Logger").info("Lobby initialized", {
		"is_host": GameConfig.is_host,
		"room_code": GameConfig.room_code,
		"player_name": GameConfig.player_name,
		"network_mode": GameConfig.NetworkMode.keys()[GameConfig.network_mode],
		"function": "_ready"
	})
	
	GameNetwork.setup_network()
	GameNetwork.game_event_received.connect(_on_game_event)
	GameNetwork.connection_state_changed.connect(_on_connection_state_changed)

	# Connect to the server
	var connect_mode := "create" if GameConfig.is_host else "join"
	get_node("/root/Logger").debug("Connecting to match", {
		"mode": connect_mode,
		"room_code": GameConfig.room_code,
		"player_name": GameConfig.player_name,
		"function": "_ready"
	})
	
	GameNetwork.connect_to_match({
		"mode": connect_mode,
		"room_code": GameConfig.room_code,
		"player_name": GameConfig.player_name
	})

func _setup_styles() -> void:
	# Style the main panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_BORDER
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	
	# Style title
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	
	# Style section headers
	players_header.add_theme_font_size_override("font_size", 16)
	players_header.add_theme_color_override("font_color", LABEL_COLOR)
	
	# Style info labels
	mode_label.add_theme_font_size_override("font_size", 13)
	mode_label.add_theme_color_override("font_color", LABEL_COLOR)
	room_label.add_theme_font_size_override("font_size", 13)
	room_label.add_theme_color_override("font_color", LABEL_COLOR)
	
	# Style players list
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(1, 1, 1, 0.5)
	list_style.border_color = PANEL_BORDER
	list_style.set_border_width_all(1)
	list_style.set_corner_radius_all(8)
	list_style.set_content_margin_all(8)
	players_list.add_theme_stylebox_override("panel", list_style)
	players_list.add_theme_font_size_override("font_size", 15)
	
	# Style status log
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0, 0, 0, 0.1)
	log_style.set_corner_radius_all(8)
	log_style.set_content_margin_all(8)
	status_log.add_theme_stylebox_override("normal", log_style)
	status_log.add_theme_font_size_override("normal_font_size", 12)
	
	# Style buttons
	_style_button(ready_button, false)
	_style_button(start_button, true)
	_style_button(leave_button, false)
	
	_update_ready_button_style()

func _style_button(btn: Button, is_primary: bool) -> void:
	var style := StyleBoxFlat.new()
	var hover_style := StyleBoxFlat.new()
	var pressed_style := StyleBoxFlat.new()
	var disabled_style := StyleBoxFlat.new()
	
	if is_primary:
		style.bg_color = BUTTON_BG
		hover_style.bg_color = BUTTON_BG_HOVER
		pressed_style.bg_color = ACCENT_COLOR
		disabled_style.bg_color = Color(0.5, 0.48, 0.45)
	else:
		style.bg_color = Color(0.7, 0.68, 0.65)
		hover_style.bg_color = Color(0.6, 0.58, 0.55)
		pressed_style.bg_color = Color(0.5, 0.48, 0.45)
		disabled_style.bg_color = Color(0.8, 0.78, 0.75)
	
	for s in [style, hover_style, pressed_style, disabled_style]:
		s.set_corner_radius_all(10)
		s.set_content_margin_all(12)
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.add_theme_color_override("font_color", BUTTON_TEXT if is_primary else TITLE_COLOR)
	btn.add_theme_color_override("font_hover_color", BUTTON_TEXT if is_primary else TITLE_COLOR)
	btn.add_theme_color_override("font_pressed_color", BUTTON_TEXT)
	btn.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.55))
	btn.add_theme_font_size_override("font_size", 15)
	btn.custom_minimum_size = Vector2(110, 42)

func _update_ready_button_style() -> void:
	var style := StyleBoxFlat.new()
	var hover_style := StyleBoxFlat.new()
	
	if is_ready:
		style.bg_color = READY_COLOR
		hover_style.bg_color = READY_COLOR.lightened(0.1)
		ready_button.text = "Ready!"
		ready_button.icon = null  # Remove icon, use text only
	else:
		style.bg_color = Color(0.7, 0.68, 0.65)
		hover_style.bg_color = Color(0.6, 0.58, 0.55)
		ready_button.text = "Ready"
		ready_button.icon = null  # Remove icon, use text only
	
	for s in [style, hover_style]:
		s.set_corner_radius_all(10)
		s.set_content_margin_all(12)
	
	ready_button.add_theme_stylebox_override("normal", style)
	ready_button.add_theme_stylebox_override("hover", hover_style)

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

func _update_mode_labels() -> void:
	var mode_text := "Online"
	if GameConfig.network_mode == GameConfig.NetworkMode.MOCK:
		mode_text = "Practice"

	mode_label.text = mode_text
	room_label.text = "Creating..." if GameConfig.room_code == "" else "Room: " + GameConfig.room_code

func _on_connection_state_changed(state: int, error: int) -> void:
	match state:
		GameNetwork.ConnectionState.CONNECTED:
			get_node("/root/Logger").info("Connected to server", {
				"room_code": GameConfig.room_code,
				"player_name": GameConfig.player_name,
				"is_host": GameConfig.is_host,
				"function": "_on_connection_state_changed"
			})
			status_log.append_text("[color=#8dc7be]Connected[/color]\n")
			# Update room label with the actual room code from server
			_update_mode_labels()
			# For server mode, get player_id from the network and send join event
			if GameConfig.network_mode == GameConfig.NetworkMode.SERVER:
				local_player_id = GameNetwork.get_player_id()
				GameConfig.player_id = local_player_id
				get_node("/root/Logger").debug("Got player ID from server", {
					"player_id": local_player_id,
					"room_code": GameConfig.room_code,
					"function": "_on_connection_state_changed"
				})
				# If we're a viewer, we should go directly to game table
				# Wait a moment for initial events to arrive
				await get_tree().create_timer(0.3).timeout
				if GameConfig.is_viewer:
					get_node("/root/Logger").info("Entering viewer mode - transitioning to game table", {
						"player_id": local_player_id,
						"room_code": GameConfig.room_code,
						"function": "_on_connection_state_changed"
					})
					# Game has already started, go directly to game table
					# The server will send us the current game state via events
					get_tree().change_scene_to_file("res://scenes/GameTable.tscn")
					return
				_send_join_event()
		GameNetwork.ConnectionState.FAILED:
			get_node("/root/Logger").error("Connection failed", {
				"error": error,
				"room_code": GameConfig.room_code,
				"player_name": GameConfig.player_name,
				"function": "_on_connection_state_changed"
			})
			status_log.append_text("[color=#e8736b]✗ Connection failed: %d[/color]\n" % error)
		GameNetwork.ConnectionState.DISCONNECTED:
			# Check if disconnection was unexpected
			if not _intentional_leave and error == ERR_CONNECTION_ERROR:
				# Unexpected disconnection - show error overlay
				get_node("/root/Logger").error("Unexpected disconnection", {
					"error": error,
					"room_code": GameConfig.room_code,
					"function": "_on_connection_state_changed"
				})
				_show_error_overlay("Connection Lost", "You have been disconnected from the server.")
			else:
				get_node("/root/Logger").info("Disconnected", {
					"intentional": _intentional_leave,
					"error": error,
					"room_code": GameConfig.room_code,
					"function": "_on_connection_state_changed"
				})
				status_log.append_text("[color=#e8736b]✗ Disconnected[/color]\n")

func _send_join_event() -> void:
	# Server already broadcasts PLAYER_JOINED when WebSocket connects
	# This function is kept for potential future use but is a no-op now
	pass

func _on_game_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	
	get_node("/root/Logger").debug("Lobby event received", {
		"event_type": event_type,
		"room_code": GameConfig.room_code,
		"player_id": local_player_id,
		"function": "_on_game_event"
	})
	
	match event_type:
		"PLAYER_JOINED":
			_handle_player_joined(event)
		"PLAYER_READY":
			_handle_player_ready(event)
		"PLAYER_LEFT":
			_handle_player_left(event)
		"ROOM_ENDED":
			_handle_room_ended(event)
		"GAME_START", "GAME_STARTED":
			_handle_game_start(event)
		"VIEWER_MODE":
			_handle_viewer_mode(event)
		"GAME_STATE":
			_handle_game_state(event)
		_:
			get_node("/root/Logger").debug("Unhandled lobby event", {
				"event_type": event_type,
				"function": "_on_game_event"
			})

func _handle_player_joined(event: Dictionary) -> void:
	var pid := str(event.get("player_id", ""))
	var player_name: String = str(event.get("name", "Player"))
	var is_host_flag: bool = bool(event.get("is_host", false))
	
	# Trust the server's is_host flag
	if pid == local_player_id and is_host_flag:
		GameConfig.is_host = true
		get_node("/root/Logger").debug("Local player is host", {
			"player_id": local_player_id,
			"room_code": GameConfig.room_code,
			"function": "_handle_player_joined"
		})
	
	if not players.has(pid):
		get_node("/root/Logger").info("Player joined lobby", {
			"player_id": pid,
			"player_name": player_name,
			"is_host": is_host_flag,
			"is_local": pid == local_player_id,
			"room_code": GameConfig.room_code,
			"function": "_handle_player_joined"
		})
		players[pid] = {
			"name": player_name,
			"ready": false,
			"is_local": pid == local_player_id
		}
		status_log.append_text("[color=#8dc7be]%s joined[/color]\n" % player_name)
		_refresh_players_list()

func _handle_player_ready(event: Dictionary) -> void:
	var pid := str(event.get("player_id", ""))
	var ready_val = event.get("ready", false)
	var is_ready_now: bool = false
	
	# Handle ready value - could be bool or other type from JSON
	if typeof(ready_val) == TYPE_BOOL:
		is_ready_now = ready_val
	elif typeof(ready_val) == TYPE_STRING:
		is_ready_now = ready_val.to_lower() == "true"
	else:
		is_ready_now = bool(ready_val)
	
	if players.has(pid):
		get_node("/root/Logger").info("Player ready state changed", {
			"player_id": pid,
			"player_name": players[pid].name,
			"ready": is_ready_now,
			"room_code": GameConfig.room_code,
			"function": "_handle_player_ready"
		})
		players[pid].ready = is_ready_now
		var ready_text := "[color=#8dc7be]ready[/color]" if players[pid].ready else "[color=#c7a88d]not ready[/color]"
		status_log.append_text("%s is %s\n" % [players[pid].name, ready_text])
		_refresh_players_list()

func _handle_game_start(event: Dictionary) -> void:
	get_node("/root/Logger").info("Game start event received - transitioning to game table", {
		"room_code": GameConfig.room_code,
		"player_id": local_player_id,
		"player_count": players.size(),
		"function": "_handle_game_start"
	})
	GameConfig.game_start_event = event
	get_tree().change_scene_to_file("res://scenes/GameTable.tscn")

func _handle_viewer_mode(_event: Dictionary) -> void:
	# Set viewer flag when VIEWER_MODE event is received
	GameConfig.is_viewer = true
	get_node("/root/Logger").info("VIEWER_MODE event received in lobby", {
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_handle_viewer_mode"
	})
	# If we're already transitioning, this is fine - GameTable will handle it
	# Otherwise, we'll transition when connection state changes

func _handle_game_state(event: Dictionary) -> void:
	# Store game state event for GameTable to process
	GameConfig.game_state_event = event
	get_node("/root/Logger").info("GAME_STATE event received in lobby - storing for GameTable", {
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"has_players": event.has("players"),
		"has_player_list": event.has("player_list"),
		"function": "_handle_game_state"
	})
	# If we're a viewer and haven't transitioned yet, transition now
	if GameConfig.is_viewer and get_tree().current_scene == self:
		# Wait a moment for any other events to arrive
		await get_tree().create_timer(0.2).timeout
		get_node("/root/Logger").info("Transitioning to game table with stored game state", {
			"player_id": local_player_id,
			"room_code": GameConfig.room_code,
			"function": "_handle_game_state"
		})
		get_tree().change_scene_to_file("res://scenes/GameTable.tscn")

func _refresh_players_list() -> void:
	players_list.clear()
	var idx := 0
	for pid in players.keys():
		var p = players[pid]
		var ready_icon := ""  # Icons will be shown via button icons
		var you_tag := " (you)" if p.is_local else ""
		var text: String = ready_icon + p.name + you_tag
		players_list.add_item(text)
		
		# Color the item based on ready state
		if p.ready:
			players_list.set_item_custom_fg_color(idx, READY_COLOR.darkened(0.2))
		else:
			players_list.set_item_custom_fg_color(idx, LABEL_COLOR)
		idx += 1

	# Only host can start
	start_button.disabled = not GameConfig.is_host

func _on_ready_pressed() -> void:
	is_ready = not is_ready
	_update_ready_button_style()
	
	get_node("/root/Logger").info("Ready button pressed", {
		"player_id": local_player_id,
		"ready": is_ready,
		"room_code": GameConfig.room_code,
		"function": "_on_ready_pressed"
	})
	
	# Update local player's ready state immediately (optimistic update)
	if players.has(local_player_id):
		players[local_player_id].ready = is_ready
		_refresh_players_list()
	
	var ev := {
		"type": "PLAYER_READY",
		"player_id": local_player_id,
		"ready": is_ready
	}
	GameNetwork.send_game_event(ev)

func _on_start_pressed() -> void:
	if not GameConfig.is_host:
		get_node("/root/Logger").warn("Start button pressed but not host", {
			"player_id": local_player_id,
			"room_code": GameConfig.room_code,
			"function": "_on_start_pressed"
		})
		return

	# Check min players / all ready
	var ready_count := 0
	for p in players.values():
		if p.ready:
			ready_count += 1

	if ready_count < GameConfig.min_players:
		get_node("/root/Logger").warn("Cannot start game: insufficient ready players", {
			"ready_count": ready_count,
			"min_players": GameConfig.min_players,
			"total_players": players.size(),
			"room_code": GameConfig.room_code,
			"function": "_on_start_pressed"
		})
		status_log.append_text("[color=#c7a88d][!] Need at least %d ready players[/color]\n" % GameConfig.min_players)
		return

	get_node("/root/Logger").info("Starting game", {
		"player_id": local_player_id,
		"ready_count": ready_count,
		"total_players": players.size(),
		"room_code": GameConfig.room_code,
		"function": "_on_start_pressed"
	})

	var start_event := {
		"type": "GAME_START",
		"players": players,
		"first_player_id": players.keys()[0]
	}
	GameNetwork.send_game_event(start_event)

func _handle_player_left(event: Dictionary) -> void:
	var pid := str(event.get("player_id", ""))
	var player_name: String = str(event.get("player_name", "Player"))
	var was_host: bool = bool(event.get("is_host", false))
	
	if players.has(pid):
		get_node("/root/Logger").info("Player left lobby", {
			"player_id": pid,
			"player_name": players[pid].name,
			"was_host": was_host,
			"remaining_players": players.size() - 1,
			"room_code": GameConfig.room_code,
			"function": "_handle_player_left"
		})
		status_log.append_text("[color=#e8736b]<< %s left[/color]\n" % players[pid].name)
		players.erase(pid)
		_refresh_players_list()
		
		# Check if only 1 player remains
		if players.size() == 1:
			get_node("/root/Logger").warn("Only 1 player remaining in lobby", {
				"room_code": GameConfig.room_code,
				"function": "_handle_player_left"
			})
			status_log.append_text("[color=#c7a88d][!] Only 1 player remaining[/color]\n")

func _handle_room_ended(event: Dictionary) -> void:
	var reason: String = str(event.get("reason", "unknown"))
	
	get_node("/root/Logger").warn("Room ended", {
		"reason": reason,
		"room_code": GameConfig.room_code,
		"player_id": local_player_id,
		"function": "_handle_room_ended"
	})
	
	var title: String = "Room Ended"
	var message: String = "The room has been closed."
	
	match reason:
		"host_disconnected":
			title = "Host Disconnected"
			message = "The host has left the room. The game has ended."
		"insufficient_players":
			title = "Insufficient Players"
			message = "Not enough players remain to continue the game."
		_:
			title = "Room Ended"
			message = "The room has been closed."
	
	_show_error_overlay(title, message)

func _show_error_overlay(title: String, message: String) -> void:
	# Disable all buttons
	ready_button.disabled = true
	start_button.disabled = true
	leave_button.disabled = true
	
	# Create overlay
	var overlay := ColorRect.new()
	overlay.name = "ErrorOverlay"
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.custom_minimum_size = Vector2(400, 200)
	center.add_child(vbox)
	
	# Title
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	# Message
	var message_label := Label.new()
	message_label.text = message
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message_label)
	
	# Return to Main Menu button
	var return_button := Button.new()
	return_button.text = "Return to Main Menu"
	return_button.custom_minimum_size = Vector2(200, 48)
	return_button.pressed.connect(func():
		_intentional_leave = true
		GameNetwork.disconnect_from_match()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	_style_button(return_button, true)
	vbox.add_child(return_button)
	
	# Center the vbox
	vbox.position = Vector2(-vbox.size.x / 2, -vbox.size.y / 2)

func _on_leave_pressed() -> void:
	get_node("/root/Logger").info("Leaving lobby", {
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_on_leave_pressed"
	})
	_intentional_leave = true
	GameNetwork.disconnect_from_match()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
