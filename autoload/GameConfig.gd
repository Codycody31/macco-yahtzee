extends Node

enum NetworkMode {
	SERVER,
	MOCK
}

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_SERVER_URL := "https://games.macco.dev/api/v1/g/yahtzee"

var network_mode: NetworkMode = NetworkMode.SERVER
var server_url: String = DEFAULT_SERVER_URL

var player_name: String = "Player"
var player_id: String = ""
var player_token: String = ""  # Token for rejoin
var room_code: String = ""
var is_host: bool = false
var max_players: int = 6
var min_players: int = 2
var is_viewer: bool = false  # True if player is viewing (rejoined after game started)
var debug_mode: bool = false  # Enable debug panel visibility

# Store the game start event to pass data from Lobby to GameTable
var game_start_event: Dictionary = {}
# Store the game state event for viewers joining mid-game
var game_state_event: Dictionary = {}


func _ready() -> void:
	load_settings()
	_apply_mobile_scale()


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err != OK:
		# No settings file yet, use defaults
		return
	
	player_name = config.get_value("player", "name", "Player")
	server_url = config.get_value("server", "url", DEFAULT_SERVER_URL)
	debug_mode = config.get_value("debug", "enabled", false)
	# Note: player_id and token are session-only, not saved
	
	# Load log level if Logger is available
	# Use integer literals to avoid autoload order issues
	if has_node("/root/Logger"):
		var log_level_str: String = config.get_value("logging", "level", "DEBUG") as String
		var log_level: int = 0  # DEBUG
		match log_level_str:
			"DEBUG": log_level = 0
			"INFO": log_level = 1
			"WARNING": log_level = 2
			"ERROR": log_level = 3
		get_node("/root/Logger").set_log_level(log_level)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.set_value("server", "url", server_url)
	config.set_value("debug", "enabled", debug_mode)
	
	# Save log level if Logger is available
	if has_node("/root/Logger"):
		var logger_node := get_node("/root/Logger")
		var log_level: int = logger_node.get_log_level()
		var log_level_str: String = logger_node.get_log_level_name(log_level)
		config.set_value("logging", "level", log_level_str)
	
	config.save(SETTINGS_PATH)

func get_log_level() -> int:
	# Return Logger log level if available
	if has_node("/root/Logger"):
		return get_node("/root/Logger").get_log_level()
	return 0  # DEBUG


func _apply_mobile_scale() -> void:
	# Only apply scaling on Android to fix the zoomed-out view
	# Desktop remains unaffected
	if OS.get_name() == "Android":
		var screen_dpi := DisplayServer.screen_get_dpi()
		# Base DPI is ~160 for standard Android density
		# Scale up for high-DPI screens so UI isn't tiny
		var scale_factor := maxf(1.0, screen_dpi / 160.0)
		# Clamp to reasonable range to avoid extreme scaling
		scale_factor = clampf(scale_factor, 1.0, 3.0)
		get_tree().root.content_scale_factor = scale_factor
