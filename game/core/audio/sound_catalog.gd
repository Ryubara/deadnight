class_name SoundCatalog
extends RefCounted
## Every sound by id. The files are rendered by `tools/audio/generate.py`; this table says how
## the game plays them. The design is `docs/design/audio.md`.

const ROOT := "res://assets/audio/"
const BUS_MUSIC := &"Music"
const BUS_EFFECTS := &"Effects"
const BUS_UI := &"UI"
const BUS_VOICE := &"Voice"
const BUS_AMBIENCE := &"Ambience"
## The level of the local player's own step at a walk, dB on the file (peak -6 dBFS): measured in
## `docs/research/audio.md` (footsteps) to sit well under the beds' swell and the guns.
const STEP_OWN_DB := -14.0

## How many voices a group may hold at once. Past it a louder or higher-priority sound takes the
## weakest voice; anything else is dropped.
const GROUP_LIMITS := {
	&"ui": 4,
	&"ui_hint": 1,
	&"challenge": 1,
	&"gun": 12,
	&"reload": 4,
	&"step": 8,
	&"step_own": 2,
	&"zombie_voice": 6,
	&"zombie_boss": 2,
	&"zombie_step": 5,
	&"generator": 2,
	&"grenade": 8,
	&"sting": 1,
	&"board": 4,
	&"door": 2,
	&"melee": 4,
	&"till": 2,
	&"soldier_voice": 3,
	&"bed": 4,
	# The arms and the lot (`ArmsCatalog`).
	&"gun_blast": 5,
	&"gun_tail": 4,
	&"impact": 6,
	&"swap": 2,
	&"breaker": 2,
	&"shop": 4,
	&"points": 2,
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


## `base` with `overrides` laid over it: an override wins. (`Dictionary.merged` keeps the base's
## value unless its second argument is true, which silently dropped overrides: issue #135.)
static func _with(base: Dictionary, overrides: Dictionary) -> Dictionary:
	return base.merged(overrides, true)


static func _add(id: StringName, path: String, count: int, options: Dictionary = {}) -> void:
	_defs[id] = SoundDef.make(id, ROOT + path, count, options)


static func _build() -> void:
	var ui := {"bus": BUS_UI, "group": &"ui", "pitch_semitones": 0.0, "priority": 90}
	var hint := {"bus": BUS_UI, "group": &"ui_hint", "pitch_semitones": 0.0, "cooldown": 0.05}
	_add(&"ui_hover", "ui/hover_%d.ogg", 1, hint)
	_add(&"ui_focus", "ui/focus_%d.ogg", 1, hint)
	_add(&"ui_tick", "ui/tick_%d.ogg", 1, _with(hint, {"cooldown": 0.02, "pitch_semitones": 1.0}))
	_add(&"ui_press", "ui/press_%d.ogg", 1, _with(ui, {"pitch_semitones": 0.3}))
	_add(&"ui_back", "ui/back_%d.ogg", 1, ui)
	_add(&"ui_push", "ui/push_%d.ogg", 1, _with(ui, {"volume_db": -3.0}))
	_add(&"ui_pop", "ui/pop_%d.ogg", 1, _with(ui, {"volume_db": -3.0}))
	# The challenge prompt's cues: quiet, and never two at once.
	var challenge := _with(ui, {"group": &"challenge", "priority": 60, "cooldown": 0.25})
	_add(&"challenge_tick", "ui/challenge_tick_%d.ogg", 1, challenge)
	_add(&"challenge_done", "ui/challenge_done_%d.ogg", 1, challenge)

	ArmsCatalog.build(_add)
	SoldierVoiceCatalog.build(_add)

	var step := {
		"group": &"step",
		"priority": 20,
		"pitch_semitones": 1.5,
		"max_distance": 30.0,
		"unit_size": 4.0,
		"near_cap_db": 0.0
	}
	_add(
		&"step_asphalt",
		"steps/asphalt_%d.ogg",
		8,
		_with(step, {"volume_db": -2.0, "cooldown": 0.0})
	)
	_add(
		&"step_gravel", "steps/gravel_%d.ogg", 8, _with(step, {"volume_db": -3.0, "cooldown": 0.0})
	)
	# The local player's own feet (`FootstepSounds`): flat, from the softer set, its own group so a
	# crowd's feet never take it. `volume_db` is the walking level, `STEP_OWN_DB`.
	var own_step := {
		"group": &"step_own",
		"priority": 25,
		"pitch_semitones": 1.0,
		"volume_db": STEP_OWN_DB,
		"max_distance": 30.0,
	}
	_add(&"step_own_asphalt", "steps/own_asphalt_%d.ogg", 8, own_step)
	_add(&"step_own_gravel", "steps/own_gravel_%d.ogg", 8, own_step)

	var zombie := {
		"group": &"zombie_voice", "pitch_semitones": 1.5, "unit_size": 6.0, "rear_cue": true
	}
	_add(
		&"zombie_groan",
		"zombie/groan_%d.ogg",
		7,
		_with(zombie, {"priority": 30, "max_distance": 40.0, "volume_db": -4.0})
	)
	_add(
		&"zombie_attack",
		"zombie/attack_%d.ogg",
		6,
		_with(zombie, {"priority": 60, "max_distance": 30.0})
	)
	_add(
		&"zombie_hurt",
		"zombie/hurt_%d.ogg",
		6,
		_with(zombie, {"priority": 50, "max_distance": 35.0, "volume_db": -2.0})
	)
	_add(
		&"zombie_death",
		"zombie/death_%d.ogg",
		5,
		_with(zombie, {"priority": 55, "max_distance": 40.0, "volume_db": -2.0})
	)

	_build_dead()

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
		_with(generator, {"volume_db": -8.0, "loop": true})
	)
	_add(
		&"generator_start", "world/generator_start_%d.ogg", 1, _with(generator, {"volume_db": -3.0})
	)

	var grenade := {"group": &"grenade", "max_distance": 70.0, "unit_size": 10.0}
	_add(
		&"grenade_tick",
		"grenade/tick_%d.ogg",
		1,
		_with(
			grenade,
			{"priority": 75, "pitch_semitones": 0.0, "max_distance": 30.0, "volume_db": -2.0}
		)
	)
	_add(
		&"grenade_throw",
		"grenade/throw_%d.ogg",
		2,
		_with(grenade, {"priority": 70, "pitch_semitones": 0.5, "max_distance": 30.0})
	)
	_add(
		&"grenade_bounce",
		"grenade/bounce_%d.ogg",
		3,
		_with(
			grenade, {"priority": 40, "pitch_semitones": 1.0, "cooldown": 0.05, "volume_db": -4.0}
		)
	)
	_add(
		&"grenade_blast",
		"grenade/blast_%d.ogg",
		2,
		_with(
			grenade,
			{"priority": 95, "pitch_semitones": 0.8, "max_distance": 120.0, "unit_size": 20.0}
		)
	)

	var sting := {"bus": BUS_MUSIC, "group": &"sting", "priority": 95, "pitch_semitones": 0.0}
	_add(
		&"round_start",
		"stings/round_start_%d.ogg",
		1,
		_with(sting, {"volume_db": -3.0, "duck_db": -9.0, "duck_hold": 1.6})
	)
	_add(
		&"round_end",
		"stings/round_end_%d.ogg",
		1,
		_with(sting, {"volume_db": -5.0, "duck_db": -5.0, "duck_hold": 0.8})
	)
	_add(
		&"special_round",
		"stings/special_round_%d.ogg",
		1,
		# Above the other stings: the announcement comes the moment the last round ends, while its
		# `round_end` sting still sounds, and one sting at a time (`GROUP_LIMITS`) must give way.
		_with(sting, {"volume_db": -3.0, "duck_db": -9.0, "duck_hold": 2.2, "priority": 98})
	)


