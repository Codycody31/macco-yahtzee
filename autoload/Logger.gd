extends Node
class_name GameLogger

## Centralized logging system with multiple levels and outputs
## Supports console, file, and in-game debug panel logging

enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

# Expose enum values as constants for external access
const LEVEL_DEBUG := 0
const LEVEL_INFO := 1
const LEVEL_WARNING := 2
const LEVEL_ERROR := 3

const LOG_DIR := "user://logs"
const MAX_LOG_SIZE := 10 * 1024 * 1024  # 10MB
const MAX_LOG_DAYS := 7
const MAX_PANEL_LOGS := 500  # Max logs to keep in memory for debug panel

var current_log_level: LogLevel = LogLevel.DEBUG
var enable_file_logging: bool = true
var enable_console_logging: bool = true
var enable_panel_logging: bool = true

var log_file: FileAccess = null
var current_log_path: String = ""
var panel_logs: Array[Dictionary] = []
var debug_panel: Control = null

signal log_added(level: LogLevel, message: String, context: Dictionary)

func _ready() -> void:
	# Initialize logging directory
	if enable_file_logging:
		_setup_file_logging()
	
	# Set log level from config if available (use call_deferred to ensure GameConfig is ready)
	call_deferred("_load_log_level_from_config")
	call_deferred("_log_init_message")

func _log_init_message() -> void:
	info("Logger initialized", {"log_level": get_log_level_name(current_log_level)})

func _load_log_level_from_config() -> void:
	if has_node("/root/GameConfig"):
		var config_node := get_node("/root/GameConfig")
		if config_node.has_method("get_log_level"):
			var level: int = config_node.get_log_level()
			if level >= 0 and level <= 3:
				current_log_level = level as LogLevel

func _exit_tree() -> void:
	_close_log_file()

func _setup_file_logging() -> void:
	# Create logs directory
	var dir := DirAccess.open("user://")
	if not dir.dir_exists(LOG_DIR):
		dir.make_dir(LOG_DIR)
	
	# Clean old logs
	_cleanup_old_logs()
	
	# Open today's log file
	_open_today_log_file()

func _open_today_log_file() -> void:
	var today := Time.get_date_dict_from_system()
	var date_str := "%04d-%02d-%02d" % [today.year, today.month, today.day]
	var log_path := LOG_DIR.path_join("game_%s.log" % date_str)
	
	# Close existing file if different
	if log_file != null and current_log_path != log_path:
		_close_log_file()
	
	# Open new file if needed
	if log_file == null:
		log_file = FileAccess.open(log_path, FileAccess.WRITE)
		if log_file == null:
			# Try to create directory again
			var dir := DirAccess.open("user://")
			if not dir.dir_exists(LOG_DIR):
				dir.make_dir(LOG_DIR)
			log_file = FileAccess.open(log_path, FileAccess.WRITE)
		
		if log_file != null:
			current_log_path = log_path
			# Write header
			log_file.store_line("# Yahtzee Game Log - %s" % date_str)
			log_file.store_line("# Format: [LEVEL] [TIME] [CONTEXT] Message")
			log_file.store_line("")

func _close_log_file() -> void:
	if log_file != null:
		log_file.close()
		log_file = null
		current_log_path = ""

