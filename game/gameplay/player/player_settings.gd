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
const KEY_CAMERA_SHAKE := &"accessibility/camera_shake"
const KEY_REDUCED_MOTION := &"accessibility/reduced_motion"
const DEFAULT_CAMERA_SHAKE := 100
const DEFAULT_SENSITIVITY := 1.0
const DEFAULT_INVERT_Y := false
const MIN_SENSITIVITY := 0.1


static func sensitivity(tree: SceneTree) -> float:
	var value: Variant = _read(tree, KEY_SENSITIVITY, DEFAULT_SENSITIVITY)
	if value is float or value is int:
		return maxf(float(value), MIN_SENSITIVITY)
	return DEFAULT_SENSITIVITY


## How much of the shot shake the player wants, 0 to 1: the camera shake setting (a percent),
## and none at all while reduced motion is on.
static func camera_shake(tree: SceneTree) -> float:
	if _read(tree, KEY_REDUCED_MOTION, false) == true:
		return 0.0
	var value: Variant = _read(tree, KEY_CAMERA_SHAKE, DEFAULT_CAMERA_SHAKE)
	if value is float or value is int:
		return clampf(float(value) / 100.0, 0.0, 1.0)
	return DEFAULT_CAMERA_SHAKE / 100.0


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
