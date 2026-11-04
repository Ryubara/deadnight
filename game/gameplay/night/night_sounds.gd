class_name NightSounds
extends Node3D
## What the night sounds like besides the guns, made only from what the server sent: the ambient
## bed (crickets and a distant highway everywhere, the projector in its booth), the score in the
## breaks, the boards at the fence, doors, melee blows, the till and every player's feet
## (`FootstepSounds`, its child). It holds no game state and asks the server nothing. The soldiers'
## voices are `SoldierVoice`'s. The design is `docs/design/audio.md`.

## Lifts a sound off the ground to the middle of the boards, and to a player's head.
const BOARD_LIFT := Vector3(0.0, 1.3, 0.0)
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)
## The ambient beds that run all night, and the one that plays in the breaks.
const NIGHT_BEDS: Array[StringName] = [&"bed_crickets", &"bed_highway"]
const SCORE := &"bed_score"
const PROJECTOR := &"bed_projector"
## The node of the lot's greybox that holds the projection booth.
const BOOTH_NODE := "ProjectionBooth"
## The physics layer (bit 2) the lot's walls and fences are also on, which the audio service's rays
## read: a sound behind one is quieter and duller. Cars, crates and the ground are not on it.
const OCCLUDER_MASK := 2
## The seed of the feet's level wobble.
const FEET_SEED := 239

## The wind (`WindSounds`): a quiet base layer and random gusts. A test or a capture draws a night's
## wind again with `wind.reseed(seed)`.
var wind: WindSounds

var _state: ClientState
var _world: NightWorld
var _over := false


## Starts the night's beds and listens to `state`. `world` says where the breaches, the doors and
## the booth are.
func setup(state: ClientState, world: NightWorld) -> void:
	_state = state
	_world = world
	Audio.occluder_mask = OCCLUDER_MASK
	state.event_received.connect(_on_event)
	# The popups' sounds are quieter in a fight, so they never hide a shot, a groan or a warning.
	Audio.ui.in_night = true
	for id in NIGHT_BEDS:
		Audio.start_bed(id)
	# The score comes and goes with the rounds: made ready now, behind the loading screen.
	Audio.start_bed(SCORE, true)
	if state.phase() != GameRules.Phase.ACTIVE:
		Audio.start_bed(SCORE)
	_start_projector()
	_add_wind()
	_add_footsteps()


## The wind of the night (`WindSounds`), a child that starts with the night and stops with it.
func _add_wind() -> void:
	wind = WindSounds.new()
	wind.name = "WindSounds"
	add_child(wind)
	wind.setup()
	wind.start()


## Every player's feet (`FootstepSounds`), found by the bodies the view knows.
func _add_footsteps() -> void:
	var view := get_parent() as NightView
	if view == null:
		return
	var feet := FootstepSounds.new()
	feet.name = "FootstepSounds"
	add_child(feet)
	feet.setup(_state, view.bodies, FEET_SEED)


func _exit_tree() -> void:
	Audio.occluder_mask = 0
	Audio.ui.in_night = false
	# A finished night leaves nothing of its own playing (the service outlives it).
	for id in NIGHT_BEDS:
		Audio.stop_bed(id)
	Audio.stop_bed(SCORE)
	if wind != null:
		wind.stop()
	for anchor in find_children("Projector", "Node3D", false, false):
		for player in anchor.get_children():
			if player is AudioStreamPlayer3D:
				(player as AudioStreamPlayer3D).stop()


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"board_torn":
			var last: bool = event["boards"] == 0
			_at_breach(&"board_last" if last else &"board_tear", event["barricade_id"])
		&"board_repaired":
			_at_breach(&"board_repair", event["barricade_id"])
		&"door_opened":
			var points := _world.door_points(StringName(event["door_id"]))
			if not points.is_empty():
				Audio.play(&"door_open", points[0])
		&"purchase_made":
			_at_player(&"till_ring", event["player_id"])
		&"shot_fired":
			if _is_melee(event["weapon_id"]):
				Audio.play(&"melee_swing", event["muzzle"])
		&"quick_melee":
			Audio.play(&"melee_swing", event["muzzle"])
		&"damage_dealt":
			if event["melee"]:
				Audio.play(&"melee_hit", event["point"])
		&"round_started":
			Audio.stop_bed(SCORE)
		&"round_ended":
			if not _over:
				Audio.start_bed(SCORE)
		&"game_over":
			_over = true
			for id in NIGHT_BEDS:
				Audio.stop_bed(id)
			Audio.stop_bed(SCORE)
			wind.stop()


func _at_breach(sound: StringName, barricade_id: Variant) -> void:
	var barricade := _world.barricade(StringName(barricade_id))
	if barricade != null:
		Audio.play(sound, barricade.centre() + BOARD_LIFT)


## A sound of one player's, where that player stands.
func _at_player(sound: StringName, player_id: int) -> void:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		Audio.play(sound, player["pos"] + HEAD_LIFT)
	else:
		Audio.play(sound)


func _is_melee(weapon_id: StringName) -> bool:
	var def := WeaponCatalog.get_def(weapon_id)
	return def != null and def.is_melee()


## The projector's clatter plays from the middle of the booth, so it is heard walking past.
func _start_projector() -> void:
	var booth := _world.greybox.get_node_or_null(BOOTH_NODE) as Node3D
	if booth == null or booth.get_child_count() == 0:
		return
	var total := Vector3.ZERO
	for child in booth.get_children():
		if child is Node3D:
			total += (child as Node3D).global_position
	var anchor := Node3D.new()
	anchor.name = "Projector"
	add_child(anchor)
	anchor.global_position = total / float(booth.get_child_count()) + Vector3(0.0, 1.5, 0.0)
	Audio.start_loop(PROJECTOR, anchor)