func _cleanup_old_logs() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	
	var cutoff_time := Time.get_unix_time_from_system() - (MAX_LOG_DAYS * 24 * 60 * 60)
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("game_") and file_name.ends_with(".log"):
			var file_path := LOG_DIR.path_join(file_name)
			var file_time := FileAccess.get_modified_time(file_path)
			if file_time < cutoff_time:
				dir.remove(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()

func _get_level_name(level: LogLevel) -> String:
	match level:
		LogLevel.DEBUG:
			return "DEBUG"
		LogLevel.INFO:
			return "INFO"
		LogLevel.WARNING:
			return "WARNING"
		LogLevel.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN"

func _log(level: LogLevel, message: String, context: Dictionary = {}) -> void:
	# Check if we should log this level
	if level < current_log_level:
		return
	
	var time_str: String = Time.get_time_string_from_system()
	var level_str: String = _get_level_name(level)
	
	# Build context string
	var context_parts: Array[String] = []
	if context.has("player_id"):
		context_parts.append("player=%s" % str(context.player_id))
	if context.has("room_code"):
		context_parts.append("room=%s" % str(context.room_code))
	if context.has("event_type"):
		context_parts.append("event=%s" % str(context.event_type))
	if context.has("function"):
		context_parts.append("func=%s" % str(context.function))
	
	var context_str := ""
	if context_parts.size() > 0:
		context_str = "[" + ", ".join(context_parts) + "]"
	
	# Format message
	var formatted_msg := "[%s] [%s] %s %s" % [level_str, time_str, context_str, message]
	
	# Console output
	if enable_console_logging:
		match level:
			LogLevel.DEBUG:
				print(formatted_msg)
			LogLevel.INFO:
				print(formatted_msg)
			LogLevel.WARNING:
				push_warning(formatted_msg)
			LogLevel.ERROR:
				push_error(formatted_msg)
	
	# File output
	if enable_file_logging:
		_write_to_file(level_str, time_str, context_str, message, context)
	
	# Panel output
	if enable_panel_logging:
		_add_to_panel(level, formatted_msg, context)
	
	# Emit signal
	log_added.emit(level, message, context)

func _write_to_file(level_str: String, time_str: String, _context_str: String, message: String, context: Dictionary) -> void:
	# Check if we need to rotate (new day)
	var today := Time.get_date_dict_from_system()
	var date_str := "%04d-%02d-%02d" % [today.year, today.month, today.day]
	var expected_path := LOG_DIR.path_join("game_%s.log" % date_str)
	
	if current_log_path != expected_path:
		_open_today_log_file()
	
	if log_file == null:
		return
	
	# Check file size
	if log_file.get_position() > MAX_LOG_SIZE:
		# Close and rename current file
		var old_path := current_log_path
		_close_log_file()
		var timestamp := Time.get_unix_time_from_system()
		var new_path := old_path.replace(".log", "_%d.log" % timestamp)
		DirAccess.rename_absolute(old_path, new_path)
		_open_today_log_file()
	
	# Write log entry
	var log_entry := {
		"timestamp": Time.get_unix_time_from_system(),
		"time": time_str,
		"level": level_str,
		"message": message,
		"context": context
	}
	
	log_file.store_line(JSON.stringify(log_entry))
	log_file.flush()

func _add_to_panel(level: LogLevel, formatted_msg: String, context: Dictionary) -> void:
	var log_entry := {
		"level": level,
		"message": formatted_msg,
		"time": Time.get_time_string_from_system(),
		"context": context
	}
	
	panel_logs.append(log_entry)
	
	# Limit panel log size
	if panel_logs.size() > MAX_PANEL_LOGS:
		panel_logs.pop_front()
	
	# Update panel if it exists
	if debug_panel != null and is_instance_valid(debug_panel):
		debug_panel.call_deferred("_update_logs")

func debug(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.DEBUG, message, context)

func info(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.INFO, message, context)

func warn(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.WARNING, message, context)

func error(message: String, context: Dictionary = {}) -> void:
	_log(LogLevel.ERROR, message, context)

func set_log_level(level: int) -> void:
	current_log_level = level as LogLevel
	info("Log level changed", {"new_level": get_log_level_name(level)})

func get_log_level() -> int:
	return current_log_level as int

func get_log_level_name(level: int) -> String:
	# Helper to get level name string from level integer
	match level:
		LEVEL_DEBUG: return "DEBUG"
		LEVEL_INFO: return "INFO"
		LEVEL_WARNING: return "WARNING"
		LEVEL_ERROR: return "ERROR"
		_: return "UNKNOWN"

func set_file_logging(enabled: bool) -> void:
	enable_file_logging = enabled
	if enabled:
		_setup_file_logging()
	else:
		_close_log_file()

func set_console_logging(enabled: bool) -> void:
	enable_console_logging = enabled

func set_panel_logging(enabled: bool) -> void:
	enable_panel_logging = enabled

func get_panel_logs() -> Array[Dictionary]:
	return panel_logs.duplicate()

func clear_panel_logs() -> void:
	panel_logs.clear()
	if debug_panel != null and is_instance_valid(debug_panel):
		debug_panel.call_deferred("_update_logs")

func register_debug_panel(panel: Control) -> void:
	debug_panel = panel

func unregister_debug_panel() -> void:
	debug_panel = null
