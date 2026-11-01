class_name TouchMode
extends RefCounted
## Whether the touch controls show. The setting `controls/touch_controls` decides: Auto follows the
## device (a phone or tablet in a browser, an Android or iOS build), On and Off force it. A debug
## flag forces them on a desktop: `--touch` on the command line (after `--` for the engine), the
## environment variable `DEADNIGHT_TOUCH=1`, or `?touch=1` on the web page's address.

enum Choice { AUTO, ON, OFF }

const FLAG := "--touch"
const ENV := "DEADNIGHT_TOUCH"
const QUERY := "touch=1"
const SETTING_PATH := ^"/root/Settings"

## Tests set this to stand in for the device.
static var device_is_touch: Variant = null


## True when the touch controls should be on screen now.
static func wanted(tree: SceneTree) -> bool:
	match choice(tree):
		Choice.ON:
			return true
		Choice.OFF:
			return false
	return debug_forced() or detect()


static func choice(tree: SceneTree) -> int:
	var service := tree.root.get_node_or_null(SETTING_PATH) if tree != null else null
	if service == null or not service.has_method(&"get_value"):
		return Choice.AUTO
	var value: Variant = service.call(&"get_value", &"controls/touch_controls")
	return clampi(int(value), Choice.AUTO, Choice.OFF) if value is int else Choice.AUTO


## A phone or tablet: the primary pointer is a finger. Not a laptop with a touchscreen.
static func detect() -> bool:
	if device_is_touch != null:
		return device_is_touch
	if OS.has_feature("web"):
		# A number, not a boolean: the bridge hands back whichever it likes, `int()` reads both.
		var script := "(navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches) ? 1 : 0"
		var answer: Variant = JavaScriptBridge.eval(script, true)
		return answer != null and int(answer) == 1
	return OS.has_feature("android") or OS.has_feature("ios")


static func debug_forced() -> bool:
	if FLAG in OS.get_cmdline_user_args() or FLAG in OS.get_cmdline_args():
		return true
	if OS.get_environment(ENV) == "1":
		return true
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		return search is String and QUERY in (search as String)
	return false
