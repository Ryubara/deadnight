class_name NightView
extends Node3D
## What the player sees and hears of the night, made only from what the server sent: the zombies
## from each frame's snapshot, flashes, impacts and damage numbers from the weapons' events, and
## the sounds. It holds no game state and never asks the server anything.

## The sound of each weapon's shot and reload; a weapon with no entry is silent for now.
const SHOT_SOUNDS := {
	&"pistol": &"shot_pistol",
	&"smg": &"shot_smg",
	&"rifle": &"shot_rifle",
	&"shotgun": &"shot_shotgun",
}
const RELOAD_SOUNDS := {
	&"pistol": &"reload_pistol",
	&"smg": &"reload_smg",
	&"rifle": &"reload_rifle",
	&"shotgun": &"reload_shotgun",
}
## Lifts a burst of splinters to the middle of the boards.
const BOARD_LIFT := Vector3(0.0, 1.3, 0.0)
## Lifts a damage number off the wound.
const NUMBER_LIFT := Vector3(0.0, 0.3, 0.0)

var horde: ZombieHorde
var effects: ShotEffects
## Where each breach's boards stand (`NightWorld`): a board torn or mended shows a burst there.
var barricade_points: Dictionary[StringName, Vector3] = {}
## The lot's lamps, drawn from the generator's events (`show_lamps`).
var lamps: LotLamps
## The night's sounds besides the guns (`hear`).
var sounds: NightSounds
## The dead's voices and feet, made from the frames (`ZombieVoices`).
var voices: ZombieVoices
## Seconds between frames, for the views' animation.
var step := 1.0 / 60.0

var _state: ClientState


## `telegraphs` maps a look to the seconds its blow takes to land, `board_seconds` to the seconds
## it takes to pull one board off (both from the rules' tuning).
func setup(
	state: ClientState,
	camera: Camera3D,
	telegraphs: Dictionary[StringName, float] = {},
	board_seconds: Dictionary[StringName, float] = {}
) -> void:
	_state = state
	effects = ShotEffects.new()
	add_child(effects)
	horde = ZombieHorde.new()
	add_child(horde)
	horde.setup_client(camera, ZombieTuning.new().emerge_seconds, telegraphs, board_seconds)
	voices = ZombieVoices.new(Audio, 1)
	voices.windups = telegraphs
	state.event_received.connect(_on_event)


## Draws the lamps of `lot` as the rules' events switch them: starting as `fuel` says the night
## begins (the circuits on, the tank full), and following every circuit, the tank and the frames.
func show_lamps(lot: Node, fuel: FuelTuning) -> void:
	lamps = LotLamps.new(lot)
	lamps.configure(fuel)
	lamps.refresh(0)


## Starts the night's ambience and the sounds of its boards, doors, blows, till and voices, placed
## in `world`.
func hear(world: NightWorld) -> void:
	sounds = NightSounds.new()
	add_child(sounds)
	sounds.setup(_state, world)


func _on_event(event: Dictionary) -> void:
	if lamps != null:
		lamps.apply_event(event)
	voices.on_event(event)
	match event["type"]:
		&"frame":
			horde.apply_snapshot(event["zombies"], step)
			voices.update(_state.zombies, step)
		&"shot_fired":
			effects.shot(WeaponCatalog.get_def(event["weapon_id"]), event["muzzle"], event["ends"])
			_sound(SHOT_SOUNDS, event["weapon_id"], event["muzzle"])
		&"damage_dealt":
			effects.number(
				event["point"] + NUMBER_LIFT, str(roundi(event["damage"])), event["headshot"]
			)
		&"reload_started":
			_sound(RELOAD_SOUNDS, event["weapon_id"], null)
		&"fire_rejected":
			if event["reason"] == &"empty":
				Audio.play(&"dry_fire")
		&"round_started":
			Audio.play(&"round_start")
		&"round_ended":
			Audio.play(&"round_end")
		&"special_round_announced":
			Audio.play(&"special_round")
		&"projectile_burst":
			effects.spark(event["point"])
		&"board_torn", &"board_repaired":
			if event["type"] == &"board_torn":
				horde.tore(event.get("zombie_id", -1))
			var at: Variant = barricade_points.get(StringName(event["barricade_id"]))
			if at is Vector3:
				effects.spark(at + BOARD_LIFT)


func _sound(table: Dictionary, weapon_id: StringName, at: Variant) -> void:
	var id: StringName = table.get(weapon_id, &"")
	if id != &"":
		Audio.play(id, at)
