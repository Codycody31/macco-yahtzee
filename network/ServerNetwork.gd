extends Node

signal game_event_received(event: Dictionary)
signal connection_state_changed(state: int, error: int)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, FAILED }

var _http: HTTPRequest
var _socket: WebSocketPeer
var _room_code: String = ""
var _player_id: String = ""
var _token: String = ""
var _connected: bool = false
var _intentional_disconnect: bool = false

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_socket = WebSocketPeer.new()

func _process(_delta: float) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			# Check if disconnection was intentional
			if _intentional_disconnect:
				get_node("/root/Logger").info("WebSocket disconnected (intentional)", {
					"room_code": _room_code,
					"player_id": _player_id,
					"function": "_process"
				})
				emit_signal("connection_state_changed", ConnectionState.DISCONNECTED, OK)
			else:
				# Unexpected disconnection
				get_node("/root/Logger").warn("WebSocket disconnected unexpectedly", {
					"room_code": _room_code,
					"player_id": _player_id,
					"function": "_process"
				})
				emit_signal("connection_state_changed", ConnectionState.DISCONNECTED, ERR_CONNECTION_ERROR)
			_intentional_disconnect = false
		return
	
	_socket.poll()
	
	var state := _socket.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			get_node("/root/Logger").info("WebSocket connected", {
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_process"
			})
			emit_signal("connection_state_changed", ConnectionState.CONNECTED, OK)
		
		# Process incoming messages
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var text := packet.get_string_from_utf8()
			var data = JSON.parse_string(text)
			if typeof(data) == TYPE_DICTIONARY:
				_handle_server_message(data)
			else:
				get_node("/root/Logger").warn("Received invalid message format", {
					"room_code": _room_code,
					"player_id": _player_id,
					"message_length": text.length(),
					"function": "_process"
				})
	elif state == WebSocketPeer.STATE_CONNECTING:
		pass # Still connecting
	elif state == WebSocketPeer.STATE_CLOSING:
		pass # Closing

func connect_to_match(params: Dictionary) -> void:
	var mode: String = str(params.get("mode", "create"))
	var player_name: String = str(params.get("player_name", "Player"))
	
	_intentional_disconnect = false
	emit_signal("connection_state_changed", ConnectionState.CONNECTING, OK)
	
	get_node("/root/Logger").info("Connecting to match", {
		"mode": mode,
		"player_name": player_name,
		"function": "connect_to_match"
	})
	
	if mode == "create":
		_create_room(player_name)
	else:
		_room_code = params.get("room_code", "")
		_join_room(_room_code, player_name)

func _create_room(player_name: String) -> void:
	var url := GameConfig.server_url + "/rooms"
	var body := {"player_name": player_name}
	
	get_node("/root/Logger").debug("Creating room", {
		"player_name": player_name,
		"url": url,
		"function": "_create_room"
	})
	
	if not _http.request_completed.is_connected(_on_create_completed):
		_http.request_completed.connect(_on_create_completed.bind(player_name))
	_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _join_room(room_code: String, player_name: String) -> void:
	var url := GameConfig.server_url + "/rooms/join"
	var body := {
		"room_code": room_code,
		"player_name": player_name
	}
	# Only use credentials if they're for the same room (rejoin attempt)
	# If joining a different room, don't send credentials
	var is_rejoin := false
	if GameConfig.player_id != "" and GameConfig.player_token != "" and GameConfig.room_code == room_code:
		body["player_id"] = GameConfig.player_id
		body["token"] = GameConfig.player_token
		is_rejoin = true
	else:
		# Clear credentials if joining a different room
		if GameConfig.room_code != "" and GameConfig.room_code != room_code:
			GameConfig.player_id = ""
			GameConfig.player_token = ""
	
	get_node("/root/Logger").debug("Joining room", {
		"room_code": room_code,
		"player_name": player_name,
		"is_rejoin": is_rejoin,
		"url": url,
		"function": "_join_room"
	})
	
	if not _http.request_completed.is_connected(_on_join_completed):
		_http.request_completed.connect(_on_join_completed.bind(player_name))
	_http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))

