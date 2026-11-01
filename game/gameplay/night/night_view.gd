class_name NightView
extends Node3D
## What the player sees and hears of the night, made only from what the server sent: the zombies
## from each frame's snapshot, tracers, flashes and damage numbers from the weapons' events, and
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
## Lifts a damage number off the wound.
const NUMBER_LIFT := Vector3(0.0, 0.3, 0.0)

var horde: ZombieHorde
var effects: ShotEffects
## The lot's lamps, drawn from the generator's events (`show_lamps`).
var lamps: LotLamps
## Seconds between frames, for the views' animation.
var step := 1.0 / 60.0

var _state: ClientState


## `telegraphs` maps a look to the seconds its blow takes to land (from the rules' roster).
func setup(
	state: ClientState, camera: Camera3D, telegraphs: Dictionary[StringName, float] = {}
) -> void:
	_state = state
	effects = ShotEffects.new()
	add_child(effects)
	horde = ZombieHorde.new()
	add_child(horde)
	horde.setup_client(camera, ZombieTuning.new().emerge_seconds, telegraphs)
	state.event_received.connect(_on_event)


## Draws the lamps of `lot` as the rules' events switch them: starting as `fuel` says the night
## begins (the circuits on, the tank full), and following every circuit, the tank and the frames.
func show_lamps(lot: Node, fuel: FuelTuning) -> void:
	lamps = LotLamps.new(lot)
	lamps.configure(fuel)
	lamps.refresh(0)


func _on_event(event: Dictionary) -> void:
	if lamps != null:
		lamps.apply_event(event)
	match event["type"]:
		&"frame":
			horde.apply_snapshot(event["zombies"], step)
		&"shot_fired":
			effects.muzzle_flash(event["muzzle"])
			for end: Vector3 in event["ends"]:
				effects.tracer(event["muzzle"], end)
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
		&"projectile_burst":
			effects.spark(event["point"])


func _sound(table: Dictionary, weapon_id: StringName, at: Variant) -> void:
	var id: StringName = table.get(weapon_id, &"")
	if id != &"":
		Audio.play(id, at)
