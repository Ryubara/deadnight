class_name WeaponSounds
extends Node
## What the guns sound like, made only from what the server sent (like `NightView`): each shot is
## a report and a tail on two voices with their own random variants, and the shooter's own shots
## play flat, close and un-panned, not from the muzzle a few metres ahead of the camera
## (`docs/research/gun-audio.md`); a reload's steps sound on the moments of the weapon's
## `ReloadMotion`; an empty trigger clicks; a swap rustles; a round that hits a zombie thumps (and
## cracks on the head) and one that hits the lot ricochets. It
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
## What each of a reload's steps sounds like, per firearm (#683): the step names are the events of
## the weapon's `ReloadMotion` (`reload/<id>.tres`), which also says when each happens, so a step
## sounds on the moment it is drawn. Each mechanism has its own: the revolver's cylinder, the tommy
## gun's drum and bolt, the lever rifle's rounds and lever, the double-barrel's and the flare gun's
## break, eject and snap; every one reaches for the belt pouch.
const RELOAD := {
	&"pistol":
	{
		&"cylinder_out": &"reload_revolver_open",
		&"eject": &"reload_revolver_eject",
		&"pouch": &"reload_pouch",
		&"rounds_in": &"reload_revolver_rounds",
		&"cylinder_in": &"reload_revolver_close",
	},
	&"smg":
	{
		&"mag_out": &"reload_smg_mag_out",
		&"pouch": &"reload_pouch",
		&"mag_in": &"reload_smg_mag_in",
		&"bolt": &"reload_smg_bolt",
	},
	&"rifle":
	{
		&"pouch": &"reload_pouch",
		&"round_in": &"reload_rifle_round",
		&"lever": &"reload_rifle_lever",
	},
	&"shotgun":
	{
		&"break_open": &"reload_shotgun_open",
		&"eject": &"reload_shotgun_eject",
		&"pouch": &"reload_pouch",
		&"shells_in": &"reload_shotgun_shells",
		&"snap_shut": &"reload_shotgun_shut",
	},
	&"flare_gun":
	{
		&"break_open": &"reload_flare_open",
		&"eject": &"reload_flare_eject",
		&"pouch": &"reload_pouch",
		&"shells_in": &"reload_flare_in",
		&"snap_shut": &"reload_flare_shut",
	},
}
## Lifts a sound off the ground to a player's head.
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()

var _t := NightSoundTuning.current()
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
		var delay := _t.tail_delay + _rng.randf() * _t.tail_spread
		schedule.add(delay, func() -> void: _play(tail, heard_at))
	var def := WeaponCatalog.get_def(weapon_id)
	if def != null and def.is_hitscan():
		_note_ends(at, event["ends"], def.max_range)


## A pellet that ended short of the weapon's range hit something; the zombies' hits are known a
## moment later in the same batch (`_on_damage` claims them), and what is left struck the lot.
func _note_ends(muzzle: Vector3, ends: Array, max_range: float) -> void:
	for end: Vector3 in ends:
		if muzzle.distance_to(end) < max_range - _t.range_margin:
			_pending_ends.append(end)
	if not _pending_ends.is_empty() and not _flush_queued:
		_flush_queued = true
		schedule.add(0.0, _flush_impacts)


func _on_damage(event: Dictionary) -> void:
	if event["melee"]:
		return
	var point: Vector3 = event["point"]
	var best := -1
	var best_distance := _t.hit_match_radius
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
	var count := mini(_pending_ends.size(), _t.max_world_impacts)
	for i in count:
		var end := _pending_ends[int(float(i * _pending_ends.size()) / float(count))]
		_play(&"impact_world", end)
	_pending_ends.clear()


func _on_reload(event: Dictionary) -> void:
	var weapon_id: StringName = event["weapon_id"]
	var steps: Dictionary = RELOAD.get(weapon_id, {})
	var motion := ReloadMotion.for_weapon(weapon_id)
	if steps.is_empty() or motion == null:
		return
	var shooter_id: int = event["shooter_id"]
	var tag := _reload_tag(shooter_id)
	schedule.cancel(tag)
	# The motion's steps are shares of the reload, stretched over the weapon's own reload time as
	# the motion is, so each sounds on the moment it is drawn and all are over before the reload.
	var seconds := float(event["seconds"])
	var lift := _t.own_reload_db if shooter_id == _state.player_id else _t.teammate_reload_db
	for step: StringName in steps:
		var sound: StringName = steps[step]
		for share in motion.event_shares(step):
			schedule.add(share * seconds, func() -> void: _at_player(sound, shooter_id, lift), tag)


func _on_equipped(event: Dictionary) -> void:
	# A weapon put away abandons its reload (the server cancels it too).
	schedule.cancel(_reload_tag(event["player_id"]))
	if _state.has_frame():
		_at_player(&"weapon_swap", event["player_id"])


static func _reload_tag(player_id: int) -> StringName:
	return StringName("reload_%d" % player_id)


## A sound where `player_id` stands: flat for this screen's own player, at the head of anyone else,
## and nothing for a stranger who is not in the frame.
func _at_player(sound: StringName, player_id: int, lift_db := 0.0) -> void:
	# The player's own hands are at their own ears: flat, as their own shots are (a centred 3D voice
	# costs 6 dB, and under fire a reload step was then lost in the guns: #683).
	if player_id == _state.player_id:
		_play(sound, null, lift_db)
		return
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		_play(sound, player["pos"] + HEAD_LIFT, lift_db)


func _play(sound: StringName, at: Variant, lift_db := 0.0) -> void:
	var extra_db := _rng.randf_range(-_t.shot_jitter_db, _t.shot_jitter_db) + lift_db
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
