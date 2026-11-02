class_name WeaponSounds
extends Node
## What the guns sound like, made only from what the server sent (like `NightView`): each shot is
## a report and a tail on two voices with their own random variants, and the shooter's own shots
## play flat, close and un-panned, not from the muzzle a few metres ahead of the camera
## (`docs/research/gun-audio.md`); a reload's steps
## sound on the event frames of the reload clip; an empty trigger clicks; a swap rustles; a round
## that hits a zombie thumps (and cracks on the head) and one that hits the lot ricochets. It
## holds no game state and asks the server nothing. The design is `docs/design/audio.md`.

## What each firearm plays: the report and the tail after it. Ids are `ArmsCatalog`'s. The
## crowbar's swing and blow are `NightSounds`' (melee), not these.
const FIRE := {
	&"pistol": {"shot": &"shot_pistol", "tail": &"tail_pistol"},
	&"smg": {"shot": &"shot_smg", "tail": &"tail_smg"},
	&"rifle": {"shot": &"shot_rifle", "tail": &"tail_rifle"},
	&"shotgun": {"shot": &"shot_shotgun", "tail": &"tail_shotgun"},
	&"flare_gun": {"shot": &"shot_flare"},
}
## Which reload clip each weapon is drawn with, and which sound each of the clip's events makes.
## The soldier has four weapon classes: the revolver and the SMG change magazines, the flare gun
## breaks open like the shotgun.
const RELOAD := {
	&"pistol":
	{
		"clip": &"Reload_Pistol",
		"steps": {&"mag_out": &"reload_pistol_mag_out", &"mag_in": &"reload_pistol_mag_in"},
	},
	&"smg":
	{
		"clip": &"Reload_Pistol",
		"steps": {&"mag_out": &"reload_smg_mag_out", &"mag_in": &"reload_smg_mag_in"},
	},
	&"rifle":
	{
		"clip": &"Reload_Rifle",
		"steps": {&"round_in": &"reload_rifle_round", &"lever": &"reload_rifle_lever"},
	},
	&"shotgun":
	{
		"clip": &"Reload_Shotgun",
		"steps":
		{
			&"break_open": &"reload_shotgun_open",
			&"shells_in": &"reload_shotgun_shells",
			&"snap_shut": &"reload_shotgun_shut"
		},
	},
	&"flare_gun":
	{
		"clip": &"Reload_Shotgun",
		"steps":
		{
			&"break_open": &"reload_shotgun_open",
			&"shells_in": &"reload_shotgun_shells",
			&"snap_shut": &"reload_shotgun_shut"
		},
	},
}
## Lifts a sound off the ground to a player's head.
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)
## The tail starts this long after the report, and up to `TAIL_SPREAD` later: the lot answers late.
const TAIL_DELAY := 0.03
const TAIL_SPREAD := 0.02
## A level wobble on every layer, in dB either way: the one level rule of the firearms, with the
## pitch rule of `ArmsCatalog.FIREARM_PITCH_SEMITONES`. Enough that repeats do not machine-gun
## (the variants and their noise do the rest), too little to make one shot stand out.
const LEVEL_JITTER_DB := 0.5
## How many ricochets one shot may make (a shotgun has eight pellets), and how close a hit's point
## must be to a pellet's end for the pellet to count as having hit the zombie.
const MAX_WORLD_IMPACTS := 3
const HIT_MATCH_RADIUS := 1.5
## A pellet that ends within this of the weapon's range hit nothing at all (the sky).
const RANGE_MARGIN := 0.5

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()

var _state: ClientState
var _rng := RandomNumberGenerator.new()
var _pending_ends: Array[Vector3] = []
var _flush_queued := false


func setup(state: ClientState, seed_value := 1958) -> void:
	_state = state
	_rng.seed = seed_value
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	schedule.advance(delta)


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"shot_fired":
			_on_shot(event)
		&"damage_dealt":
			_on_damage(event)
		&"fire_rejected":
			if event["reason"] == &"empty":
				_at_player(&"dry_fire", event["shooter_id"])
		&"reload_started":
			_on_reload(event)
		&"weapon_equipped":
			_on_equipped(event)
		&"projectile_burst":
			_play(&"burst_flare", event["point"])
		&"game_over":
			schedule.clear()