func _on_create_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, player_name: String) -> void:
	_http.request_completed.disconnect(_on_create_completed)
	
	if response_code != 200:
		get_node("/root/Logger").error("Failed to create room", {
			"response_code": response_code,
			"result": _result,
			"player_name": player_name,
			"function": "_on_create_completed"
		})
		emit_signal("connection_state_changed", ConnectionState.FAILED, response_code)
		return
	
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		get_node("/root/Logger").error("Invalid response format when creating room", {
			"response_code": response_code,
			"player_name": player_name,
			"function": "_on_create_completed"
		})
		emit_signal("connection_state_changed", ConnectionState.FAILED, ERR_PARSE_ERROR)
		return
	
	_room_code = str(data.get("room_code", ""))
	_player_id = str(data.get("player_id", ""))
	_token = str(data.get("token", ""))
	var is_viewer: bool = bool(data.get("is_viewer", false))
	
	GameConfig.room_code = _room_code
	GameConfig.player_id = _player_id
	GameConfig.player_token = _token
	GameConfig.is_viewer = is_viewer
	
	get_node("/root/Logger").info("Room created successfully", {
		"room_code": _room_code,
		"player_id": _player_id,
		"is_viewer": is_viewer,
		"function": "_on_create_completed"
	})
	
	# Connect to WebSocket
	_connect_websocket(player_name)

func _on_join_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, player_name: String) -> void:
	_http.request_completed.disconnect(_on_join_completed)
	
	if response_code != 200:
		# If 403 and we have credentials, try rejoin
		if response_code == 403 and GameConfig.player_id != "" and GameConfig.player_token != "":
			get_node("/root/Logger").debug("Got 403, attempting rejoin with existing credentials", {
				"room_code": GameConfig.room_code,
				"player_name": player_name,
				"function": "_on_join_completed"
			})
			# Attempt rejoin with existing credentials
			_join_room(GameConfig.room_code, player_name)
			return
		# If 401, credentials were invalid - clear them and show error
		if response_code == 401:
			# Clear invalid credentials
			GameConfig.player_id = ""
			GameConfig.player_token = ""
			get_node("/root/Logger").warn("Invalid credentials. Cannot rejoin this room.", {
				"room_code": _room_code,
				"player_name": player_name,
				"function": "_on_join_completed"
			})
		else:
			get_node("/root/Logger").error("Failed to join room", {
				"response_code": response_code,
				"result": _result,
				"room_code": _room_code,
				"player_name": player_name,
				"function": "_on_join_completed"
			})
		emit_signal("connection_state_changed", ConnectionState.FAILED, response_code)
		return
	
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		get_node("/root/Logger").error("Invalid response format when joining room", {
			"response_code": response_code,
			"room_code": _room_code,
			"player_name": player_name,
			"function": "_on_join_completed"
		})
		emit_signal("connection_state_changed", ConnectionState.FAILED, ERR_PARSE_ERROR)
		return
	
	_room_code = str(data.get("room_code", ""))
	_player_id = str(data.get("player_id", ""))
	_token = str(data.get("token", ""))
	var is_viewer: bool = bool(data.get("is_viewer", false))
	
	GameConfig.room_code = _room_code
	GameConfig.player_id = _player_id
	GameConfig.player_token = _token
	GameConfig.is_viewer = is_viewer
	
	get_node("/root/Logger").info("Joined room successfully", {
		"room_code": _room_code,
		"player_id": _player_id,
		"is_viewer": is_viewer,
		"function": "_on_join_completed"
	})
	
	# Connect to WebSocket
	_connect_websocket(player_name)

