class_name SettingsService
extends Node
## The player's options: loaded from `user://settings.cfg`, applied the moment a value changes and
## written back shortly after. Registered as the autoload `Settings`.
##
## Values are plain data, keyed `section/name`. Every key has a default and a range, so a missing,
## hand-edited or wrong-typed entry falls back instead of breaking anything. Controls and shake
## values (mouse sensitivity, invert Y, camera shake) have nothing to apply here: gameplay reads
## them with `get_value` and listens to `changed`.

## Emitted after a value changes and has been applied.
signal changed(key: StringName, value: Variant)

enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }

const DEFAULT_PATH := "user://settings.cfg"
## What a test run, a capture and an agent's run get instead: no file, so nothing is read from or
## written to the person's own options (an empty path loads the defaults and saves nothing).
const HARNESS_PATH := ""
## Set to anything to take the harness path in a run the checks below do not recognise.
const HARNESS_ENV := "DEADNIGHT_NO_USER_FILES"
## Seconds after the last change before the file is written (a slider drag is one write).
const SAVE_DELAY := 0.6

const WINDOW_MODE := &"video/window_mode"
const RESOLUTION_SCALE := &"video/resolution_scale"
const VSYNC := &"video/vsync"
const VOLUME_MASTER := &"audio/master"
const VOLUME_MUSIC := &"audio/music"
const VOLUME_EFFECTS := &"audio/effects"
const VOLUME_VOICE := &"audio/voice"
const VOLUME_AMBIENCE := &"audio/ambience"
const VOLUME_UI := &"audio/ui"
const REDUCED_MOTION := &"accessibility/reduced_motion"
const UI_SCALE := &"accessibility/ui_scale"
## How much of the shot's view shake is drawn, in percent (0 is off). Reduced motion turns it
## off too.
const CAMERA_SHAKE := &"accessibility/camera_shake"
const MOUSE_SENSITIVITY := &"controls/mouse_sensitivity"
const INVERT_Y := &"controls/invert_y"
## Touch controls: 0 follows the device (a phone shows them), 1 always, 2 never (`TouchMode`).
const TOUCH_CONTROLS := &"controls/touch_controls"
const TOUCH_SCALE := &"controls/touch_scale"
const TOUCH_OPACITY := &"controls/touch_opacity"
const HAPTICS := &"controls/haptics"
## Touch only: how strongly the view is helped toward a zombie (0 is off, 1 the most). `AimAssist`.
const TOUCH_AIM_ASSIST := &"controls/touch_aim_assist"
## Touch only: 1 (the default) fires by itself while the player aims with the crosshair on a zombie
## and holds Aim while the thumb is on it; 0 leaves the trigger alone and makes Aim a toggle
## (`TouchAimAssist.AutoFire`, `TouchControls`). Auto-fire spends ammunition.
const TOUCH_AUTO_FIRE := &"controls/touch_auto_fire"
## The touch layout flipped for a left hand: the stick on the right, Fire and its buttons on the
## left, and the HUD's corner columns swap sides with them.
const LEFT_HANDED := &"controls/left_handed"
## Which first-run touch hints were used and are gone, one bit per hint (`TouchHints`). Resetting
## the defaults brings them back.
const TOUCH_HINTS_SEEN := &"controls/touch_hints_seen"
## Which challenge prompts show in the night: 0 all, 1 only finished challenges and milestone steps,
## 2 none (`HudChallenge.Mode`).
const CHALLENGE_PROMPTS := &"accessibility/challenge_prompts"
## Which progression popups show (`PopupLane.Mode`): 0 all, 1 big ones only (a level, a tier, a
## finished challenge), 2 none.
const PROGRESS_POPUPS := &"accessibility/progress_popups"
## The player's character look as JSON (`CharacterLook.to_json`); empty means the default look.
const CHARACTER_LOOK := &"character/look"
## The platform profile as last read, for the menu to show (`MenuProfile`): JSON, read-only on the
## client, empty until the backend (or a test) fills it. Nothing in the game writes progress here.
const PROFILE_CACHE := &"profile/cache"
## The weapon the menu's soldier holds (`WeaponCatalog` id, one that has a model). Cosmetic: a night
## starts with the starter program whatever is chosen here.
const SHOWCASE_WEAPON := &"loadout/weapon"
## The live 3D stage behind the menu: 0 follows the machine (it falls back to a still when frames
## run long), 1 always live, 2 always a still (`MenuStageQuality`).
const MENU_SCENE := &"video/menu_scene"
## The longest saved text accepted, so a damaged file cannot fill memory.
const MAX_TEXT := 4096