func _on_shot(event: Dictionary) -> void:
	var weapon_id: StringName = event["weapon_id"]
	var layers: Dictionary = FIRE.get(weapon_id, {})
	if layers.is_empty():
		return
	var at: Vector3 = event["muzzle"]
	# The shooter's own gun is in their hands: flat, at full level, whatever the distance from the
	# camera to the muzzle and the pan law of a 3D voice (which costs a centred sound 6 dB).
	var heard_at: Variant = null if event["shooter_id"] == _state.player_id else at
	_play(layers["shot"], heard_at)
	if layers.has("tail"):
		var tail: StringName = layers["tail"]
		var delay := TAIL_DELAY + _rng.randf() * TAIL_SPREAD
		schedule.add(delay, func() -> void: _play(tail, heard_at))
	var def := WeaponCatalog.get_def(weapon_id)
	if def != null and def.is_hitscan():
		_note_ends(at, event["ends"], def.max_range)


## A pellet that ended short of the weapon's range hit something; the zombies' hits are known a
## moment later in the same batch (`_on_damage` claims them), and what is left struck the lot.
func _note_ends(muzzle: Vector3, ends: Array, max_range: float) -> void:
	for end: Vector3 in ends:
		if muzzle.distance_to(end) < max_range - RANGE_MARGIN:
			_pending_ends.append(end)
	if not _pending_ends.is_empty() and not _flush_queued:
		_flush_queued = true
		schedule.add(0.0, _flush_impacts)


func _on_damage(event: Dictionary) -> void:
	if event["melee"]:
		return
	var point: Vector3 = event["point"]
	var best := -1
	var best_distance := HIT_MATCH_RADIUS
	for i in _pending_ends.size():
		var distance := _pending_ends[i].distance_to(point)
		if distance <= best_distance:
			best = i
			best_distance = distance
	if best >= 0:
		_pending_ends.remove_at(best)
	_play(&"impact_head" if event["headshot"] else &"impact_flesh", point)


func _flush_impacts() -> void:
	_flush_queued = false
	var count := mini(_pending_ends.size(), MAX_WORLD_IMPACTS)
	for i in count:
		var end := _pending_ends[int(float(i * _pending_ends.size()) / float(count))]
		_play(&"impact_world", end)
	_pending_ends.clear()


func _on_reload(event: Dictionary) -> void:
	var table: Dictionary = RELOAD.get(event["weapon_id"], {})
	if table.is_empty():
		return
	var shooter_id: int = event["shooter_id"]
	var tag := _reload_tag(shooter_id)
	schedule.cancel(tag)
	var steps: Dictionary = table["steps"]
	for step: StringName in steps:
		var sound: StringName = steps[step]
		for seconds in ClipEvents.times(table["clip"], step):
			schedule.add(seconds, func() -> void: _at_player(sound, shooter_id), tag)


func _on_equipped(event: Dictionary) -> void:
	# A weapon put away abandons its reload (the server cancels it too).
	schedule.cancel(_reload_tag(event["player_id"]))
	if _state.has_frame():
		_at_player(&"weapon_swap", event["player_id"])


static func _reload_tag(player_id: int) -> StringName:
	return StringName("reload_%d" % player_id)


## A sound where `player_id` stands; flat when it is this screen's own player and the frame has
## no position yet, and nothing for a stranger who is not in the frame.
func _at_player(sound: StringName, player_id: int) -> void:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		_play(sound, player["pos"] + HEAD_LIFT)
	elif player_id == _state.player_id:
		_play(sound, null)


func _play(sound: StringName, at: Variant) -> void:
	var extra_db := _rng.randf_range(-LEVEL_JITTER_DB, LEVEL_JITTER_DB)
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
