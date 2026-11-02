class_name ArmsCatalog
extends RefCounted
## The weapons' and the lot's machines' sounds, added to `SoundCatalog` by `build`. Kept in a file
## of its own so the catalog stays a table of groups; the design is `docs/design/audio.md`.
##
## A gunshot is three layers, each on its own voice with its own random variant and pitch, so no
## two shots are the same sound: the report (`shot_*`: transient and body, synthesised), a
## generated blast (`blast_*`: body and roll, ElevenLabs) and a synthesised tail (`tail_*`, played a
## few hundredths late). The files are `tools/audio/weapon_recipes.py` and `elevenlabs.py`.


## Adds every sound; `add` is `SoundCatalog._add` (id, path under the audio folder, variants,
## options).
static func build(add: Callable) -> void:
	var gun := {
		"near_cap_db": 0.0,
		"group": &"gun",
		"priority": 80,
		"pitch_semitones": 0.6,
		"max_distance": 90.0,
		"unit_size": 14.0
	}
	var blast := {
		"near_cap_db": 0.0,
		"group": &"gun_blast",
		"priority": 55,
		"pitch_semitones": 1.0,
		"max_distance": 90.0,
		"unit_size": 14.0,
		"volume_db": -9.0
	}
	var tail := {
		"near_cap_db": 0.0,
		"group": &"gun_tail",
		"priority": 40,
		"pitch_semitones": 0.8,
		"max_distance": 90.0,
		"unit_size": 18.0,
		"volume_db": -13.0
	}
	# Report, blast and tail of each firearm. An automatic gun's blast and tail get a cooldown, so
	# twelve shots a second are twelve reports over a roll and not a wall of tails.
	var guns := {
		&"pistol": [-3.0, 0.0, 0.0],
		&"smg": [-6.0, 0.14, 0.22],
		&"rifle": [-3.0, 0.0, 0.0],
		&"shotgun": [-2.0, 0.0, 0.0],
	}
	for weapon: StringName in guns:
		var trims: Array = guns[weapon]
		var shot_options := SoundCatalog._with(gun, {"volume_db": trims[0]})
		if weapon == &"smg":
			shot_options["pitch_semitones"] = 0.8
		add.call(StringName("shot_%s" % weapon), "guns/shot_%s_%%d.ogg" % weapon, 5, shot_options)
		add.call(
			StringName("blast_%s" % weapon),
			"eleven/blast_%s_%%d.ogg" % weapon,
			3,
			SoundCatalog._with(blast, {"cooldown": trims[1]})
		)
		add.call(
			StringName("tail_%s" % weapon),
			"guns/tail_%s_%%d.ogg" % weapon,
			3,
			SoundCatalog._with(tail, {"cooldown": trims[2]})
		)
	add.call(
		&"shot_flare", "guns/shot_flare_%d.ogg", 3, SoundCatalog._with(gun, {"volume_db": -6.0})
	)
	add.call(
		&"burst_flare",
		"guns/burst_flare_%d.ogg",
		2,
		SoundCatalog._with(gun, {"priority": 60, "volume_db": -9.0, "max_distance": 70.0})
	)
	add.call(
		&"dry_fire",
		"guns/dry_fire_%d.ogg",
		1,
		SoundCatalog._with(gun, {"priority": 70, "max_distance": 20.0, "cooldown": 0.12})
	)
	add.call(
		&"weapon_swap",
		"guns/weapon_swap_%d.ogg",
		3,
		SoundCatalog._with(
			gun,
			{
				"group": &"swap",
				"priority": 55,
				"max_distance": 25.0,
				"unit_size": 5.0,
				"volume_db": -4.0
			}
		)
	)

	var impact := {
		"near_cap_db": 0.0,
		"group": &"impact",
		"priority": 50,
		"pitch_semitones": 1.5,
		"max_distance": 50.0,
		"unit_size": 8.0,
		"cooldown": 0.02
	}
	add.call(
		&"impact_flesh",
		"guns/impact_flesh_%d.ogg",
		4,
		SoundCatalog._with(impact, {"volume_db": -3.0})
	)
	add.call(
		&"impact_head",
		"guns/impact_head_%d.ogg",
		4,
		SoundCatalog._with(impact, {"priority": 58, "volume_db": -1.0})
	)
	add.call(
		&"impact_world",
		"guns/impact_world_%d.ogg",
		4,
		SoundCatalog._with(impact, {"volume_db": -6.0})
	)

	# Reload steps: one sound per event frame of the reload clip.
	var step := {
		"near_cap_db": 0.0,
		"group": &"reload",
		"priority": 60,
		"max_distance": 25.0,
		"unit_size": 5.0,
		"volume_db": -1.0,
		"pitch_semitones": 0.5
	}
	var steps := {
		&"reload_pistol_mag_out": 2,
		&"reload_pistol_mag_in": 2,
		&"reload_smg_mag_out": 2,
		&"reload_smg_mag_in": 2,
		&"reload_rifle_round": 3,
		&"reload_rifle_lever": 2,
		&"reload_shotgun_open": 2,
		&"reload_shotgun_shells": 2,
		&"reload_shotgun_shut": 2,
	}
	for id: StringName in steps:
		add.call(id, "guns/%s_%%d.ogg" % id, steps[id], step)

	_build_world(add)


