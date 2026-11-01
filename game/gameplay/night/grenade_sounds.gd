class_name GrenadeSounds
extends Node
## What a grenade sounds like, from the server's events: the pin and spoon at the throw, a tick
## while a player cooks one (its rate rises as the fuse runs down, so a cook can be timed by ear),
## the knock of each bounce (harder when it hits harder) and the blast. A grenade in the air makes
## no tick: its place is only known at the throw, the bounces and the blast.

## The tick's gap at the start of a fuse and at its end, in seconds.
const TICK_GAP_START := 0.5
const TICK_GAP_END := 0.1
## A bounce's level goes from `BOUNCE_QUIET_DB` at rest to `BOUNCE_LOUD_DB` at `BOUNCE_FAST` m/s.
const BOUNCE_QUIET_DB := -9.0
const BOUNCE_LOUD_DB := 0.0
const BOUNCE_FAST := 12.0
const HEAD_LIFT := Vector3(0.0, 1.4, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`; the audio service unless a test
## listens instead.
var play := Callable()
var schedule := SoundSchedule.new()

var _state: ClientState
var _cooks: Dictionary[int, int] = {}


func setup(state: ClientState) -> void:
	_state = state
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	schedule.advance(delta)


## The gap before the next tick when `left` of `fuse` seconds remain.
static func tick_gap(left: float, fuse: float) -> float:
	return lerpf(TICK_GAP_END, TICK_GAP_START, clampf(left / maxf(fuse, 0.001), 0.0, 1.0))


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
			var loud := clampf(float(event["speed"]) / BOUNCE_FAST, 0.0, 1.0)
			_play(&"grenade_bounce", event["point"], lerpf(BOUNCE_QUIET_DB, BOUNCE_LOUD_DB, loud))
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