const DEFAULTS := {
	WINDOW_MODE: WindowMode.WINDOWED,
	RESOLUTION_SCALE: 100,
	VSYNC: true,
	VOLUME_MASTER: 100,
	VOLUME_MUSIC: 80,
	VOLUME_EFFECTS: 100,
	VOLUME_VOICE: 100,
	VOLUME_AMBIENCE: 80,
	VOLUME_UI: 80,
	REDUCED_MOTION: false,
	UI_SCALE: 1.0,
	CAMERA_SHAKE: 100,
	CHALLENGE_PROMPTS: 0,
	PROGRESS_POPUPS: 0,
	MOUSE_SENSITIVITY: 1.0,
	INVERT_Y: false,
	TOUCH_CONTROLS: 0,
	TOUCH_SCALE: 1.0,
	TOUCH_OPACITY: 0.7,
	HAPTICS: true,
	TOUCH_AIM_ASSIST: 0.5,
	TOUCH_AUTO_FIRE: 1,
	LEFT_HANDED: false,
	TOUCH_HINTS_SEEN: 0,
	CHARACTER_LOOK: "",
	PROFILE_CACHE: "",
	SHOWCASE_WEAPON: "rifle",
	MENU_SCENE: 0,
}

## Allowed range of each numeric value.
const RANGES := {
	WINDOW_MODE: Vector2(0, 2),
	RESOLUTION_SCALE: Vector2(50, 100),
	VOLUME_MASTER: Vector2(0, 100),
	VOLUME_MUSIC: Vector2(0, 100),
	VOLUME_EFFECTS: Vector2(0, 100),
	VOLUME_VOICE: Vector2(0, 100),
	VOLUME_AMBIENCE: Vector2(0, 100),
	VOLUME_UI: Vector2(0, 100),
	UI_SCALE: Vector2(0.8, 1.25),
	CAMERA_SHAKE: Vector2(0, 100),
	CHALLENGE_PROMPTS: Vector2(0, 2),
	PROGRESS_POPUPS: Vector2(0, 2),
	MOUSE_SENSITIVITY: Vector2(0.1, 3.0),
	TOUCH_CONTROLS: Vector2(0, 2),
	TOUCH_SCALE: Vector2(0.8, 1.4),
	TOUCH_OPACITY: Vector2(0.3, 1.0),
	TOUCH_AIM_ASSIST: Vector2(0.0, 1.0),
	TOUCH_AUTO_FIRE: Vector2(0, 1),
	TOUCH_HINTS_SEEN: Vector2(0, 255),
	MENU_SCENE: Vector2(0, 2),
}

## The audio bus each volume drives (the layout is `res://default_bus_layout.tres`).
const BUSES := {
	VOLUME_MASTER: &"Master",
	VOLUME_MUSIC: &"Music",
	VOLUME_EFFECTS: &"Effects",
	VOLUME_VOICE: &"Voice",
	VOLUME_AMBIENCE: &"Ambience",
	VOLUME_UI: &"UI",
}

## Where the file lives: `default_path()`. A test that wants a file of its own points this at one.
var path := default_path()
## How many times the file was written (a test counts the writes of a visit to a screen).
var write_count := 0
## True in a browser, which owns its window (window mode is not ours to set). Tests inject it.
var is_web := OS.has_feature("web")
## Takes the window mode instead of the real window when it is valid (a Callable taking a
## `DisplayServer.WindowMode`): a test sets one, so no test changes the display it runs on.
var window_setter := Callable()

var _values := {}
var _dirty := false
var _idle := 0.0
## Kept so the browser keeps the page-hide callback alive.
var _page_hide_callback: JavaScriptObject


## The one place that decides where the options are kept: the person's file, unless this is a test
## run (the GdUnit runner), a capture or autopilot scene of `res://tests/`, a run of the kit's
## `gds godot` (`GDS_QUIET`) or one that asks for it (`HARNESS_ENV`). Those keep them in memory: a
## suite that sets a value, or a service freed with a change pending, must never reach the file
## the person plays with (#418).
static func default_path() -> String:
	return HARNESS_PATH if is_harness_run() else DEFAULT_PATH


static func is_harness_run() -> bool:
	if OS.has_environment(HARNESS_ENV) or OS.get_environment("GDS_QUIET") == "1":
		return true
	for argument in OS.get_cmdline_args():
		if argument.begins_with("res://tests/") or argument.contains("gdUnit4"):
			return true
	return false


func _init() -> void:
	_values = DEFAULTS.duplicate()
	# The settings screen is opened from a pause menu: the debounced write has to run while the
	# tree is paused, or a change made there is lost on a crash or a closed browser tab.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _ready() -> void:
	load_from_disk()
	apply_all()
	_flush_when_the_page_hides()


func _process(delta: float) -> void:
	_idle += delta
	if _idle >= SAVE_DELAY:
		save()