## The dead's voices and feet, per type (`ZombieVoiceTable` says which look uses which). Each has
## `rear_cue`: heard from behind it is darker, so the side it comes from can be told.
static func _build_dead() -> void:
	var voice := {
		"group": &"zombie_voice",
		"pitch_semitones": 1.2,
		"unit_size": 6.0,
		"rear_cue": true,
	}
	var calls := {"priority": 65, "max_distance": 45.0, "volume_db": -2.0}
	_add(&"zombie_alert", "zombie/alert_%d.ogg", 6, _with(voice, calls))
	_add(
		&"zombie_grunt",
		"zombie/grunt_%d.ogg",
		3,
		_with(voice, {"priority": 62, "max_distance": 30.0, "volume_db": -3.0})
	)
	_add(
		&"zombie_shriek",
		"zombie/shriek_%d.ogg",
		5,
		_with(voice, {"priority": 66, "max_distance": 50.0, "volume_db": -5.0})
	)
	_add(
		&"zombie_breath_brute",
		"zombie/breath_brute_%d.ogg",
		3,
		_with(voice, {"priority": 25, "max_distance": 26.0, "volume_db": -3.0})
	)
	_add(
		&"zombie_groan_brute",
		"zombie/groan_brute_%d.ogg",
		5,
		_with(voice, {"priority": 32, "max_distance": 40.0, "volume_db": -3.0})
	)
	_add(
		&"zombie_groan_crawler",
		"zombie/groan_crawler_%d.ogg",
		5,
		_with(voice, {"priority": 30, "max_distance": 30.0, "volume_db": -4.0})
	)
	var boss := {
		"group": &"zombie_boss",
		"pitch_semitones": 0.4,
		"unit_size": 7.0,
		"max_distance": 90.0,
		"rear_cue": true,
	}
	_add(&"zombie_roar", "zombie/roar_%d.ogg", 4, _with(boss, {"priority": 88, "volume_db": -7.0}))
	_add(
		&"zombie_growl_boss",
		"zombie/growl_boss_%d.ogg",
		2,
		_with(boss, {"priority": 86, "max_distance": 70.0, "volume_db": -6.0})
	)
	var foot := {
		"group": &"zombie_step",
		"priority": 15,
		"pitch_semitones": 1.5,
		"unit_size": 4.0,
		"max_distance": 28.0,
		"rear_cue": true,
	}
	_add(&"zombie_step_shuffle", "zombie/step_shuffle_%d.ogg", 4, _with(foot, {"volume_db": -6.0}))
	_add(&"zombie_step_run", "zombie/step_run_%d.ogg", 4, _with(foot, {"volume_db": -6.0}))
	_add(
		&"zombie_step_stomp",
		"zombie/step_stomp_%d.ogg",
		3,
		_with(foot, {"volume_db": -3.0, "max_distance": 40.0, "unit_size": 6.0})
	)
	_add(
		&"zombie_drag",
		"zombie/drag_%d.ogg",
		4,
		_with(foot, {"priority": 18, "volume_db": -5.0, "max_distance": 24.0})
	)

	_build_night()


