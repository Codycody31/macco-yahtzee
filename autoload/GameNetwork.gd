extends Node

signal game_event_received(event: Dictionary)
signal connection_state_changed(state: int, error: int)

enum ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, FAILED }

const ServerNetworkScript = preload("res://network/ServerNetwork.gd")

var _impl: Node = null
var state: ConnectionState = ConnectionState.DISCONNECTED

func setup_network() -> void:
	if _impl and is_instance_valid(_impl):
		_impl.queue_free()
		_impl = null

	match GameConfig.network_mode:
		GameConfig.NetworkMode.SERVER:
			_impl = ServerNetworkScript.new()
		GameConfig.NetworkMode.MOCK:
			_impl = MockNetwork.new()  # Global class_name

	add_child(_impl)
	_impl.game_event_received.connect(_on_impl_event)
	_impl.connection_state_changed.connect(_on_impl_state)

func connect_to_match(params: Dictionary) -> void:
	state = ConnectionState.CONNECTING
	if _impl:
		_impl.connect_to_match(params)

func send_game_event(event: Dictionary) -> void:
	if _impl:
		_impl.send_game_event(event)

func disconnect_from_match() -> void:
	if _impl and _impl.has_method("disconnect_from_match"):
		_impl.disconnect_from_match()

func _on_impl_event(event: Dictionary) -> void:
	emit_signal("game_event_received", event)

func _on_impl_state(new_state: int, error: int = 0) -> void:
	state = new_state as ConnectionState
	emit_signal("connection_state_changed", new_state, error)

func get_player_id() -> String:
	if _impl and _impl.has_method("get_player_id"):
		return _impl.get_player_id()
	return ""

func get_room_code() -> String:
	if _impl and _impl.has_method("get_room_code"):
		return _impl.get_room_code()
	return GameConfig.room_code


func start_first_bot_turn() -> void:
	## For mock mode: trigger first bot turn after UI is ready
	if _impl and _impl.has_method("start_first_bot_turn"):
		_impl.start_first_bot_turn()
