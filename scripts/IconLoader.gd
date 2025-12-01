extends RefCounted
class_name IconLoader

# Utility class for loading SVG icons from assets/icons directory
# Godot automatically imports SVG files as textures, so we can load them directly

static func load_icon(icon_name: String) -> Texture2D:
	"""
	Load an SVG icon and return it as a Texture2D.
	Godot automatically imports SVG files, so we can load them as textures.
	
	Args:
		icon_name: Name of the icon file (without .svg extension)
	
	Returns:
		Texture2D or null if loading fails
	"""
	var path := "res://assets/icons/%s.svg" % icon_name
	if not ResourceLoader.exists(path):
		push_error("Icon not found: " + path)
		return null
	
	# Try loading as texture (Godot imports SVG as texture)
	var texture := load(path) as Texture2D
	if texture == null:
		# If direct load fails, try using ResourceLoader
		texture = ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
		if texture == null:
			push_error("Failed to load icon as texture: " + path)
			return null
	
	return texture