static func _build_world(add: Callable) -> void:
	var machine := {
		"near_cap_db": 0.0,
		"group": &"generator",
		"priority": 72,
		"max_distance": 55.0,
		"unit_size": 10.0,
		"pitch_semitones": 0.0
	}
	add.call(
		&"generator_engine",
		"eleven/generator_hum_%d.ogg",
		1,
		SoundCatalog._with(machine, {"volume_db": -12.0, "loop": true})
	)
	add.call(
		&"generator_sputter",
		"world/generator_sputter_%d.ogg",
		3,
		SoundCatalog._with(machine, {"volume_db": -3.0, "pitch_semitones": 1.0})
	)
	add.call(
		&"generator_down",
		"world/generator_down_%d.ogg",
		1,
		SoundCatalog._with(machine, {"volume_db": -3.0})
	)
	add.call(
		&"generator_down_air",
		"eleven/generator_down_%d.ogg",
		1,
		SoundCatalog._with(machine, {"volume_db": -7.0})
	)
	add.call(
		&"generator_up",
		"eleven/generator_up_%d.ogg",
		1,
		SoundCatalog._with(machine, {"volume_db": -6.0})
	)

	var breaker := {
		"near_cap_db": 0.0,
		"group": &"breaker",
		"priority": 65,
		"max_distance": 40.0,
		"unit_size": 7.0,
		"pitch_semitones": 0.6
	}
	add.call(&"breaker_on", "world/breaker_on_%d.ogg", 2, breaker)
	add.call(&"breaker_off", "world/breaker_off_%d.ogg", 2, breaker)

	var shop := {
		"near_cap_db": 0.0,
		"group": &"shop",
		"priority": 65,
		"max_distance": 35.0,
		"unit_size": 6.0,
		"pitch_semitones": 0.5
	}
	add.call(&"door_unlock", "world/door_unlock_%d.ogg", 2, shop)
	add.call(
		&"door_buy", "eleven/door_buy_%d.ogg", 2, SoundCatalog._with(shop, {"volume_db": -7.0})
	)
	add.call(&"buy_weapon", "world/buy_weapon_%d.ogg", 2, shop)
	add.call(&"buy_ammo", "world/buy_ammo_%d.ogg", 2, shop)
	add.call(&"buy_fuel", "world/buy_fuel_%d.ogg", 1, SoundCatalog._with(shop, {"volume_db": -3.0}))
	add.call(
		&"buy_tonic", "world/buy_tonic_%d.ogg", 1, SoundCatalog._with(shop, {"volume_db": -3.0})
	)
	# The re-cut bench: the motor, the press' blow at 0.8 s (the machine strikes then), the bell
	# at 1.55 s.
	add.call(&"buy_recut", "world/buy_recut_%d.ogg", 1, SoundCatalog._with(shop, {"priority": 66}))

	# The prize crane's moments (`WorldSounds`, from the rules' `crane_*` events): the wheel
	# spinning down, the claw, the prize, a breakdown and the machine moving to a new spot.
	var crane := SoundCatalog._with(shop, {"priority": 68, "max_distance": 45.0, "unit_size": 8.0})
	for id: StringName in [&"crane_spin", &"crane_claw_drop", &"crane_claw_lift", &"crane_prize"]:
		add.call(id, "world/%s_%%d.ogg" % id, 1, crane)
	add.call(&"crane_break", "world/crane_break_%d.ogg", 1, crane)
	add.call(&"crane_move", "world/crane_move_%d.ogg", 1, crane)

	var flat := {"bus": &"UI", "pitch_semitones": 0.0}
	add.call(
		&"deny",
		"world/deny_%d.ogg",
		1,
		SoundCatalog._with(
			flat, {"group": &"shop", "priority": 88, "cooldown": 0.15, "volume_db": -4.0}
		)
	)
	add.call(
		&"points_tick",
		"ui/points_tick_%d.ogg",
		1,
		SoundCatalog._with(
			flat, {"group": &"points", "priority": 30, "cooldown": 0.03, "pitch_semitones": 0.4}
		)
	)
	add.call(
		&"points_kill",
		"ui/points_kill_%d.ogg",
		1,
		SoundCatalog._with(
			flat, {"group": &"points", "priority": 35, "cooldown": 0.05, "pitch_semitones": 0.3}
		)
	)
	add.call(
		&"bed_tension",
		"music/tension_%d.ogg",
		1,
		{
			"bus": &"Music",
			"group": &"bed",
			"loop": true,
			"pitch_semitones": 0.0,
			"priority": 10,
			"volume_db": -20.0
		}
	)