## The night's own sounds: the boards, doors, blows, the till, the player's voice, and the beds
## (ambience and score) that loop under it all.
static func _build_night() -> void:
	var board := {
		"group": &"board",
		"priority": 65,
		"pitch_semitones": 0.8,
		"max_distance": 70.0,
		"unit_size": 9.0,
		"volume_db": 2.0
	}
	_add(&"board_tear", "world/board_tear_%d.ogg", 3, board)
	_add(
		&"board_last",
		"world/board_last_%d.ogg",
		2,
		_with(board, {"priority": 75, "max_distance": 90.0, "unit_size": 12.0, "volume_db": 4.0})
	)
	_add(
		&"board_repair",
		"world/board_repair_%d.ogg",
		3,
		_with(board, {"max_distance": 40.0, "unit_size": 7.0, "volume_db": 3.0})
	)
	_add(
		&"door_open",
		"world/door_open_%d.ogg",
		2,
		{
			"group": &"door",
			"priority": 70,
			"pitch_semitones": 0.6,
			"max_distance": 60.0,
			"unit_size": 10.0,
			"volume_db": -2.0
		}
	)
	var melee := {
		"group": &"melee",
		"priority": 70,
		"pitch_semitones": 1.0,
		"max_distance": 30.0,
		"unit_size": 5.0
	}
	_add(&"melee_swing", "melee/swing_%d.ogg", 3, _with(melee, {"volume_db": -3.0}))
	_add(&"melee_hit", "melee/hit_%d.ogg", 2, _with(melee, {"priority": 72, "max_distance": 35.0}))
	_add(
		&"till_ring",
		"shop/till_%d.ogg",
		2,
		{
			"group": &"till",
			"priority": 65,
			"pitch_semitones": 0.4,
			"max_distance": 30.0,
			"unit_size": 8.0,
			"volume_db": -4.0
		}
	)

	var bed := {
		"bus": BUS_AMBIENCE, "group": &"bed", "loop": true, "pitch_semitones": 0.0, "priority": 10
	}
	_add(&"bed_crickets", "ambience/crickets_%d.ogg", 1, _with(bed, {"volume_db": -18.5}))
	_add(&"bed_highway", "ambience/highway_%d.ogg", 1, _with(bed, {"volume_db": -18.0}))
	_add(
		&"bed_projector",
		"ambience/projector_%d.ogg",
		1,
		_with(bed, {"volume_db": -14.0, "max_distance": 35.0, "unit_size": 4.0})
	)
	_add(&"bed_score", "music/score_%d.ogg", 1, _with(bed, {"bus": BUS_MUSIC, "volume_db": -20.1}))