func _connect_websocket(player_name: String) -> void:
	# Convert http:// to ws:// or https:// to wss://
	var ws_url := GameConfig.server_url.replace("http://", "ws://").replace("https://", "wss://")
	ws_url = "%s/rooms/%s/ws?player_id=%s&token=%s&player_name=%s" % [
		ws_url, 
		_room_code, 
		_player_id.uri_encode(), 
		_token.uri_encode(),
		player_name.uri_encode()
	]
	
	get_node("/root/Logger").debug("Connecting WebSocket", {
		"room_code": _room_code,
		"player_id": _player_id,
		"player_name": player_name,
		"function": "_connect_websocket"
	})
	
	var err := _socket.connect_to_url(ws_url)
	if err != OK:
		get_node("/root/Logger").error("Failed to connect WebSocket", {
			"error": err,
			"room_code": _room_code,
			"player_id": _player_id,
			"function": "_connect_websocket"
		})
		emit_signal("connection_state_changed", ConnectionState.FAILED, err)

func _handle_server_message(data: Dictionary) -> void:
	var msg_type: String = str(data.get("type", ""))
	
	get_node("/root/Logger").debug("Received server message", {
		"msg_type": msg_type,
		"room_code": _room_code,
		"player_id": _player_id,
		"function": "_handle_server_message"
	})
	
	match msg_type:
		"auth_success":
			# Successfully authenticated
			get_node("/root/Logger").info("WebSocket authentication successful", {
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_handle_server_message"
			})
		"auth_failed":
			get_node("/root/Logger").error("WebSocket authentication failed", {
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_handle_server_message"
			})
			emit_signal("connection_state_changed", ConnectionState.FAILED, ERR_UNAUTHORIZED)
			_socket.close()
		"event":
			# Wrapped event format: {"type": "event", "event": {...}}
			var event: Dictionary = data.get("event", {})
			var event_type: String = str(event.get("type", ""))
			get_node("/root/Logger").debug("Received game event (wrapped)", {
				"event_type": event_type,
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_handle_server_message"
			})
			emit_signal("game_event_received", event)
		"error":
			var error_msg: String = str(data.get("error", "Unknown error"))
			get_node("/root/Logger").error("Server error message", {
				"error": error_msg,
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_handle_server_message"
			})
		"VIEWER_MODE":
			# Player is in viewer mode (rejoined after game started)
			get_node("/root/Logger").info("Entering viewer mode", {
				"room_code": _room_code,
				"player_id": _player_id,
				"function": "_handle_server_message"
			})
			GameConfig.is_viewer = true
			emit_signal("game_event_received", data)
		_:
			# Direct event format: {"type": "PLAYER_JOINED", ...}
			# The server sends game events directly, not wrapped
			if msg_type != "":
				get_node("/root/Logger").debug("Received game event (direct)", {
					"event_type": msg_type,
					"room_code": _room_code,
					"player_id": _player_id,
					"function": "_handle_server_message"
				})
				emit_signal("game_event_received", data)

func send_game_event(event: Dictionary) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		get_node("/root/Logger").warn("Cannot send event: WebSocket not connected", {
			"event_type": str(event.get("type", "")),
			"room_code": _room_code,
			"player_id": _player_id,
			"function": "send_game_event"
		})
		return
	
	var event_type: String = str(event.get("type", ""))
	get_node("/root/Logger").debug("Sending game event", {
		"event_type": event_type,
		"room_code": _room_code,
		"player_id": _player_id,
		"function": "send_game_event"
	})
	
	var message := {
		"type": "event",
		"event": event
	}
	
	var json := JSON.stringify(message)
	_socket.send_text(json)

func disconnect_from_match() -> void:
	get_node("/root/Logger").info("Disconnecting from match", {
		"room_code": _room_code,
		"player_id": _player_id,
		"function": "disconnect_from_match"
	})
	_intentional_disconnect = true
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.close()
	_room_code = ""
	_player_id = ""
	_token = ""
	_connected = false

func get_room_code() -> String:
	return _room_code

func get_player_id() -> String:
	return _player_id