func _notification(what: int) -> void:
	# A browser has no close request: losing focus or hiding the tab is the last chance to write.
	var last_chance := (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		or what == NOTIFICATION_PREDELETE
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
	)
	if last_chance and _dirty:
		save()


func get_value(key: StringName) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Sets, applies and schedules a save. An unknown key is ignored; a value of the wrong type or out
## of range is coerced the way loading would.
func set_value(key: StringName, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	var clean: Variant = _sanitize(key, value)
	if _values[key] == clean:
		return
	_values[key] = clean
	_apply(key)
	_dirty = true
	_idle = 0.0
	set_process(true)
	changed.emit(key, clean)


## Back to the shipped defaults (applied, saved).
func reset_defaults() -> void:
	for key: StringName in DEFAULTS:
		set_value(key, DEFAULTS[key])


## Reads the file. A missing or unreadable file, or a bad entry, leaves the default in place.
func load_from_disk() -> void:
	_values = DEFAULTS.duplicate()
	if path.is_empty():
		return
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key: StringName in DEFAULTS:
		var parts := String(key).split("/")
		_values[key] = _sanitize(key, file.get_value(parts[0], parts[1], DEFAULTS[key]))


## Writes the file now.
func save() -> Error:
	if path.is_empty():
		_dirty = false
		_idle = 0.0
		set_process(false)
		return OK
	var file := ConfigFile.new()
	for key: StringName in DEFAULTS:
		var parts := String(key).split("/")
		file.set_value(parts[0], parts[1], _values[key])
	_dirty = false
	_idle = 0.0
	set_process(false)
	write_count += 1
	return file.save(path)


## Applies every value; the startup call, and what a test uses to see the whole effect.
func apply_all() -> void:
	for key: StringName in DEFAULTS:
		_apply(key)


## The volume as a linear 0 to 1 factor, for code that mixes by hand.
func volume_linear(key: StringName) -> float:
	return float(get_value(key)) / 100.0


## On the web, `visibilitychange` (tab hidden, app switched, page closing on mobile) is the one
## event a page reliably gets before it can vanish, so it flushes a pending write.
func _flush_when_the_page_hides() -> void:
	if not OS.has_feature("web"):
		return
	_page_hide_callback = JavaScriptBridge.create_callback(_on_visibility_change)
	JavaScriptBridge.get_interface("document").addEventListener(
		"visibilitychange", _page_hide_callback
	)
	JavaScriptBridge.get_interface("window").addEventListener("pagehide", _page_hide_callback)


func _on_visibility_change(_args: Array) -> void:
	if _dirty:
		save()


func _sanitize(key: StringName, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	match typeof(fallback):
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else fallback
		TYPE_INT, TYPE_FLOAT:
			return _sanitize_number(key, value, fallback)
		TYPE_STRING:
			return _sanitize_text(value, fallback)
	return fallback


func _sanitize_number(key: StringName, value: Variant, fallback: Variant) -> Variant:
	if not _is_finite_number(value):
		return fallback
	var bounds: Vector2 = RANGES.get(key, Vector2(-INF, INF))
	if typeof(fallback) == TYPE_INT:
		return clampi(roundi(float(value)), int(bounds.x), int(bounds.y))
	return clampf(float(value), bounds.x, bounds.y)


func _sanitize_text(value: Variant, fallback: String) -> String:
	if typeof(value) != TYPE_STRING or String(value).length() > MAX_TEXT:
		return fallback
	return value


## A number a ConfigFile can hold that is neither `nan` nor infinite, which would pass a clamp
## (nan) or become a limit (inf) and be applied as if it were a choice.
func _is_finite_number(value: Variant) -> bool:
	match typeof(value):
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
	return false


func _apply(key: StringName) -> void:
	var value: Variant = _values[key]
	match key:
		WINDOW_MODE:
			_apply_window_mode(value)
		RESOLUTION_SCALE:
			if is_inside_tree():
				get_tree().root.scaling_3d_scale = float(value) / 100.0
		VSYNC:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED
			)
		REDUCED_MOTION:
			UIMotion.reduced = value
		UI_SCALE:
			if is_inside_tree():
				get_tree().root.content_scale_factor = value
		_:
			if BUSES.has(key):
				_apply_volume(BUSES[key], float(value) / 100.0)


func _apply_window_mode(mode: int) -> void:
	# A browser owns its window: the page (or Discord) decides, so there is nothing to set.
	if is_web:
		return
	var target := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == WindowMode.FULLSCREEN:
		target = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif mode == WindowMode.EXCLUSIVE:
		target = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_set_window_mode(target)


## The one call that touches the real window, so a test can stand in for it.
func _set_window_mode(target: DisplayServer.WindowMode) -> void:
	if window_setter.is_valid():
		window_setter.call(target)
	else:
		DisplayServer.window_set_mode(target)


func _apply_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
