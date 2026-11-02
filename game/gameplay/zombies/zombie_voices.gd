class_name ZombieVoices
extends RefCounted
## What the dead sound like on a client, made only from what the server sent: each frame's decoded
## zombies (`ZombieCodec.decode`) and the rules' `zombie_damaged` events. It holds no game state
## and asks the server nothing; the table of who sounds like what is `ZombieVoiceTable`, the sounds
## are `SoundCatalog`'s, and the design is `docs/design/audio.md`.
##
## - **Idle voices** are rationed: each zombie has its own random timer, and the whole horde shares
##   one gate, so at most one starts every `idle_gap_min` s however many are due at once, chosen
##   from the nearest few. (The service's `zombie_voice` group is the second guard: six voices.)
## - **Noticed**: a zombie that is chasing and first comes within `alert_range` metres snarls once
##   (a runner shrieks). A snapshot carries no target, so this is the closest a client can get to
##   "it picked you".
## - **Swings**: the effort sound is started `windup - lead` seconds after the swing begins, so its
##   peak lands on the blow; the headliner's longer telegraph gets its growl the same way.
## - **Feet** keep the clip's cadence: a foot plants twice per cycle of the clip that plays at the
##   zombie's speed, from the same per-id starting phase the view uses (`ZombieHorde`).
## - **The headliner** roars when it appears, growls before its blow and roars once more falling.
##
## Time is the caller's: `update(entries, delta)` moves the clock, so tests and replays do not
## depend on real time.

## Seconds a blow takes to land for a look with no telegraph (`ZombieTuning.windup_seconds`).
const DEFAULT_WINDUP := 0.45

## Seconds the blow takes to land, by look, for the looks that have their own telegraph.
var windups: Dictionary[StringName, float] = {}
## How many times each sound was asked for (the service may drop it); tests and captures read it.
var requested := {}

var _t := NightSoundTuning.current()
var _audio: AudioService
var _rng := RandomNumberGenerator.new()
var _now := 0.0
var _states: Dictionary[int, ZState] = {}
var _pending: Array[Dictionary] = []
var _idle_gate := 0.0
var _alert_gate := 0.0


class ZState:
	extends RefCounted
	var id := 0
	var look: StringName = &"walker"
	var mode := -1
	var episode := -1
	var position := Vector3.ZERO
	var speed := 0.0
	## 0 to 1 through the clip, started where the view starts it.
	var clip_phase := 0.0
	var next_idle := 0.0
	var alerted := false
	var swing_repeat_left := 0.0
	var last_hurt := -100.0


func _init(audio: AudioService, seed_value := 1) -> void:
	_audio = audio
	_rng.seed = seed_value


## Moves the clock by `delta` and plays what this frame's `entries` (the decoded zombies) cause.
func update(entries: Array[Dictionary], delta: float) -> void:
	_now += delta
	var listen := _audio.listener_position()
	var seen := {}
	for entry in entries:
		var zombie_id: int = entry["id"]
		seen[zombie_id] = true
		var state: ZState = _states.get(zombie_id)
		if state == null:
			state = _arrive(entry)
		_follow(state, entry, delta, listen)
	for zombie_id: int in _states.keys():
		if not seen.has(zombie_id):
			_states.erase(zombie_id)
	_fire_pending()
	_idle(listen)


## The rules' events: a hit that does not kill hurts.
func on_event(event: Dictionary) -> void:
	if event.get("type") != &"zombie_damaged":
		return
	var state: ZState = _states.get(event["zombie_id"])
	if state == null or state.mode == ZombieBody.Mode.DYING:
		return
	if float(event.get("health", 1.0)) <= 0.0 or _now - state.last_hurt < _t.hurt_gap:
		return
	state.last_hurt = _now
	_say(state, ZombieVoiceTable.get_role(state.look, "hurt"))


func zombie_count() -> int:
	return _states.size()


## Where the sound of `state` is placed: its mouth, above its feet.
func _mouth(state: ZState) -> Vector3:
	var height: float = ZombieVoiceTable.get_role(state.look, "lift")
	return state.position + Vector3(0.0, height, 0.0)


func _arrive(entry: Dictionary) -> ZState:
	var state := ZState.new()
	state.id = entry["id"]
	state.look = entry["look"]
	state.position = entry["position"]
	state.clip_phase = fposmod(float(state.id) * 0.618034, 1.0)
	state.next_idle = _now + _rng.randf_range(_t.idle_self_min * 0.3, _t.idle_self_max)
	state.mode = entry["mode"]
	state.episode = entry["episode"]
	_states[state.id] = state
	# A headliner seen rising has just arrived: it announces itself.
	if ZombieModels.is_boss(state.look) and state.mode == ZombieBody.Mode.EMERGING:
		_play(&"zombie_roar", _mouth(state))
	return state


