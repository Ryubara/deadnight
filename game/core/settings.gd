class_name SettingsService
extends Node
## The player's options: loaded from `user://settings.cfg`, applied the moment a value changes and
## written back shortly after. Registered as the autoload `Settings`.
##
## Values are plain data, keyed `section/name`. Every key has a default and a range, so a missing,
## hand-edited or wrong-typed entry falls back instead of breaking anything. Controls values
## (mouse sensitivity, invert Y) have nothing to apply here: gameplay reads them with `get_value`
## and listens to `changed`.

## Emitted after a value changes and has been applied.
signal changed(key: StringName, value: Variant)

enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }

const DEFAULT_PATH := "user://settings.cfg"
## Seconds after the last change before the file is written (a slider drag is one write).
const SAVE_DELAY := 0.6

const WINDOW_MODE := &"video/window_mode"
const RESOLUTION_SCALE := &"video/resolution_scale"
const VSYNC := &"video/vsync"
const VOLUME_MASTER := &"audio/master"
const VOLUME_MUSIC := &"audio/music"
const VOLUME_EFFECTS := &"audio/effects"
const VOLUME_UI := &"audio/ui"
const REDUCED_MOTION := &"accessibility/reduced_motion"
const UI_SCALE := &"accessibility/ui_scale"
const MOUSE_SENSITIVITY := &"controls/mouse_sensitivity"
const INVERT_Y := &"controls/invert_y"

const DEFAULTS := {
	WINDOW_MODE: WindowMode.WINDOWED,
	RESOLUTION_SCALE: 100,
	VSYNC: true,
	VOLUME_MASTER: 100,
	VOLUME_MUSIC: 80,
	VOLUME_EFFECTS: 100,
	VOLUME_UI: 80,
	REDUCED_MOTION: false,
	UI_SCALE: 1.0,
	MOUSE_SENSITIVITY: 1.0,
	INVERT_Y: false,
}

## Allowed range of each numeric value.
const RANGES := {
	WINDOW_MODE: Vector2(0, 2),
	RESOLUTION_SCALE: Vector2(50, 100),
	VOLUME_MASTER: Vector2(0, 100),
	VOLUME_MUSIC: Vector2(0, 100),
	VOLUME_EFFECTS: Vector2(0, 100),
	VOLUME_UI: Vector2(0, 100),
	UI_SCALE: Vector2(0.8, 1.25),
	MOUSE_SENSITIVITY: Vector2(0.1, 3.0),
}

## The audio bus each volume drives (the layout is `res://default_bus_layout.tres`).
const BUSES := {
	VOLUME_MASTER: &"Master",
	VOLUME_MUSIC: &"Music",
	VOLUME_EFFECTS: &"Effects",
	VOLUME_UI: &"UI",
}

## Where the file lives. Tests point this somewhere else.
var path := DEFAULT_PATH

var _values := {}
var _dirty := false
var _idle := 0.0


func _init() -> void:
	_values = DEFAULTS.duplicate()
	set_process(false)


func _ready() -> void:
	load_from_disk()
	apply_all()


func _process(delta: float) -> void:
	_idle += delta
	if _idle >= SAVE_DELAY:
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _dirty:
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
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return
	for key: StringName in DEFAULTS:
		var parts := String(key).split("/")
		_values[key] = _sanitize(key, file.get_value(parts[0], parts[1], DEFAULTS[key]))


## Writes the file now.
func save() -> Error:
	var file := ConfigFile.new()
	for key: StringName in DEFAULTS:
		var parts := String(key).split("/")
		file.set_value(parts[0], parts[1], _values[key])
	_dirty = false
	_idle = 0.0
	set_process(false)
	return file.save(path)


## Applies every value; the startup call, and what a test uses to see the whole effect.
func apply_all() -> void:
	for key: StringName in DEFAULTS:
		_apply(key)


## The volume as a linear 0 to 1 factor, for code that mixes by hand.
func volume_linear(key: StringName) -> float:
	return float(get_value(key)) / 100.0


func _sanitize(key: StringName, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	match typeof(fallback):
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else fallback
		TYPE_INT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return fallback
			var bounds: Vector2 = RANGES.get(key, Vector2(-INF, INF))
			return clampi(roundi(float(value)), int(bounds.x), int(bounds.y))
		TYPE_FLOAT:
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return fallback
			var bounds: Vector2 = RANGES.get(key, Vector2(-INF, INF))
			return clampf(float(value), bounds.x, bounds.y)
	return fallback


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
	if OS.has_feature("web"):
		return
	var target := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == WindowMode.FULLSCREEN:
		target = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif mode == WindowMode.EXCLUSIVE:
		target = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(target)


func _apply_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, linear <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
