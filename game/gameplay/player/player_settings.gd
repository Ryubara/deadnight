class_name PlayerSettings
extends RefCounted
## Reads the look settings the player cares about from the game's settings service.
##
## Asks the game's `Settings` autoload (`core/settings.gd`): `get_value(key)` and the
## `changed(key, value)` signal. Without it (a test room run on its own) or with an odd answer,
## the defaults below apply, so the player always works.

const SERVICE_PATH := ^"/root/Settings"
const KEY_SENSITIVITY := &"controls/mouse_sensitivity"
const KEY_INVERT_Y := &"controls/invert_y"
const DEFAULT_SENSITIVITY := 1.0
const DEFAULT_INVERT_Y := false
const MIN_SENSITIVITY := 0.1


static func sensitivity(tree: SceneTree) -> float:
	var value: Variant = _read(tree, KEY_SENSITIVITY, DEFAULT_SENSITIVITY)
	if value is float or value is int:
		return maxf(float(value), MIN_SENSITIVITY)
	return DEFAULT_SENSITIVITY


static func invert_y(tree: SceneTree) -> bool:
	var value: Variant = _read(tree, KEY_INVERT_Y, DEFAULT_INVERT_Y)
	return value if value is bool else DEFAULT_INVERT_Y


static func _read(tree: SceneTree, key: StringName, default: Variant) -> Variant:
	if tree == null:
		return default
	var service := tree.root.get_node_or_null(SERVICE_PATH)
	if service == null or not service.has_method(&"get_value"):
		return default
	var value: Variant = service.call(&"get_value", key)
	return default if value == null else value
