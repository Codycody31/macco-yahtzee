extends Control

const DiceSlotScene := preload("res://scenes/DiceSlot.tscn")
const ScorecardPanelScene := preload("res://scenes/ScorecardPanel.tscn")

# UI Color Scheme
const BG_COLOR := Color(0.91, 0.52, 0.45)  # Coral/salmon background
const BUTTON_BG := Color(0.25, 0.23, 0.22)  # Dark button background
const BUTTON_TEXT := Color(0.96, 0.93, 0.87)  # Light button text
const INDICATOR_BG := Color(0.25, 0.23, 0.22)  # Dark indicator background

@onready var mode_label: Label = %ModeLabel
@onready var room_label: Label = %RoomLabel
@onready var room_code_label: Label = %RoomCodeLabel
@onready var current_player_label: Label = %CurrentPlayerLabel
@onready var rolls_label: Label = %RollsLabel
@onready var leave_button: Button = %LeaveButton
@onready var dice_row: HBoxContainer = %DiceRow
@onready var roll_button: Button = %RollButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var roll_count_label: Label = %RollCountLabel
@onready var turn_indicator: PanelContainer = %TurnIndicator
@onready var start_game_button: Button = null  # Optional, created for mock mode
@onready var players_list: ItemList = %PlayersList
@onready var info_log: RichTextLabel = %InfoLog
@onready var scorecard_container: Control = %ScorecardContainer
@onready var right_panel: VBoxContainer = $MainVBox/CenterArea/RightPanel
@onready var bottom_area: VBoxContainer = $MainVBox/BottomArea
@onready var buttons_row: HBoxContainer = %RollButton.get_parent()
@onready var debug_panel: Control = $DebugPanel

var dice_slots: Array = []
var dice_values: Array[int] = [0,0,0,0,0]  # 0 = placeholder star, not rolled yet
var rolls_left: int = 3
var local_player_id: String = ""
var current_player_id: String = ""
var players: Dictionary = {} # id -> {name, total_score}
var player_order: Array = []  # Ordered list of player IDs from server
var scorecard_panel: Node
var _pending_game_start_event: Dictionary = {}  # Store event while showing animation
var _intentional_leave: bool = false
var _game_state_processed: bool = false  # Track if we've already processed GAME_STATE

