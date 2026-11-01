class_name SoundCatalog
extends RefCounted
## Every sound by id. The files are rendered by `tools/audio/generate.py`; this table says how
## the game plays them. The design is `docs/design/audio.md`.

const ROOT := "res://assets/audio/"
const BUS_MUSIC := &"Music"
const BUS_EFFECTS := &"Effects"
const BUS_UI := &"UI"

## How many voices a group may hold at once. Past it a louder or higher-priority sound takes the
## weakest voice; anything else is dropped.
const GROUP_LIMITS := {
	&"ui": 4,
	&"ui_hint": 1,
	&"gun": 12,
	&"reload": 3,
	&"step": 8,
	&"zombie_voice": 6,
	&"generator": 2,
	&"sting": 1,
}

## What `UIAudio` cues play (the gds_ui addon names the cues and ships no sounds).
const UI_CUES := {
	&"hover": &"ui_hover",
	&"focus": &"ui_focus",
	&"press": &"ui_press",
	&"back": &"ui_back",
	&"push": &"ui_push",
	&"pop": &"ui_pop",
	&"tick": &"ui_tick",
}

static var _defs := {}


static func get_def(id: StringName) -> SoundDef:
	if _defs.is_empty():
		_build()
	return _defs.get(id)


static func ids() -> Array:
	if _defs.is_empty():
		_build()
	return _defs.keys()


static func _add(id: StringName, path: String, count: int, options: Dictionary = {}) -> void:
	_defs[id] = SoundDef.make(id, ROOT + path, count, options)


static func _build() -> void:
	var ui := {"bus": BUS_UI, "group": &"ui", "pitch_semitones": 0.0, "priority": 90}
	var hint := {"bus": BUS_UI, "group": &"ui_hint", "pitch_semitones": 0.0, "cooldown": 0.05}
	_add(&"ui_hover", "ui/hover_%d.ogg", 1, hint)
	_add(&"ui_focus", "ui/focus_%d.ogg", 1, hint)
	_add(&"ui_tick", "ui/tick_%d.ogg", 1, hint.merged({"cooldown": 0.02, "pitch_semitones": 1.0}))
	_add(&"ui_press", "ui/press_%d.ogg", 1, ui.merged({"pitch_semitones": 0.3}))
	_add(&"ui_back", "ui/back_%d.ogg", 1, ui)
	_add(&"ui_push", "ui/push_%d.ogg", 1, ui.merged({"volume_db": -3.0}))
	_add(&"ui_pop", "ui/pop_%d.ogg", 1, ui.merged({"volume_db": -3.0}))

	var gun := {
		"group": &"gun",
		"priority": 80,
		"pitch_semitones": 0.6,
		"max_distance": 90.0,
		"unit_size": 14.0
	}
	_add(&"shot_pistol", "guns/shot_pistol_%d.ogg", 3, gun.merged({"volume_db": -2.0}))
	_add(
		&"shot_smg",
		"guns/shot_smg_%d.ogg",
		3,
		gun.merged({"volume_db": -4.0, "pitch_semitones": 0.8})
	)
	_add(&"shot_rifle", "guns/shot_rifle_%d.ogg", 3, gun)
	_add(&"shot_shotgun", "guns/shot_shotgun_%d.ogg", 3, gun.merged({"volume_db": 1.0}))
	_add(
		&"dry_fire",
		"guns/dry_fire_%d.ogg",
		1,
		gun.merged({"priority": 70, "max_distance": 20.0, "cooldown": 0.12})
	)
	var reload := {
		"group": &"reload",
		"priority": 60,
		"max_distance": 25.0,
		"unit_size": 5.0,
		"volume_db": -5.0
	}
	for weapon: String in ["pistol", "smg", "rifle", "shotgun"]:
		_add(StringName("reload_" + weapon), "guns/reload_%s_%%d.ogg" % weapon, 2, reload)

	var step := {
		"group": &"step",
		"priority": 20,
		"pitch_semitones": 1.5,
		"max_distance": 30.0,
		"unit_size": 4.0
	}
	_add(
		&"step_asphalt",
		"steps/asphalt_%d.ogg",
		4,
		step.merged({"volume_db": -5.0, "cooldown": 0.12})
	)
	_add(
		&"step_gravel", "steps/gravel_%d.ogg", 4, step.merged({"volume_db": -6.0, "cooldown": 0.12})
	)

	var zombie := {"group": &"zombie_voice", "pitch_semitones": 1.5, "unit_size": 6.0}
	_add(
		&"zombie_groan",
		"zombie/groan_%d.ogg",
		4,
		zombie.merged({"priority": 30, "max_distance": 40.0, "volume_db": -4.0})
	)
	_add(
		&"zombie_attack",
		"zombie/attack_%d.ogg",
		3,
		zombie.merged({"priority": 60, "max_distance": 30.0})
	)
	_add(
		&"zombie_hurt",
		"zombie/hurt_%d.ogg",
		3,
		zombie.merged({"priority": 50, "max_distance": 35.0, "volume_db": -2.0})
	)
	_add(
		&"zombie_death",
		"zombie/death_%d.ogg",
		2,
		zombie.merged({"priority": 55, "max_distance": 40.0, "volume_db": -2.0})
	)

	var generator := {
		"group": &"generator",
		"priority": 70,
		"max_distance": 45.0,
		"unit_size": 10.0,
		"pitch_semitones": 0.0
	}
	_add(
		&"generator_hum",
		"world/generator_hum_%d.ogg",
		1,
		generator.merged({"volume_db": -8.0, "loop": true})
	)
	_add(
		&"generator_start", "world/generator_start_%d.ogg", 1, generator.merged({"volume_db": -3.0})
	)

	var sting := {"bus": BUS_MUSIC, "group": &"sting", "priority": 95, "pitch_semitones": 0.0}
	_add(
		&"round_start",
		"stings/round_start_%d.ogg",
		1,
		sting.merged({"volume_db": -3.0, "duck_db": -9.0, "duck_hold": 1.6})
	)
	_add(
		&"round_end",
		"stings/round_end_%d.ogg",
		1,
		sting.merged({"volume_db": -5.0, "duck_db": -5.0, "duck_hold": 0.8})
	)
