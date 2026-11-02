class_name GrenadeSounds
extends Node
## What a grenade sounds like, from the server's events: the pin and spoon at the throw, a tick
## while a player cooks one (its rate rises as the fuse runs down, so a cook can be timed by ear),
## the knock of each bounce (harder when it hits harder) and the blast. A grenade in the air makes
## no tick: its place is only known at the throw, the bounces and the blast.

const HEAD_LIFT := Vector3(0.0, 1.4, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()

var _t := NightSoundTuning.current()
var _state: ClientState
var _cooks: Dictionary[int, int] = {}


func setup(state: ClientState) -> void:
	_state = state
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	schedule.advance(delta)


## The gap before the next tick when `left` of `fuse` seconds remain.
static func tick_gap(left: float, fuse: float) -> float:
	var t := NightSoundTuning.current()
	return lerpf(t.tick_gap_end, t.tick_gap_start, clampf(left / maxf(fuse, 0.001), 0.0, 1.0))


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"cook_started":
			_start_cook(event["player_id"], event["fuse"])
		&"grenade_thrown":
			_stop_cook(event["thrower_id"])
			_play(&"grenade_throw", event["position"])
		&"grenade_dropped", &"cook_rejected":
			_stop_cook(event.get("thrower_id", event.get("player_id", -1)))
		&"grenade_bounced":
			var loud := clampf(float(event["speed"]) / _t.bounce_fast_speed, 0.0, 1.0)
			_play(
				&"grenade_bounce",
				event["point"],
				lerpf(_t.bounce_quiet_db, _t.bounce_loud_db, loud)
			)
		&"grenade_exploded":
			_play(&"grenade_blast", event["point"])
			_stop_cook(event["thrower_id"])
		&"game_over":
			schedule.clear()
			_cooks.clear()


func _start_cook(player_id: int, fuse: float) -> void:
	_stop_cook(player_id)
	var token := schedule.now()
	_cooks[player_id] = int(token * 1000.0) + 1
	_tick(player_id, fuse, fuse, _cooks[player_id])


func _stop_cook(player_id: int) -> void:
	if _cooks.erase(player_id):
		schedule.cancel(_tag(player_id))


## One tick now, the next after a gap that shrinks with the fuse.
func _tick(player_id: int, fuse: float, left: float, token: int) -> void:
	if _cooks.get(player_id, 0) != token or left <= 0.0:
		return
	var player: Dictionary = _state.frame.get("players", {}).get(player_id, {})
	var at: Variant = player["pos"] + HEAD_LIFT if player.has("pos") else null
	_play(&"grenade_tick", at)
	var gap := tick_gap(left, fuse)
	schedule.add(gap, func() -> void: _tick(player_id, fuse, left - gap, token), _tag(player_id))


static func _tag(player_id: int) -> StringName:
	return StringName("cook_%d" % player_id)


func _play(sound: StringName, at: Variant, extra_db := 0.0) -> void:
	if play.is_valid():
		play.call(sound, at, extra_db)
	else:
		Audio.play(sound, at, extra_db)