func _ready() -> void:
	_setup_ui_styles()
	_create_dice()
	_create_scorecard()

	roll_button.pressed.connect(_on_roll_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	end_turn_button.disabled = true
	roll_button.disabled = true  # Disabled until game starts and it's our turn
	_update_rolls_label()
	_update_room_code_label()

	GameNetwork.game_event_received.connect(_on_game_event)
	GameNetwork.connection_state_changed.connect(_on_connection_state_changed)

	# Get players populated by Lobby; if needed, set local id
	if GameConfig.player_id != "":
		local_player_id = GameConfig.player_id
	elif local_player_id == "":
		local_player_id = GameConfig.player_name + "_" + str(randi() % 100000)

	current_player_id = local_player_id
	
	# If we're a viewer, disable controls immediately
	if GameConfig.is_viewer:
		_disable_all_controls()
		# Ensure leave button is enabled for viewers
		leave_button.disabled = false
		_show_viewer_overlay()
		info_log.append_text("[color=#c7a88d]You are viewing this game. You cannot interact.[/color]\n")

	# Initialize game based on network mode
	match GameConfig.network_mode:
		GameConfig.NetworkMode.MOCK:
			# Setup mock network and connect
			GameNetwork.setup_network()
			GameNetwork.connect_to_match({})
			# Auto-start the game after a brief delay to let everything initialize
			await get_tree().create_timer(0.1).timeout
			GameNetwork.send_game_event({"type": "START_GAME"})
		GameConfig.NetworkMode.SERVER:
			# Check if we have a pending game state event (for viewers joining mid-game)
			if not GameConfig.game_state_event.is_empty():
				get_node("/root/Logger").info("Processing stored GAME_STATE event", {
					"player_id": local_player_id,
					"is_viewer": GameConfig.is_viewer,
					"function": "_ready"
				})
				_handle_game_state(GameConfig.game_state_event)
				_game_state_processed = true
				GameConfig.game_state_event = {} # Clear it
			# Check if we have a pending start event from Lobby
			elif not GameConfig.game_start_event.is_empty():
				_handle_game_start(GameConfig.game_start_event)
				GameConfig.game_start_event = {} # Clear it
	
	# Handle initial layout and resize events
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	
	# Setup debug panel visibility based on debug_mode setting
	if debug_panel:
		if GameConfig.debug_mode:
			# Debug mode enabled - panel can be toggled with F3
			# Start hidden but allow F3 toggle
			debug_panel.visible = false
		else:
			# Debug mode disabled - hide panel and disable F3 toggle
			debug_panel.visible = false
			debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Disable input processing to prevent F3 toggle
			debug_panel.set_process_input(false)

func _on_viewport_resized() -> void:
	var viewport_size = get_viewport_rect().size
	var is_landscape = viewport_size.x > viewport_size.y * 1.2
	
	if is_landscape:
		_set_landscape_layout()
	else:
		_set_portrait_layout()

func _set_landscape_layout() -> void:
	# Move dice and buttons to RightPanel if not already there
	if dice_row.get_parent() != right_panel:
		dice_row.reparent(right_panel)
		buttons_row.reparent(right_panel)
		# Ensure they are at the bottom
		right_panel.move_child(dice_row, -1)
		right_panel.move_child(buttons_row, -1)
	
	right_panel.visible = true
	bottom_area.visible = false
	scorecard_container.custom_minimum_size.y = 0 # Let it shrink if needed

func _set_portrait_layout() -> void:
	# Move dice and buttons back to BottomArea if not already there
	if dice_row.get_parent() != bottom_area:
		dice_row.reparent(bottom_area)
		buttons_row.reparent(bottom_area)
	
	right_panel.visible = false
	bottom_area.visible = true
	scorecard_container.custom_minimum_size.y = 400 # Ensure some height in portrait

func _setup_ui_styles() -> void:
	# Style the turn indicator panel
	var indicator_style := StyleBoxFlat.new()
	indicator_style.bg_color = INDICATOR_BG
	indicator_style.set_corner_radius_all(20)
	indicator_style.set_content_margin_all(12)
	turn_indicator.add_theme_stylebox_override("panel", indicator_style)
	
	# Style the rolls label in indicator
	rolls_label.add_theme_font_size_override("font_size", 24)
	rolls_label.add_theme_color_override("font_color", BUTTON_TEXT)
	
	# Style the room code label
	room_code_label.add_theme_font_size_override("font_size", 16)
	room_code_label.add_theme_color_override("font_color", BUTTON_TEXT)
	
	# Style the roll count label at bottom - make it circular
	roll_count_label.add_theme_font_size_override("font_size", 28)
	roll_count_label.add_theme_color_override("font_color", Color.WHITE)
	# Create circular background for roll count
	var count_bg_style := StyleBoxFlat.new()
	count_bg_style.bg_color = BUTTON_BG
	count_bg_style.set_corner_radius_all(20)  # Half of 40px size for perfect circle
	count_bg_style.set_content_margin_all(8)
	roll_count_label.add_theme_stylebox_override("normal", count_bg_style)
	# Ensure it stays circular (Label doesn't have custom_maximum_size)
	roll_count_label.custom_minimum_size = Vector2(40, 40)
	roll_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	roll_count_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	roll_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Style buttons with circular/pill shape
	_style_icon_button(leave_button, 36)
	_style_icon_button(roll_button, 56)
	_style_icon_button(end_turn_button, 40)
	
	# Add icons to buttons
	_set_button_icon(leave_button, "close", BUTTON_TEXT)
	_set_button_icon(roll_button, "dice", BUTTON_TEXT)
	_set_button_icon(end_turn_button, "close", BUTTON_TEXT)
	
	# Clear text from icon buttons
	leave_button.text = ""
	roll_button.text = ""
	end_turn_button.text = ""

func _style_icon_button(btn: Button, size_val: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BUTTON_BG
	style.set_corner_radius_all(int(size_val / 2))
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", BUTTON_TEXT)
	btn.add_theme_color_override("font_hover_color", BUTTON_TEXT)
	btn.add_theme_color_override("font_pressed_color", BUTTON_TEXT)
	# Set minimum size to ensure proper circle size
	btn.custom_minimum_size = Vector2(size_val, size_val)
	# Prevent stretching by using shrink flags
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

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

func _create_dice() -> void:
	for i in range(5):
		var ds = DiceSlotScene.instantiate()
		ds.interactive = false  # Start disabled until game starts and it's our turn
		dice_row.add_child(ds)
		dice_slots.append(ds)

func _create_scorecard() -> void:
	scorecard_panel = ScorecardPanelScene.instantiate()
	scorecard_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	scorecard_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scorecard_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scorecard_container.add_child(scorecard_panel)
	scorecard_panel.category_chosen.connect(_on_category_chosen)
	
	# Set up container to expand - wider for desktop
	scorecard_container.custom_minimum_size = Vector2(320, 300)
	scorecard_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func _create_start_game_button() -> void:
	start_game_button = Button.new()
	start_game_button.text = "Start Game"
	start_game_button.custom_minimum_size = Vector2(150, 40)
	start_game_button.pressed.connect(_on_start_game_pressed)
	# Add it next to roll button
	roll_button.get_parent().add_child(start_game_button)
	roll_button.get_parent().move_child(start_game_button, 0)

func _on_start_game_pressed() -> void:
	if start_game_button:
		start_game_button.queue_free()
		start_game_button = null
	GameNetwork.send_game_event({"type": "START_GAME"})

func _on_connection_state_changed(state: int, error: int) -> void:
	# Only handle unexpected disconnections during game (not in mock mode)
	if GameConfig.network_mode == GameConfig.NetworkMode.SERVER:
		if state == GameNetwork.ConnectionState.DISCONNECTED:
			if not _intentional_leave and error == ERR_CONNECTION_ERROR:
				# Unexpected disconnection during game
				get_node("/root/Logger").error("Unexpected disconnection during game", {
					"error": error,
					"player_id": local_player_id,
					"room_code": GameConfig.room_code,
					"function": "_on_connection_state_changed"
				})
				_show_error_overlay("Connection Lost", "You have been disconnected from the server. The game cannot continue.")
				_disable_all_controls()
			else:
				get_node("/root/Logger").info("Disconnected from game", {
					"intentional": _intentional_leave,
					"error": error,
					"player_id": local_player_id,
					"room_code": GameConfig.room_code,
					"function": "_on_connection_state_changed"
				})

func _on_game_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	
	get_node("/root/Logger").debug("Game event received", {
		"event_type": event_type,
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_on_game_event"
	})
	
	match event_type:
		"PLAYER_JOINED":
			_handle_player_joined(event)
		"PLAYER_LEFT":
			_handle_player_left(event)
		"ROOM_ENDED":
			_handle_room_ended(event)
		"VIEWER_MODE":
			_handle_viewer_mode(event)
		"GAME_STATE":
			# Only process GAME_STATE if we haven't already processed one
			# This prevents duplicate processing when events arrive via WebSocket
			if not _game_state_processed:
				_handle_game_state(event)
				_game_state_processed = true
			else:
				get_node("/root/Logger").debug("Ignoring duplicate GAME_STATE event", {
					"player_id": local_player_id,
					"function": "_on_game_event"
				})
		"GAME_START", "GAME_STARTED":
			_handle_game_start(event)
		"ROLL_RESULT":
			_handle_roll_result(event)
		"CATEGORY_CHOSEN", "SCORE_UPDATE":
			_handle_category_chosen(event)
		"TURN_CHANGE", "TURN_CHANGED":
			_handle_turn_change(event)
		"GAME_END":
			_handle_game_end(event)
		_:
			get_node("/root/Logger").debug("Unhandled game event type", {
				"event_type": event_type,
				"function": "_on_game_event"
			})

func _handle_viewer_mode(_event: Dictionary) -> void:
	get_node("/root/Logger").info("Entering viewer mode", {
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_handle_viewer_mode"
	})
	GameConfig.is_viewer = true
	_disable_all_controls()
	# Ensure leave button is enabled for viewers
	leave_button.disabled = false
	info_log.append_text("[color=#c7a88d]You are viewing this game. You cannot interact.[/color]\n")
	_show_viewer_overlay()

func _handle_game_state(event: Dictionary) -> void:
	# Handle receiving current game state when joining as viewer
	# This is similar to GAME_STARTED but for viewers joining mid-game
	# ALL data comes from the WebSocket - we must parse everything from the event
	
	get_node("/root/Logger").debug("GAME_STATE event received", {
		"event_keys": event.keys(),
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"event_type": "GAME_STATE",
		"function": "_handle_game_state"
	})
	
	var event_players: Variant = event.get("players", null)
	var player_list: Variant = event.get("player_list", null)
	var turn_order: Variant = event.get("turn_order", [])
	var current_player: Variant = event.get("current_player", "")
	var dice: Variant = event.get("dice", [])
	var rolls_left_val: Variant = event.get("rolls_left", 3)
	
	get_node("/root/Logger").debug("Parsing game state data", {
		"turn_order": turn_order,
		"player_list_type": typeof(player_list),
		"player_list_size": player_list.size() if player_list is Array else 0,
		"current_player": current_player,
		"function": "_handle_game_state"
	})
	
	# Clear existing players and rebuild from event
	players.clear()
	player_order.clear()
	
	# Build turn order first
	if turn_order is Array:
		for player_id in turn_order:
			player_order.append(str(player_id))
	
	# Update players dictionary - prefer player_list (active players in order)
	if player_list is Array:
		for p_data in player_list:
			if p_data is Dictionary:
				var pid = str(p_data.get("player_id", ""))
				if pid != "":
					players[pid] = p_data.duplicate()
	
	# Also add any other players from full players dict (viewers, etc.)
	if event_players is Dictionary:
		for player_id_key in event_players:
			var pid_str := str(player_id_key)
			var p_data = event_players[player_id_key]
			if p_data is Dictionary:
				if not players.has(pid_str):
					players[pid_str] = p_data.duplicate()
				else:
					# Update existing with any missing data
					var existing = players[pid_str]
					for k in p_data:
						existing[k] = p_data[k]
	
	# Update current player
	current_player_id = str(current_player)
	
	# Check if local player is a viewer
	var local_player_data = players.get(local_player_id, {})
	if local_player_data is Dictionary:
		var is_viewer: bool = bool(local_player_data.get("is_viewer", false))
		if is_viewer:
			GameConfig.is_viewer = true
			_disable_all_controls()
			leave_button.disabled = false  # Viewers can leave
			_show_viewer_overlay()
	
	# Update dice
	if dice is Array and dice.size() >= 5:
		for i in range(5):
			dice_values[i] = int(dice[i])
			if dice_slots.size() > i:
				dice_slots[i].value = dice_values[i]
				dice_slots[i].held = false  # Reset held state
	else:
		# No dice rolled yet, ensure all are 0
		for i in range(5):
			dice_values[i] = 0
			if dice_slots.size() > i:
				dice_slots[i].value = 0
				dice_slots[i].held = false
	
	# Update rolls left
	rolls_left = int(rolls_left_val)
	_update_rolls_label()
	
	# Disable dice interaction if not local player's turn or if viewer
	if not _is_local_turn() or GameConfig.is_viewer:
		_set_dice_interactive(false)
		scorecard_panel.set_all_interactive(false)
	else:
		_set_dice_interactive(true)
		scorecard_panel.set_all_interactive(true)
	
	# Load scores for all active players from the player data BEFORE building UI
	# The server sends each player's scores in their player data
	# We must populate scores_by_player_id first so set_players_ordered can use them
	get_node("/root/Logger").debug("Loading scores from game state", {
		"player_count": player_order.size(),
		"function": "_handle_game_state"
	})
	for player_id in player_order:
		var p_data = players.get(player_id, {})
		if p_data is Dictionary:
			var scores_data = p_data.get("scores", null)
			if scores_data != null and scores_data is Dictionary:
				get_node("/root/Logger").debug("Loading player scores", {
					"player_id": player_id,
					"score_count": scores_data.size(),
					"function": "_handle_game_state"
				})
				for cat in scores_data:
					var cat_str := str(cat)
					var score_val: int = int(scores_data[cat])
					# Pre-populate the scorecard's player ID tracking
					scorecard_panel.set_player_score(player_id, cat_str, score_val)
	
	get_node("/root/Logger").debug("Setting up scorecard UI", {"function": "_handle_game_state"})
	# Setup scorecard with player info (this rebuilds the UI using scores_by_player_id)
	scorecard_panel.set_players_ordered(players, player_order, local_player_id)
	scorecard_panel.set_current_turn_by_id(current_player_id, player_order)
	
	_refresh_player_list()
	_update_current_player_label()
	
	# Process event history to populate info log (for context only, scores already loaded above)
	var event_history: Variant = event.get("event_history", null)
	if event_history is Array:
		info_log.append_text("[color=#c7a88d]Game History:[/color]\n")
		for hist_event in event_history:
			if hist_event is Dictionary:
				_process_history_event(hist_event)
		info_log.append_text("\n")
	
	info_log.append_text("[color=#c7a88d]Joined game in progress. You are viewing.[/color]\n")

func _process_history_event(hist_event: Dictionary) -> void:
	# Process a historical event and add it to the info log
	# NOTE: This is for info log display only - scores are already loaded from player data
	var event_type: String = str(hist_event.get("type", ""))
	
	match event_type:
		"GAME_STARTED":
			info_log.append_text("[color=#c7a88d]Game started.[/color]\n")
		"TURN_CHANGED":
			var pid: String = str(hist_event.get("current_player", ""))
			if players.has(pid):
				var p_data = players[pid]
				var pname: String = _get_player_name(p_data)
				info_log.append_text("%s's turn.\n" % pname)
			else:
				info_log.append_text("Turn changed.\n")
		"SCORE_UPDATE":
			var pid: String = str(hist_event.get("player_id", ""))
			var category: String = str(hist_event.get("category", ""))
			var score: int = int(hist_event.get("score", 0))
			
			if players.has(pid):
				var pname: String = _get_player_name(players[pid])
				# Format category name nicely
				var cat_display: String = category.replace("_", " ").capitalize()
				info_log.append_text("%s chose %s (%d)\n" % [pname, cat_display, score])
			# Don't lock here - scores already loaded from player data in _handle_game_state
		"ROLL_RESULT":
			# Roll results are less important in history, skip them
			pass
		"PLAYER_JOINED":
			var pname: String = str(hist_event.get("name", hist_event.get("player_name", "Player")))
			info_log.append_text("%s joined the game.\n" % pname)
		"PLAYER_LEFT":
			var pname: String = str(hist_event.get("player_name", hist_event.get("name", "Player")))
			info_log.append_text("[color=#e8736b]%s left the game[/color]\n" % pname)
		"CHAT_MESSAGE":
			# Could add chat history if needed
			pass

# Helper function to safely get player name from player data
func _get_player_name(p_data) -> String:
	if p_data is Dictionary:
		var n = p_data.get("name", p_data.get("player_name", ""))
		if n != "":
			return str(n)
	return "Player"

func _show_viewer_overlay() -> void:
	# Create a subtle overlay to indicate viewer mode
	var overlay := ColorRect.new()
	overlay.name = "ViewerOverlay"
	overlay.color = Color(0, 0, 0, 0.3)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Add viewer label at top
	var viewer_label := Label.new()
	viewer_label.text = "VIEWER MODE - You are watching this game"
	viewer_label.add_theme_font_size_override("font_size", 18)
	viewer_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	viewer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	viewer_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	viewer_label.offset_top = 20
	viewer_label.offset_left = 20
	viewer_label.offset_right = -20
	overlay.add_child(viewer_label)

func _handle_player_joined(event: Dictionary) -> void:
	var pid := str(event.get("player_id", ""))
	var pname: String = str(event.get("player_name", event.get("name", "Player")))
	var is_viewer: bool = bool(event.get("is_viewer", false))
	players[pid] = {"name": pname, "total_score": 0, "is_viewer": is_viewer}
	
	get_node("/root/Logger").info("Player joined", {
		"player_id": pid,
		"player_name": pname,
		"is_viewer": is_viewer,
		"room_code": GameConfig.room_code,
		"function": "_handle_player_joined"
	})
	
	_refresh_player_list()
	
	# For mock network, update local_player_id if this is our player
	if event.get("is_host", false) and GameConfig.network_mode == GameConfig.NetworkMode.MOCK:
		local_player_id = pid
		get_node("/root/Logger").debug("Updated local player ID from mock network", {
			"local_player_id": local_player_id,
			"function": "_handle_player_joined"
		})

func _handle_player_left(event: Dictionary) -> void:
	var pid := str(event.get("player_id", ""))
	var _player_name: String = str(event.get("player_name", "Player"))
	var _was_host: bool = bool(event.get("is_host", false))
	
	if players.has(pid):
		var player_name_to_show: String = _get_player_name(players[pid])
		get_node("/root/Logger").info("Player left", {
			"player_id": pid,
			"player_name": player_name_to_show,
			"was_host": _was_host,
			"room_code": GameConfig.room_code,
			"function": "_handle_player_left"
		})
		info_log.append_text("[color=#e8736b]%s left the game[/color]\n" % player_name_to_show)
		
		# Remove from players dictionary
		players.erase(pid)
		
		# Remove from player_order array
		var player_idx := player_order.find(pid)
		if player_idx >= 0:
			player_order.remove_at(player_idx)
		
		# Update scorecard panel with new player order
		if scorecard_panel:
			# Remove this player's scores from tracking
			scorecard_panel.remove_player_scores(pid)
			
			# Rebuild scorecard with updated player order
			# The scorecard will automatically remap remaining players' scores
			scorecard_panel.set_players_ordered(players, player_order, local_player_id)
			
			# Update current turn indicator if still valid
			if current_player_id != "" and player_order.find(current_player_id) >= 0:
				scorecard_panel.set_current_turn_by_id(current_player_id, player_order)
		
		_refresh_player_list()
		
		# If the current player left, the server will send a TURN_CHANGED event
		# but we should update the UI immediately to reflect the change
		if pid == current_player_id:
			info_log.append_text("[color=#c7a88d]Waiting for next turn...[/color]\n")
			# Clear dice display since the turn is changing
			for i in range(5):
				dice_values[i] = 0
				dice_slots[i].value = 0
				dice_slots[i].held = false
			rolls_left = 3
			_update_rolls_label()
			scorecard_panel.clear_previews()
			_set_dice_interactive(false)
			scorecard_panel.set_all_interactive(false)
			end_turn_button.disabled = true

func _handle_room_ended(event: Dictionary) -> void:
	var reason: String = str(event.get("reason", "unknown"))
	
	get_node("/root/Logger").warn("Room ended", {
		"reason": reason,
		"player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_handle_room_ended"
	})
	
	var title: String = "Game Ended"
	var message: String = "The game has been terminated."
	
	match reason:
		"host_disconnected":
			title = "Host Disconnected"
			message = "The host has left the game. The game has ended."
		"insufficient_players":
			title = "Insufficient Players"
			message = "Not enough players remain to continue the game."
		_:
			title = "Game Ended"
			message = "The game has been terminated."
	
	_disable_all_controls()
	_show_error_overlay(title, message)

func _handle_game_start(event: Dictionary) -> void:
	# Store the event and show the player order animation first
	_pending_game_start_event = event
	
	# Extract player info for animation
	var anim_players: Array[Dictionary] = []
	
	# Get turn order from event
	var turn_order: Variant = event.get("turn_order", [])
	var event_players: Variant = event.get("players", {})
	var player_list: Variant = event.get("player_list", null)
	
	# Build player name mapping
	var name_map: Dictionary = {}
	if player_list is Array:
		for p_data in player_list:
			if p_data is Dictionary:
				var pid = str(p_data.get("player_id", ""))
				var pname = str(p_data.get("name", "Player"))
				name_map[pid] = pname
	if event_players is Dictionary:
		for pid in event_players:
			var p_data = event_players[pid]
			if p_data is Dictionary:
				name_map[str(pid)] = str(p_data.get("name", "Player"))
	
	# Build ordered list for animation
	if turn_order is Array:
		for pid in turn_order:
			var pid_str := str(pid)
			anim_players.append({
				"id": pid_str,
				"name": name_map.get(pid_str, "Player"),
				"is_local": pid_str == local_player_id
			})
	
	# Show the animation
	if anim_players.size() > 0:
		_show_player_order_animation(anim_players)
	else:
		# No animation data, just start immediately
		_complete_game_start()


func _show_player_order_animation(anim_players: Array[Dictionary]) -> void:
	# Create full-screen overlay
	var overlay := ColorRect.new()
	overlay.name = "PlayerOrderOverlay"
	overlay.color = Color(0.1, 0.12, 0.15, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	# Main VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "TURN ORDER"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Spinning indicator (will be replaced by players)
	var spinner_label := Label.new()
	spinner_label.name = "SpinnerLabel"
	spinner_label.text = "Randomizing..."
	spinner_label.add_theme_font_size_override("font_size", 28)
	spinner_label.add_theme_color_override("font_color", Color(0.91, 0.52, 0.45))
	spinner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(spinner_label)
	
	# Player slots container
	var slots_container := VBoxContainer.new()
	slots_container.name = "SlotsContainer"
	slots_container.add_theme_constant_override("separation", 12)
	vbox.add_child(slots_container)
	
	# Create empty slots for each player
	for i in range(anim_players.size()):
		var slot := _create_player_slot(i + 1, "", false)
		slot.modulate.a = 0.3
		slots_container.add_child(slot)
	
	# Animate the reveal
	await _animate_player_reveal(overlay, slots_container, spinner_label, anim_players)


func _create_player_slot(pos_num: int, player_name: String, is_local: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	
	if is_local:
		style.bg_color = Color(0.55, 0.78, 0.73, 0.9)  # Teal for local player
	else:
		style.bg_color = Color(0.25, 0.23, 0.22, 0.9)  # Dark for others
	
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(300, 50)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	panel.add_child(hbox)
	
	# Position number
	var pos_label := Label.new()
	var ordinal := _get_ordinal(pos_num)
	pos_label.text = ordinal
	pos_label.add_theme_font_size_override("font_size", 22)
	pos_label.add_theme_color_override("font_color", Color(0.91, 0.52, 0.45))
	pos_label.custom_minimum_size.x = 50
	hbox.add_child(pos_label)
	
	# Player name
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = player_name
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)
	
	# You indicator
	if is_local and player_name != "":
		var you_label := Label.new()
		you_label.text = "(YOU)"
		you_label.add_theme_font_size_override("font_size", 16)
		you_label.add_theme_color_override("font_color", Color(1, 0.84, 0))
		hbox.add_child(you_label)
	
	return panel


func _get_ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return str(n) + "th"


func _animate_player_reveal(overlay: Control, slots_container: VBoxContainer, spinner: Label, anim_players: Array[Dictionary]) -> void:
	# Spinning animation phase
	var spin_duration := 1.5
	var spin_symbols := ["*", "D", "O", "X", "+"]
	var spin_start := Time.get_ticks_msec()
	
	while (Time.get_ticks_msec() - spin_start) < spin_duration * 1000:
		@warning_ignore("integer_division")
		var idx := (Time.get_ticks_msec() / 100) % spin_symbols.size()
		spinner.text = spin_symbols[idx] + " Randomizing... " + spin_symbols[idx]
		await get_tree().create_timer(0.1).timeout
	
		spinner.text = "Here's the order!"
	
	await get_tree().create_timer(0.3).timeout
	
	# Reveal each player one by one
	for i in range(anim_players.size()):
		var player_data: Dictionary = anim_players[i]
		var slot: PanelContainer = slots_container.get_child(i)
		
		# Replace the empty slot with the revealed player
		var new_slot := _create_player_slot(i + 1, player_data.name, player_data.is_local)
		new_slot.modulate.a = 0
		slots_container.add_child(new_slot)
		slots_container.move_child(new_slot, i)
		slot.queue_free()
		
		# Fade in animation
		var tween := create_tween()
		tween.tween_property(new_slot, "modulate:a", 1.0, 0.3)
		
		# Scale pop effect
		new_slot.scale = Vector2(0.8, 0.8)
		new_slot.pivot_offset = new_slot.size / 2
		tween.parallel().tween_property(new_slot, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		
		await get_tree().create_timer(0.5).timeout
	
	# Brief pause to let players see the order
	await get_tree().create_timer(1.5).timeout
	
	# Fade out overlay
	var fade_tween := create_tween()
	fade_tween.tween_property(overlay, "modulate:a", 0.0, 0.5)
	await fade_tween.finished
	
	overlay.queue_free()
	
	# Now actually start the game
	_complete_game_start()


func _complete_game_start() -> void:
	var event := _pending_game_start_event
	_pending_game_start_event = {}
	
	# Handle player_list if provided (array of player objects) - preferred over dictionary
	var player_list: Variant = event.get("player_list", null)
	if player_list is Array:
		for p_data in player_list:
			if p_data is Dictionary:
				var pid = str(p_data.get("player_id", ""))
				if pid != "":
					if not players.has(pid):
						players[pid] = p_data
					else:
						# Update existing
						var existing = players[pid]
						for k in p_data:
							existing[k] = p_data[k]
	
	var event_players: Variant = event.get("players", null)
	if event_players != null and event_players is Dictionary:
		# Merge player data instead of overwriting to preserve existing info (like names)
		for pid in event_players:
			var p_data = event_players[pid]
			if p_data is Dictionary:
				if not players.has(pid):
					players[pid] = p_data
				else:
					# Update existing player with new data
					var existing = players[pid]
					for k in p_data:
						existing[k] = p_data[k]
					# Ensure we have a name
					if not existing.has("name") and p_data.has("name"):
						existing["name"] = p_data["name"]
	
	# Get turn order from server (consistent across all clients)
	var turn_order: Variant = event.get("turn_order", [])
	if turn_order is Array:
		player_order.clear()
		for pid in turn_order:
			player_order.append(str(pid))
	else:
		# Fallback to dictionary keys if no turn_order
		player_order = players.keys()
	
	var first_player: Variant = event.get("first_player_id", event.get("current_player", local_player_id))
	current_player_id = str(first_player)
	rolls_left = 3
	
	get_node("/root/Logger").info("Game started", {
		"player_count": players.size(),
		"turn_order": player_order,
		"first_player": current_player_id,
		"local_player_id": local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_complete_game_start"
	})
	
	# Setup scorecard with player info using consistent order
	scorecard_panel.set_players_ordered(players, player_order, local_player_id)
	scorecard_panel.set_current_turn_by_id(current_player_id, player_order)
	
	_refresh_player_list()
	_update_current_player_label()
	_update_rolls_label()
	info_log.append_text("Game started.\n")
	
	# Enable controls if it's our turn
	var is_my_turn := _is_local_turn()
	_set_dice_interactive(is_my_turn)
	if is_my_turn:
		scorecard_panel.set_all_interactive(true)
		get_node("/root/Logger").debug("Local player's turn - controls enabled", {
			"player_id": local_player_id,
			"function": "_complete_game_start"
		})
	else:
		scorecard_panel.set_all_interactive(false)
		get_node("/root/Logger").debug("Other player's turn - controls disabled", {
			"current_player": current_player_id,
			"function": "_complete_game_start"
		})
		# In mock mode, trigger bot's turn now that UI is ready
		if GameConfig.network_mode == GameConfig.NetworkMode.MOCK:
			GameNetwork.start_first_bot_turn()

func _handle_roll_result(event: Dictionary) -> void:
	var new_dice: Array = event.get("dice", dice_values)
	rolls_left = int(event.get("rolls_left", rolls_left))
	var player_id: String = str(event.get("player_id", ""))
	
	get_node("/root/Logger").info("Dice rolled", {
		"player_id": player_id,
		"dice": new_dice,
		"rolls_left": rolls_left,
		"is_local": player_id == local_player_id,
		"room_code": GameConfig.room_code,
		"function": "_handle_roll_result"
	})
	
	# Animate dice that changed (not held)
	for i in range(5):
		if i < new_dice.size():
			var new_val: int = int(new_dice[i])
			if not dice_slots[i].held:
				dice_slots[i].animate_roll(new_val)
			dice_values[i] = new_val
	
	_update_rolls_label()
	
	# Check for Yahtzee (5 of a kind) - celebrate!
	if _is_yahtzee(dice_values):
		get_node("/root/Logger").info("Yahtzee!", {
			"player_id": player_id,
			"dice": dice_values,
			"function": "_handle_roll_result"
		})
		# Wait for dice animation then show celebration
		await get_tree().create_timer(0.7).timeout
		_show_yahtzee_celebration()
	
	# Update score previews if it's local player's turn
	if _is_local_turn():
		# Wait for animations to finish before updating previews
		await get_tree().create_timer(0.7).timeout
		scorecard_panel.set_previews(dice_values)
		scorecard_panel.set_all_interactive(true)
		end_turn_button.disabled = false


func _is_yahtzee(dice: Array[int]) -> bool:
	if dice.size() < 5:
		return false
	var first := dice[0]
	if first == 0:
		return false  # Dice not rolled yet
	for d in dice:
		if d != first:
			return false
	return true


func _show_yahtzee_celebration() -> void:
	# Create celebration overlay
	var overlay := Control.new()
	overlay.name = "YahtzeeCelebration"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	
	# Show "YAHTZEE!" text
	var label := Label.new()
	label.text = "YAHTZEE!"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))  # Gold
	label.add_theme_color_override("font_outline_color", Color(0.2, 0.15, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.pivot_offset = label.size / 2
	overlay.add_child(label)
	
	# Animate the text
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0
	var text_tween := create_tween()
	text_tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	text_tween.parallel().tween_property(label, "modulate:a", 1.0, 0.2)
	text_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Spawn confetti particles
	_spawn_confetti(overlay, 50)
	
	# Remove celebration after a few seconds
	await get_tree().create_timer(2.5).timeout
	var fade_tween := create_tween()
	fade_tween.tween_property(overlay, "modulate:a", 0.0, 0.5)
	await fade_tween.finished
	overlay.queue_free()


func _spawn_confetti(parent: Control, count: int) -> void:
	var colors := [
		Color(1.0, 0.3, 0.3),   # Red
		Color(0.3, 1.0, 0.3),   # Green
		Color(0.3, 0.3, 1.0),   # Blue
		Color(1.0, 1.0, 0.3),   # Yellow
		Color(1.0, 0.5, 0.0),   # Orange
		Color(1.0, 0.3, 1.0),   # Magenta
		Color(0.3, 1.0, 1.0),   # Cyan
		Color(1.0, 0.84, 0.0),  # Gold
	]
	
	var viewport_size := get_viewport_rect().size
	
	for i in range(count):
		var confetti := ColorRect.new()
		confetti.size = Vector2(randf_range(8, 16), randf_range(8, 16))
		confetti.color = colors[randi() % colors.size()]
		confetti.position = Vector2(randf() * viewport_size.x, -20)
		confetti.rotation = randf() * TAU
		confetti.pivot_offset = confetti.size / 2
		parent.add_child(confetti)
		
		# Animate falling
		var fall_tween := create_tween()
		var end_y := viewport_size.y + 50
		var drift_x := randf_range(-100, 100)
		var duration := randf_range(1.5, 3.0)
		var delay := randf_range(0, 0.5)
		
		fall_tween.tween_property(confetti, "position:y", end_y, duration).set_delay(delay).set_ease(Tween.EASE_IN)
		fall_tween.parallel().tween_property(confetti, "position:x", confetti.position.x + drift_x, duration).set_delay(delay)
		fall_tween.parallel().tween_property(confetti, "rotation", confetti.rotation + randf_range(-TAU, TAU), duration).set_delay(delay)

func _handle_category_chosen(event: Dictionary) -> void:
	# Also handles SCORE_UPDATE events
	var pid := str(event.get("player_id", ""))
	var cat: String = str(event.get("category", ""))
	var score := int(event.get("score", 0))
	var upper_bonus: int = int(event.get("upper_bonus", 0))
	var yahtzee_bonus: int = int(event.get("yahtzee_bonus", 0))
	
	get_node("/root/Logger").info("Category chosen", {
		"player_id": pid,
		"category": cat,
		"score": score,
		"upper_bonus": upper_bonus,
		"yahtzee_bonus": yahtzee_bonus,
		"room_code": GameConfig.room_code,
		"function": "_handle_category_chosen"
	})
	
	if players.has(pid):
		var p_data = players[pid]
		if p_data is Dictionary:
			p_data["total_score"] = int(p_data.get("total_score", 0)) + score
	_refresh_player_list()
	
	# Find player index using consistent player_order
	var player_idx := player_order.find(pid)
	if player_idx < 0:
		player_idx = 0
	scorecard_panel.lock_category(cat, score, player_idx)
	var name_to_show: String = _get_player_name(players.get(pid, {})) if players.has(pid) else "Player"
	info_log.append_text("%s chose %s (%d)\n" % [name_to_show, cat, score])

func _handle_turn_change(event: Dictionary) -> void:
	current_player_id = str(event.get("current_player", event.get("player_id", current_player_id)))
	var is_my_turn := _is_local_turn()
	
	get_node("/root/Logger").info("Turn changed", {
		"current_player": current_player_id,
		"player_name": _get_player_name(players.get(current_player_id, {})),
		"is_local": is_my_turn,
		"room_code": GameConfig.room_code,
		"function": "_handle_turn_change"
	})
	
	# Update scorecard turn indicator using consistent order
	scorecard_panel.set_current_turn_by_id(current_player_id, player_order)
	
	# Clear held dice for new turn
	for slot in dice_slots:
		slot.held = false
	
	# Reset dice display for new turn
	for i in range(5):
		dice_values[i] = 0
		dice_slots[i].value = 0
	
	_update_current_player_label()
	rolls_left = 3
	_update_rolls_label()
	
	# Clear previews from previous turn
	scorecard_panel.clear_previews()
	
	# Set dice interactivity based on turn
	_set_dice_interactive(is_my_turn)
	
	if is_my_turn:
		scorecard_panel.set_all_interactive(true)
		end_turn_button.disabled = true  # Disabled until they roll and choose
		info_log.append_text("[color=#8dc7be]Your turn! Roll the dice.[/color]\n")
	else:
		scorecard_panel.set_all_interactive(false)
		end_turn_button.disabled = true
		var cur_name: String = _get_player_name(players.get(current_player_id, {})) if players.has(current_player_id) else "Player"
		info_log.append_text("%s's turn.\n" % cur_name)

func _refresh_player_list() -> void:
	players_list.clear()
	for pid in players.keys():
		var p = players[pid]
		var pname: String = _get_player_name(p)
		var total: int = int(p.get("total_score", 0)) if p is Dictionary else 0
		var text := "%s: %d" % [pname, total]
		if pid == current_player_id:
			text += " (turn)"
		if pid == local_player_id:
			text += " [YOU]"
		players_list.add_item(text)

func _update_current_player_label() -> void:
	var cur_player_name: String = _get_player_name(players.get(current_player_id, {})) if players.has(current_player_id) else "Unknown"
	current_player_label.text = "Current: " + cur_player_name
	_refresh_player_list()

func _update_dice_visuals() -> void:
	for i in range(5):
		dice_slots[i].value = dice_values[i]

func _update_rolls_label() -> void:
	rolls_label.text = str(rolls_left)
	roll_count_label.text = str(rolls_left)
	# Also disable roll button if no rolls left (regardless of turn)
	if _is_local_turn() and rolls_left <= 0:
		roll_button.disabled = true

func _update_room_code_label() -> void:
	if room_code_label:
		var room_code: String = GameConfig.room_code
		if room_code != "":
			room_code_label.text = "Room: " + room_code
		else:
			room_code_label.text = ""

func _is_local_turn() -> bool:
	return current_player_id == local_player_id and not GameConfig.is_viewer

func _set_dice_interactive(enabled: bool) -> void:
	for slot in dice_slots:
		slot.interactive = enabled
	roll_button.disabled = not enabled

func _on_roll_pressed() -> void:
	if GameConfig.is_viewer:
		return
	if not _is_local_turn():
		return
	if rolls_left <= 0:
		return

	# Determine held indices from dice_slots
	var held_indices: Array[int] = []
	for i in range(5):
		if dice_slots[i].held:
			held_indices.append(i)

	get_node("/root/Logger").debug("Roll button pressed", {
		"player_id": local_player_id,
		"rolls_left": rolls_left,
		"held_indices": held_indices,
		"current_dice": dice_values,
		"function": "_on_roll_pressed"
	})

	# Send request; authority will respond
	var ev := {
		"type": "REQUEST_ROLL",
		"player_id": local_player_id,
		"held_indices": held_indices
	}
	GameNetwork.send_game_event(ev)

func _on_end_turn_pressed() -> void:
	if GameConfig.is_viewer:
		return
	if not _is_local_turn():
		return
	# Player should have chosen a category; just send TURN_CHANGE
	var ev := {
		"type": "REQUEST_END_TURN",
		"player_id": local_player_id
	}
	GameNetwork.send_game_event(ev)

func _on_category_chosen(cat: String) -> void:
	if GameConfig.is_viewer:
		return
	if not _is_local_turn():
		return
	# Calculate score locally, but authority should verify as well
	var scores: Dictionary = ScoreLogic.score_all(dice_values)
	var score: int = int(scores.get(cat, 0))

	get_node("/root/Logger").info("Category chosen by local player", {
		"player_id": local_player_id,
		"category": cat,
		"score": score,
		"dice": dice_values,
		"room_code": GameConfig.room_code,
		"function": "_on_category_chosen"
	})

	var ev := {
		"type": "CATEGORY_CHOSEN",
		"player_id": local_player_id,
		"category": cat,
		"score": score
	}
	GameNetwork.send_game_event(ev)
	scorecard_panel.set_all_interactive(false)
	end_turn_button.disabled = false

func _on_leave_pressed() -> void:
	_intentional_leave = true
	GameNetwork.disconnect_from_match()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _disable_all_controls() -> void:
	roll_button.disabled = true
	end_turn_button.disabled = true
	# Don't disable leave button for viewers - they should be able to exit
	if not GameConfig.is_viewer:
		leave_button.disabled = true
	scorecard_panel.set_all_interactive(false)
	for ds in dice_slots:
		ds.interactive = false

func _show_error_overlay(title: String, message: String) -> void:
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
	
	# Style the button
	var style := StyleBoxFlat.new()
	style.bg_color = BUTTON_BG
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	return_button.add_theme_stylebox_override("normal", style)
	return_button.add_theme_color_override("font_color", BUTTON_TEXT)
	return_button.add_theme_font_size_override("font_size", 16)
	
	vbox.add_child(return_button)
	
	# Center the vbox
	vbox.position = Vector2(-vbox.size.x / 2, -vbox.size.y / 2)

func _handle_game_end(event: Dictionary) -> void:
	var final_scores: Dictionary = event.get("final_scores", {})
	var winner_name: String = str(event.get("winner_name", "Unknown"))
	var is_draw: bool = bool(event.get("is_draw", false))
	var winner_id: String = str(event.get("winner_id", ""))
	
	get_node("/root/Logger").info("Game ended", {
		"winner_id": winner_id,
		"winner_name": winner_name,
		"is_draw": is_draw,
		"final_scores": final_scores,
		"room_code": GameConfig.room_code,
		"function": "_handle_game_end"
	})
	
	# Disable all controls
	roll_button.disabled = true
	end_turn_button.disabled = true
	scorecard_panel.set_all_interactive(false)
	for ds in dice_slots:
		ds.interactive = false
	
	# Show game end overlay
	_show_game_end_overlay(final_scores, winner_name, is_draw)

func _show_game_end_overlay(final_scores: Dictionary, winner_name: String, is_draw: bool = false) -> void:
	# Create overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	# Center container for proper alignment
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.custom_minimum_size = Vector2(400, 300)
	center.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "GAME OVER!"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Winner announcement with draw handling
	var winner_label := Label.new()
	if is_draw:
		winner_label.text = winner_name
	else:
		winner_label.text = "Winner: " + winner_name
	winner_label.add_theme_font_size_override("font_size", 28)
	winner_label.add_theme_color_override("font_color", Color(1, 0.84, 0))  # Gold
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(winner_label)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	# Scores list
	var scores_container := VBoxContainer.new()
	scores_container.add_theme_constant_override("separation", 8)
	vbox.add_child(scores_container)
	
	# Sort scores by final score descending - handle both formats
	var sorted_pids: Array = final_scores.keys()
	sorted_pids.sort_custom(func(a, b):
		var score_a = final_scores[a]
		var score_b = final_scores[b]
		# Handle both Dictionary format (with .final_score) and int format
		var val_a: int = 0
		var val_b: int = 0
		if score_a is Dictionary:
			val_a = int(score_a.get("final_score", 0))
		else:
			val_a = int(score_a)
		if score_b is Dictionary:
			val_b = int(score_b.get("final_score", 0))
		else:
			val_b = int(score_b)
		return val_a > val_b
	)
	
	var rank := 1
	var prev_score: int = -1
	var actual_rank := 1
	for pid in sorted_pids:
		var data = final_scores[pid]
		var score_line := Label.new()
		
		var name_str: String = ""
		var final_score: int = 0
		var upper_bonus: int = 0
		
		# Handle both Dictionary format and simple int format
		if data is Dictionary:
			name_str = str(data.get("name", "Player"))
			final_score = int(data.get("final_score", 0))
			upper_bonus = int(data.get("upper_bonus", 0))
		else:
			# Simple int format - try to get name from players dict
			name_str = players.get(pid, {}).get("name", "Player")
			final_score = int(data)
		
		# Handle tied ranks
		if final_score == prev_score:
			actual_rank = rank - 1  # Same rank as previous
		else:
			actual_rank = rank
		prev_score = final_score
		
		var bonus_text := " (+35 bonus)" if upper_bonus > 0 else ""
		score_line.text = "%d. %s: %d%s" % [actual_rank, name_str, final_score, bonus_text]
		score_line.add_theme_font_size_override("font_size", 18)
		score_line.add_theme_color_override("font_color", Color(0.96, 0.93, 0.87))
		score_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		# Highlight if this is the local player
		if pid == local_player_id:
			score_line.add_theme_color_override("font_color", Color(0.55, 0.78, 0.73))  # Teal
			score_line.text += " (YOU)"
		
		scores_container.add_child(score_line)
		rank += 1
	
	# Spacer before button
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# Play again button
	var play_again := Button.new()
	play_again.text = "Return to Main Menu"
	play_again.custom_minimum_size = Vector2(240, 48)
	play_again.pressed.connect(_on_leave_pressed)
	
	# Style the button
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = BUTTON_BG
	btn_style.set_corner_radius_all(10)
	btn_style.set_content_margin_all(12)
	play_again.add_theme_stylebox_override("normal", btn_style)
	play_again.add_theme_stylebox_override("hover", btn_style)
	play_again.add_theme_stylebox_override("pressed", btn_style)
	play_again.add_theme_color_override("font_color", BUTTON_TEXT)
	play_again.add_theme_font_size_override("font_size", 18)
	
	vbox.add_child(play_again)
