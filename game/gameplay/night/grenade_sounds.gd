class_name GrenadeSounds
extends Node
## What a grenade sounds like, from the server's events: the pin and spoon at the throw, a time
## bomb's beep from the pin to the blast (it comes faster and a little louder as the fuse runs
## down, in the hand while a player cooks and then from the grenade wherever it lies), the knock of
## each bounce (harder when it hits harder, a zombie's thud included) and the blast. Every client
## hears the same beeps: they follow the events, which every client gets, and the schedule's clock.

const HEAD_LIFT := Vector3(0.0, 1.4, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
## `Callable(grenade_id: int) -> Variant`: where that grenade is now (a Vector3), or null when this
## client does not draw it. The night gives the view's; without it a beep comes from where the
## grenade was last heard.
var where_is := Callable()
var schedule := SoundSchedule.new()

var _t := NightSoundTuning.current()
var _state: ClientState
## The beeps running: `{key: {"token", "left", "fuse", "due", "player_id", "grenade_id", "at"}}`.
## A key is the player's cook (`cook_<id>`) or a grenade in the air (`nade_<id>`).
var _beeps: Dictionary[StringName, Dictionary] = {}
var _tokens := 0


func setup(state: ClientState) -> void:
	_state = state
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	schedule.advance(delta)


## The gap before the next beep when `left` of `fuse` seconds remain: from `beep_gap_start` at the
## pin to `beep_gap_end` at the blast.
static func beep_gap(left: float, fuse: float) -> float:
	var t := NightSoundTuning.current()
	var ratio := clampf(left / maxf(fuse, 0.001), 0.0, 1.0)
	return lerpf(t.beep_gap_end, t.beep_gap_start, pow(ratio, t.beep_curve))


## The beep's level when `left` of `fuse` seconds remain: it swells toward the blast.
static func beep_db(left: float, fuse: float) -> float:
	var t := NightSoundTuning.current()
	return lerpf(t.beep_db_end, t.beep_db_start, clampf(left / maxf(fuse, 0.001), 0.0, 1.0))


## How many beeps are running (a cook, a grenade in the air), for tests.
func beeping() -> int:
	return _beeps.size()


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"cook_started":
			_start_cook(event["player_id"], event["fuse"])
		&"grenade_thrown":
			_play(&"grenade_throw", event["position"])
			_hand_over(event)
		&"grenade_dropped":
			_hand_over(event)
		&"cook_rejected":
			_stop(_cook_key(event.get("player_id", -1)))
		&"grenade_bounced":
			var loud := clampf(float(event["speed"]) / _t.bounce_fast_speed, 0.0, 1.0)
			_play(
				&"grenade_bounce",
				event["point"],
				lerpf(_t.bounce_quiet_db, _t.bounce_loud_db, loud)
			)
		&"grenade_exploded":
			_play(&"grenade_blast", event["point"])
			_stop(_nade_key(event["grenade_id"]))
			if event["in_hand"]:
				_stop(_cook_key(event["thrower_id"]))
		&"game_over":
			schedule.clear()
			_beeps.clear()


func _start_cook(player_id: int, fuse: float) -> void:
	_stop(_cook_key(player_id))
	_begin(_cook_key(player_id), fuse, fuse, player_id, -1, 0.0)


## The pin's beeps go on from the grenade: the cook's chain becomes the grenade's, keeping the beat
## (the next beep stays due when it was due), with the fuse the server says is left. A player this
## client did not hear cook (it joined late) starts the chain at the grenade.
func _hand_over(event: Dictionary) -> void:
	var thrower: int = event["thrower_id"]
	var grenade_id: int = event["grenade_id"]
	var key := _nade_key(grenade_id)
	var cook := _cook_key(thrower)
	var fuse: float = event["fuse_left"] + float(event.get("cooked", 0.0))
	var delay := 0.0
	if _beeps.has(cook):
		fuse = _beeps[cook]["fuse"]
		delay = maxf(_beeps[cook]["due"] - schedule.now(), 0.0)
		_stop(cook)
	_begin(key, fuse, event["fuse_left"], thrower, grenade_id, delay)
	_beeps[key]["at"] = event["position"]


## Starts a chain: the first beep `delay` seconds from now.
func _begin(
	key: StringName, fuse: float, left: float, player_id: int, grenade_id: int, delay: float
) -> void:
	_tokens += 1
	var token := _tokens
	_beeps[key] = {
		"token": token,
		"left": left,
		"fuse": fuse,
		"due": schedule.now() + delay,
		"player_id": player_id,
		"grenade_id": grenade_id,
		"at": null,
	}
	schedule.add(delay, func() -> void: _beep(key, token), key)


func _stop(key: StringName) -> void:
	if _beeps.erase(key):
		schedule.cancel(key)


## One beep now, the next after a gap that shrinks with the fuse.
func _beep(key: StringName, token: int) -> void:
	var chain: Dictionary = _beeps.get(key, {})
	if chain.is_empty() or chain["token"] != token or chain["left"] <= 0.0:
		return
	_play(&"grenade_beep", _beep_place(chain), beep_db(chain["left"], chain["fuse"]))
	var gap := beep_gap(chain["left"], chain["fuse"])
	chain["left"] -= gap
	chain["due"] = schedule.now() + gap
	schedule.add(gap, func() -> void: _beep(key, token), key)


## Where a beep comes from: the grenade, or the head of the player who holds it.
func _beep_place(chain: Dictionary) -> Variant:
	if chain["grenade_id"] >= 0:
		if where_is.is_valid():
			var found: Variant = where_is.call(chain["grenade_id"])
			if found is Vector3:
				chain["at"] = found
		return chain["at"]
	var player: Dictionary = _state.frame.get("players", {}).get(chain["player_id"], {})
	return player["pos"] + HEAD_LIFT if player.has("pos") else null


static func _cook_key(player_id: int) -> StringName:
	return StringName("cook_%d" % player_id)


static func _nade_key(grenade_id: int) -> StringName:
	return StringName("nade_%d" % grenade_id)


func _play(sound: StringName, at: Variant, extra_db := 0.0) -> void:
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
