class_name EnergySounds
extends Node
## What the two energy weapons sound like, from the server's events (#791; the recipes are
## `tools/audio/energy_recipes.py`, the numbers are in `docs/research/gun-audio.md`):
##
## - the ray gun: a charged, rising zap for the shot; a hum that follows the bolt in flight (a
##   loop on a node that flies with the bolt's own numbers, stopped by the burst); the burst with
##   its crackling splash; the reload's cell going out and in; a wake-up hum when it is raised;
## - the freeze gun: a cold hiss and crackle for the shot; the freeze taking hold of a zombie; the
##   ice's creak every second or so while it holds; the thaw when it lets go; the shatter when a
##   blow breaks it; the reload's canister out and in; a chime when it is raised.
##
## The shooter's own shot plays flat and close like every firearm's (`WeaponSounds`), a stranger's
## from the muzzle. It holds no game state and asks the server nothing. The status events are the
## ones the combat server's status effect sends (`ZOMBIE_FROZEN`, `ZOMBIE_THAWED`,
## `ZOMBIE_SHATTERED`: zombie_id, point and, for the freeze, seconds); the methods under them do
## the same for a caller that hears the news some other way.

const RAY := &"ray_gun"
const FREEZE := &"freeze_gun"
const ZOMBIE_FROZEN := &"zombie_frozen"
const ZOMBIE_THAWED := &"zombie_thawed"
const ZOMBIE_SHATTERED := &"zombie_shattered"
## What each energy weapon's shot sounds like.
const FIRE := {RAY: &"shot_ray", FREEZE: &"shot_freeze"}
## What each is raised with, besides the swap's rustle (`WeaponSounds`).
const EQUIP := {RAY: &"equip_ray", FREEZE: &"equip_freeze"}
## A reload's steps: the event of the weapon's `ReloadMotion` (`reload/<id>.tres`) each sound
## plays on, and the share of the reload it falls at when the motion has no such event yet.
const RELOAD := {
	RAY:
	{
		&"cell_out": [&"reload_ray_cell_out", 0.12],
		&"cell_in": [&"reload_ray_cell_in", 0.55],
	},
	FREEZE:
	{
		&"canister_out": [&"reload_freeze_out", 0.12],
		&"canister_in": [&"reload_freeze_in", 0.55],
	},
}
const BOLT_LOOP := &"bolt_ray"
const BURST := &"burst_ray"
const FREEZE_HIT := &"freeze_hit"
const FREEZE_CREAK := &"freeze_creak"
const FREEZE_THAW := &"freeze_thaw"
const FREEZE_SHATTER := &"freeze_shatter"
## How long a freeze holds when the event does not say (the design's three seconds).
const FREEZE_SECONDS := 3.0
## The first creak comes this long after the freeze takes hold, then one every `CREAK_GAP` seconds
## (a little random), and none in the last `CREAK_QUIET` seconds before the thaw.
const CREAK_FIRST := 0.7
const CREAK_GAP := Vector2(0.7, 1.2)
const CREAK_QUIET := 0.4
## A bolt's hum is stopped after this long even if no burst arrives (a lost packet).
const BOLT_MAX_SECONDS := 6.0
## A sound at a player's head.
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
## `Callable(id: StringName, parent: Node3D) -> Node`: starts a loop on `parent`; the audio
## service's unless a test listens instead.
var start_loop := Callable()
var schedule := SoundSchedule.new()

var _t := NightSoundTuning.current()
var _state: ClientState
var _rng := RandomNumberGenerator.new()
## The bolts in flight: projectile id to `{"anchor", "velocity", "gravity", "age"}`.
var _bolts: Dictionary[int, Dictionary] = {}


## Whether `weapon_id` is one of the two this plays (`WeaponSounds` leaves its bursts to it).
static func handles(weapon_id: StringName) -> bool:
	return FIRE.has(weapon_id)


func setup(state: ClientState, seed_value := 791) -> void:
	_state = state
	_rng.seed = seed_value
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	advance(delta)


## Moves the clock: the creaks and the reload's steps, and the bolts' hums along their flight.
func advance(delta: float) -> void:
	schedule.advance(delta)
	for id: int in _bolts.keys():
		var bolt: Dictionary = _bolts[id]
		var anchor: Node3D = bolt["anchor"]
		bolt["age"] += delta
		bolt["velocity"] += Vector3.DOWN * float(bolt["gravity"]) * delta
		anchor.position += bolt["velocity"] * delta
		if bolt["age"] > BOLT_MAX_SECONDS:
			_stop_bolt(id)


## How many bolts are humming, for tests.
func bolts_in_flight() -> int:
	return _bolts.size()


## The anchor a bolt's hum rides on (null when it is not in flight), for tests.
func bolt_anchor(projectile_id: int) -> Node3D:
	return _bolts[projectile_id]["anchor"] if _bolts.has(projectile_id) else null


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"shot_fired":
			_on_shot(event)
		&"reload_started":
			_on_reload(event)
		&"weapon_equipped":
			_on_equipped(event)
		&"projectile_spawned":
			_on_spawned(event)
		&"projectile_burst":
			_on_burst(event)
		ZOMBIE_FROZEN:
			frozen(event["zombie_id"], event["point"], event.get("seconds", FREEZE_SECONDS))
		ZOMBIE_THAWED:
			thawed(event["zombie_id"], event["point"])
		ZOMBIE_SHATTERED:
			shattered(event["zombie_id"], event.get("point", event.get("position", Vector3.ZERO)))
		&"status_applied":
			_on_status(event, true)
		&"status_ended":
			_on_status(event, false)
		&"game_over":
			schedule.clear()
			for id: int in _bolts.keys():
				_stop_bolt(id)


# --- The shot, the reload, the raising ---