func _follow(state: ZState, entry: Dictionary, delta: float, listen: Vector3) -> void:
	var mode: int = entry["mode"]
	var changed := mode != state.mode
	var swung: bool = entry["episode"] != state.episode
	state.look = entry["look"]
	state.position = entry["position"]
	state.speed = entry["speed"]
	state.mode = mode
	state.episode = entry["episode"]
	var distance := listen.distance_to(state.position)
	match mode:
		ZombieBody.Mode.ATTACK:
			state.swing_repeat_left -= delta
			if changed or swung or state.swing_repeat_left <= 0.0:
				_swing(state)
		ZombieBody.Mode.STAGGER:
			if changed and _now - state.last_hurt >= _t.hurt_gap:
				state.last_hurt = _now
				_say(state, ZombieVoiceTable.get_role(state.look, "hurt"))
		ZombieBody.Mode.DYING:
			if changed:
				_die(state)
		ZombieBody.Mode.CHASE:
			if not state.alerted and distance <= _t.alert_range:
				_notice(state)
			_walk(state, delta, distance)
	if mode != ZombieBody.Mode.ATTACK:
		state.swing_repeat_left = 0.0


func _notice(state: ZState) -> void:
	var cue: StringName = ZombieVoiceTable.get_role(state.look, "alert")
	if cue == &"":
		state.alerted = true
		return
	if _now < _alert_gate:
		return
	state.alerted = true
	_alert_gate = _now + _t.alert_gap
	_say(state, cue)


func _swing(state: ZState) -> void:
	state.swing_repeat_left = _t.swing_repeat
	var windup: float = windups.get(state.look, DEFAULT_WINDUP)
	var lead: float = ZombieVoiceTable.get_role(state.look, "swing_lead")
	(
		_pending
		. append(
			{
				"at": _now + maxf(windup - lead, 0.0),
				"id": state.id,
				"sound": ZombieVoiceTable.get_role(state.look, "swing"),
			}
		)
	)


func _die(state: ZState) -> void:
	if ZombieModels.is_boss(state.look):
		_play(&"zombie_roar", _mouth(state), _t.boss_death_db)
	else:
		_say(state, ZombieVoiceTable.get_role(state.look, "death"))


## Feet: the clip's phase advances at its own cadence and a step falls at each half of it.
func _walk(state: ZState, delta: float, distance: float) -> void:
	if state.speed < ZombieVoiceTable.MOVING_FROM:
		return
	var cycle := ZombieVoiceTable.cycle_seconds(state.look, state.speed)
	var before := floorf(state.clip_phase * 2.0)
	state.clip_phase += delta / cycle
	if floorf(state.clip_phase * 2.0) == before or distance > _t.step_range:
		return
	_play(ZombieVoiceTable.step_sound(state.look, state.speed), state.position)


func _fire_pending() -> void:
	var waiting: Array[Dictionary] = []
	for item in _pending:
		if item["at"] > _now:
			waiting.append(item)
			continue
		var state: ZState = _states.get(item["id"])
		if state != null and state.mode == ZombieBody.Mode.ATTACK:
			_say(state, item["sound"])
	_pending = waiting


## One idle voice at most per gate: the nearest few due zombies are the candidates.
func _idle(listen: Vector3) -> void:
	if _now < _idle_gate:
		return
	var due: Array[ZState] = []
	for state: ZState in _states.values():
		if state.mode != ZombieBody.Mode.CHASE or _now < state.next_idle:
			continue
		if listen.distance_to(state.position) <= _t.idle_range:
			due.append(state)
	if due.is_empty():
		return
	due.sort_custom(
		func(a: ZState, b: ZState) -> bool:
			return listen.distance_squared_to(a.position) < listen.distance_squared_to(b.position)
	)
	var chosen := due[_rng.randi_range(0, mini(due.size(), _t.idle_pool) - 1)]
	var sounds: Array = ZombieVoiceTable.get_role(chosen.look, "idle")
	_say(chosen, sounds[_rng.randi_range(0, sounds.size() - 1)])
	chosen.next_idle = _now + _rng.randf_range(_t.idle_self_min, _t.idle_self_max)
	_idle_gate = _now + _rng.randf_range(_t.idle_gap_min, _t.idle_gap_max)


## A voice at the zombie's mouth; the headliner's cues go through the boss group's table entries.
func _say(state: ZState, sound: StringName) -> void:
	_play(sound, _mouth(state))


func _play(sound: StringName, at: Vector3, extra_db := 0.0) -> void:
	if sound == &"":
		return
	requested[sound] = int(requested.get(sound, 0)) + 1
	_audio.play(sound, at, extra_db)
