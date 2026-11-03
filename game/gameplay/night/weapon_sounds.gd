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
	# The second batch of firearms (#790, `tools/audio/gun_recipes_2.py`).
	&"ppsh": {"shot": &"shot_ppsh", "tail": &"tail_ppsh"},
	&"m249": {"shot": &"shot_m249", "tail": &"tail_m249"},
	&"m4a1": {"shot": &"shot_m4a1", "tail": &"tail_m4a1"},
	&"fifty_cal": {"shot": &"shot_fifty_cal", "tail": &"tail_fifty_cal"},
	&"mp5": {"shot": &"shot_mp5", "tail": &"tail_mp5"},
	&"pump_870": {"shot": &"shot_pump_870", "tail": &"tail_pump_870"},
	&"dual_pistols": {"shot": &"shot_dual_pistols", "tail": &"tail_dual_pistols"},
	&"flare_gun": {"shot": &"shot_flare"},
}
## The sound of a weapon coming up, and of its trigger pulled on nothing, where it has its own; any
## other weapon rustles and clicks the common way (`weapon_swap`, `dry_fire`).
const EQUIP := {
	&"ppsh": &"equip_ppsh",
	&"m249": &"equip_m249",
	&"m4a1": &"equip_m4a1",
	&"fifty_cal": &"equip_fifty_cal",
	&"mp5": &"equip_mp5",
	&"pump_870": &"equip_pump_870",
	&"dual_pistols": &"equip_dual_pistols",
}
const DRY := {
	&"ppsh": &"dry_ppsh",
	&"m249": &"dry_m249",
	&"m4a1": &"dry_m4a1",
	&"fifty_cal": &"dry_fifty_cal",
	&"mp5": &"dry_mp5",
	&"pump_870": &"dry_pump_870",
	&"dual_pistols": &"dry_dual_pistols",
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
	# The second batch (#790). The step names are the events of each weapon's `ReloadMotion`: the
	# magazine guns' are the revolver's and the tommy gun's, the SAW's are its cover and belt, the
	# pump's `shell_in` sounds once for each shell the motion lists (the reload is shell by shell)
	# and `pump` is the forend racked.
	&"ppsh":
	{
		&"drum_out": &"reload_ppsh_drum_out",
		&"pouch": &"reload_pouch",
		&"drum_in": &"reload_ppsh_drum_in",
		&"bolt": &"reload_ppsh_bolt",
	},
	&"m249":
	{
		&"cover_open": &"reload_m249_cover_open",
		&"pouch": &"reload_pouch",
		&"belt_in": &"reload_m249_belt",
		&"cover_shut": &"reload_m249_cover_shut",
		&"charge": &"reload_m249_charge",
	},
	&"m4a1":
	{
		&"mag_out": &"reload_m4a1_mag_out",
		&"pouch": &"reload_pouch",
		&"mag_in": &"reload_m4a1_mag_in",
		&"bolt": &"reload_m4a1_bolt",
	},
	&"fifty_cal":
	{
		&"mag_out": &"reload_fifty_mag_out",
		&"pouch": &"reload_pouch",
		&"mag_in": &"reload_fifty_mag_in",
		&"bolt": &"reload_fifty_bolt",
	},
	&"mp5":
	{
		&"mag_out": &"reload_mp5_mag_out",
		&"pouch": &"reload_pouch",
		&"mag_in": &"reload_mp5_mag_in",
		&"bolt": &"reload_mp5_bolt",
	},
	&"pump_870":
	{
		&"pouch": &"reload_pouch",
		&"shell_in": &"reload_pump_shell",
		&"pump": &"reload_pump_stroke",
	},
	&"dual_pistols":
	{
		&"mag_out": &"reload_dual_mag_out",
		&"pouch": &"reload_pouch",
		&"mag_in": &"reload_dual_mag_in",
		&"slide": &"reload_dual_slide",
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
				var held: StringName = (
					_state.frame.get("players", {}).get(event["shooter_id"], {}).get("weapon", &"")
				)
				_at_player(DRY.get(held, &"dry_fire"), event["shooter_id"])
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
	# A weapon the catalogue does not have yet has a sound and no definition (#790 before #793).
	var def := _def_of(weapon_id)
	if def != null and def.is_hitscan():
		_note_ends(at, event["ends"], def.max_range)


func _def_of(weapon_id: StringName) -> WeaponDef:
	if not ResourceLoader.exists("%s%s.tres" % [WeaponCatalog.DIR, weapon_id]):
		return null
	return WeaponCatalog.get_def(weapon_id)


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
			schedule.add(
				share * seconds, func() -> void: _reload_step(sound, shooter_id, lift), tag
			)


func _on_equipped(event: Dictionary) -> void:
	# A weapon put away abandons its reload (the server cancels it too).
	schedule.cancel(_reload_tag(event["player_id"]))
	if _state.has_frame():
		_at_player(EQUIP.get(event["weapon_id"], &"weapon_swap"), event["player_id"])


static func _reload_tag(player_id: int) -> StringName:
	return StringName("reload_%d" % player_id)


## A sound where `player_id` stands; flat when it is this screen's own player and the frame has
## no position yet, and nothing for a stranger who is not in the frame.
func _at_player(sound: StringName, player_id: int, lift_db := 0.0) -> void:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		_play(sound, player["pos"] + HEAD_LIFT, lift_db)
	elif player_id == _state.player_id:
		_play(sound, null, lift_db)


## A reload step: the player's own hands are at their own ears, flat as their own shots are (a
## centred 3D voice costs 6 dB, and under fire a step was then lost in the guns: #683); anyone
## else's at his head.
func _reload_step(sound: StringName, player_id: int, lift_db: float) -> void:
	if player_id == _state.player_id:
		_play(sound, null, lift_db)
	else:
		_at_player(sound, player_id, lift_db)


func _play(sound: StringName, at: Variant, lift_db := 0.0) -> void:
	var extra_db := _rng.randf_range(-_t.shot_jitter_db, _t.shot_jitter_db) + lift_db
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