func _on_shot(event: Dictionary) -> void:
	var sound: StringName = FIRE.get(event["weapon_id"], &"")
	if sound == &"":
		return
	# The shooter's own gun is in their hands: flat, like every firearm's.
	var heard_at: Variant = null if event["shooter_id"] == _state.player_id else event["muzzle"]
	_play(sound, heard_at)


func _on_reload(event: Dictionary) -> void:
	var weapon_id: StringName = event["weapon_id"]
	var steps: Dictionary = RELOAD.get(weapon_id, {})
	if steps.is_empty():
		return
	var shooter_id: int = event["shooter_id"]
	var tag := _reload_tag(shooter_id)
	schedule.cancel(tag)
	var motion := ReloadMotion.for_weapon(weapon_id)
	var seconds := float(event["seconds"])
	var lift := _t.own_reload_db if shooter_id == _state.player_id else _t.teammate_reload_db
	for step: StringName in steps:
		var sound: StringName = steps[step][0]
		var shares := motion.event_shares(step) if motion != null else PackedFloat32Array()
		if shares.is_empty():
			shares = PackedFloat32Array([steps[step][1]])
		for share in shares:
			schedule.add(
				share * seconds, func() -> void: _reload_step(sound, shooter_id, lift), tag
			)


func _on_equipped(event: Dictionary) -> void:
	# A weapon put away abandons its reload (the server cancels it too).
	schedule.cancel(_reload_tag(event["player_id"]))
	var sound: StringName = EQUIP.get(event["weapon_id"], &"")
	if sound != &"" and _state.has_frame():
		_at_player(sound, event["player_id"])


static func _reload_tag(player_id: int) -> StringName:
	return StringName("energy_reload_%d" % player_id)


func _reload_step(sound: StringName, player_id: int, lift_db: float) -> void:
	if player_id == _state.player_id:
		_play(sound, null, lift_db)
	else:
		_at_player(sound, player_id, lift_db)


# --- The ray gun's bolt ---


func _on_spawned(event: Dictionary) -> void:
	if event["weapon_id"] != RAY:
		return
	var id: int = event["projectile_id"]
	_stop_bolt(id)
	var anchor := Node3D.new()
	anchor.name = "Bolt%d" % id
	add_child(anchor)
	anchor.position = event["position"]
	# The bolt's own numbers once the weapon is in the catalogue (a stand-in flies straight).
	var def := WeaponCatalog.get_def(RAY) if WeaponCatalog.IDS.has(RAY) else null
	_bolts[id] = {
		"anchor": anchor,
		"velocity": event["velocity"],
		"gravity": def.projectile_gravity if def != null else 0.0,
		"age": 0.0,
	}
	if start_loop.is_valid():
		start_loop.call(BOLT_LOOP, anchor)
	else:
		Audio.start_loop(BOLT_LOOP, anchor)


func _on_burst(event: Dictionary) -> void:
	# The warm-up's sample burst names no weapon.
	if event.get("weapon_id", &"") != RAY:
		return
	_stop_bolt(event.get("projectile_id", -1))
	_play(BURST, event["point"])


func _stop_bolt(projectile_id: int) -> void:
	var bolt: Dictionary = _bolts.get(projectile_id, {})
	if bolt.is_empty():
		return
	_bolts.erase(projectile_id)
	(bolt["anchor"] as Node3D).queue_free()


# --- The freeze ---


## The combat server's status events (`StatusBoard`): the frozen status is the freeze, heard where
## the zombie stands in the last frame; a chilled one only gets the cold touch.
func _on_status(event: Dictionary, applied: bool) -> void:
	var id: int = event["target_id"]
	var point := Vector3.ZERO
	for entry in _state.zombies:
		if entry["id"] == id:
			point = entry["position"]
			break
	if point == Vector3.ZERO:
		return
	match event["status"]:
		&"frozen":
			if applied:
				frozen(id, point, event.get("seconds", FREEZE_SECONDS))
			else:
				thawed(id, point)
		&"chilled":
			if applied:
				_play(FREEZE_HIT, point)


## A zombie froze at `point` for `seconds`: the freeze takes hold, and the ice creaks now and then
## until it lets go.
func frozen(zombie_id: int, point: Vector3, seconds := FREEZE_SECONDS) -> void:
	var tag := _freeze_tag(zombie_id)
	schedule.cancel(tag)
	_play(FREEZE_HIT, point)
	var at := CREAK_FIRST
	while at < seconds - CREAK_QUIET:
		schedule.add(at, func() -> void: _play(FREEZE_CREAK, point), tag)
		at += _rng.randf_range(CREAK_GAP.x, CREAK_GAP.y)


## The freeze let go of a zombie: no more creaks, the thaw.
func thawed(zombie_id: int, point: Vector3) -> void:
	schedule.cancel(_freeze_tag(zombie_id))
	_play(FREEZE_THAW, point)


## A blow broke a frozen zombie into pieces: no more creaks, the shatter.
func shattered(zombie_id: int, point: Vector3) -> void:
	schedule.cancel(_freeze_tag(zombie_id))
	_play(FREEZE_SHATTER, point)


static func _freeze_tag(zombie_id: int) -> StringName:
	return StringName("freeze_%d" % zombie_id)


# --- Playing ---


## A sound where `player_id` stands; nothing for a stranger who is not in the frame.
func _at_player(sound: StringName, player_id: int, lift_db := 0.0) -> void:
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	if player.has("pos"):
		_play(sound, player["pos"] + HEAD_LIFT, lift_db)
	elif player_id == _state.player_id:
		_play(sound, null, lift_db)


func _play(sound: StringName, at: Variant, lift_db := 0.0) -> void:
	var extra_db := _rng.randf_range(-_t.shot_jitter_db, _t.shot_jitter_db) + lift_db
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
