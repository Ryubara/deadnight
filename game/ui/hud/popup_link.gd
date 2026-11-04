class_name PopupLink
extends RefCounted
## Joins a popup lane to the player's settings and to the sound: the setting decides which cards
## show (`PopupLane.Mode`, kept current while the player changes it) and each card that starts
## plays its cue through the menu's sound table (`Audio.play_ui`, the cues of
## `UiSoundTable.PROGRESS_CUES`). Whoever owns the lane holds the link for as long as the lane
## plays.

var _lane: PopupLane
var _settings: SettingsService


## `settings` is the player's (the `Settings` autoload); a test passes its own.
func _init(lane: PopupLane, settings: SettingsService = null) -> void:
	_lane = lane
	_settings = settings if settings != null else Settings
	lane.cue.connect(_on_cue)
	_apply()
	_settings.changed.connect(_on_setting)


func _on_cue(cue: StringName) -> void:
	Audio.play_ui(cue)


func _on_setting(key: StringName, _value: Variant) -> void:
	if key == SettingsService.PROGRESS_POPUPS:
		_apply()


func _apply() -> void:
	_lane.mode = int(_settings.get_value(SettingsService.PROGRESS_POPUPS)) as PopupLane.Mode
