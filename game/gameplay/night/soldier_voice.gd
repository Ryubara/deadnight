class_name SoldierVoice
extends Node
## The soldiers talk: a person reacting to what just happened, made only from what the server sent
## (like `WeaponSounds`). Each event of the night becomes one moment (`SoldierMoments`),
## `VoiceDirector` says whether it is voiced and which take, and the take plays on the Voice bus:
## flat for the player at this screen (their voice is in their head), where they stand for a
## teammate. It holds no game state and asks the server nothing. The design is
## `docs/design/audio.md`.

## A voice comes from a player's head.
const HEAD_LIFT := Vector3(0.0, 1.6, 0.0)

## `Callable(id: StringName, at: Variant, extra_db: float)`, returning a node (or true) when the
## line started and null (or false) when the service dropped it; the audio service unless a test
## listens instead.
var play := Callable()
var director := VoiceDirector.new()
var schedule := SoundSchedule.new()
## Every player's look (the night's `LookRegistry`): a soldier speaks with the voice of their
## character (`SoldierVoiceCatalog.VOICES`). Without it, or for a player it has not heard of yet,
## the Soldier as built.
var looks: LookRegistry

var _t := NightSoundTuning.current()
var _state: ClientState
var _kills: Dictionary[int, Array] = {}
var _speaking: Variant = null
var _break_ends := 0.0
var _lull := 0.0


func setup(state: ClientState, seed_value := 1958) -> void:
	_state = state
	director.seed_random(seed_value)
	state.event_received.connect(_on_event)


func _process(delta: float) -> void:
	step(delta)


## Moves the clock (the director's and the schedule's) and lets the soldier muse in a quiet break.
func step(delta: float) -> void:
	var ready := false
	director.advance(delta)
	schedule.advance(delta)
	if _state == null or not _state.has_frame() or _state.over:
		return
	if _state.phase() == GameRules.Phase.ACTIVE:
		_lull = _lull + delta if _nearest_dead() > _t.lull_distance else 0.0
		ready = _lull > _t.lull
	else:
		_lull = 0.0
		ready = _break_ends - director.now() > _t.idle_margin
	if ready and director.quiet_for() > _t.idle_after:
		say(&"idle", _state.player_id)


## The character whose voice `speaker` (a player id) speaks with.
func voice_of(speaker: int) -> StringName:
	if looks != null and looks.looks.has(speaker):
		return (looks.looks[speaker] as CharacterLook).body()
	return LookCatalog.MALE


## Says `event` as `speaker` (a player id) if the director allows it. Returns whether it played. A
## character with no voice yet says nothing, and uses up no turn of the director's.
func say(event: StringName, speaker: int) -> bool:
	if not SoldierVoiceCatalog.has_voice(voice_of(speaker)):
		return false
	var player := _player(speaker)
	if bool(player.get("downed", false)) and event != &"downed":
		return false
	var take := director.choose(event, speaker)
	if take == 0:
		return false
	var own := speaker == _state.player_id
	var at: Variant = null
	if not own and player.has("pos"):
		at = player["pos"] + HEAD_LIFT
	var priority: int = SoldierVoiceCatalog.moments()[event]["priority"]
	var cut := director.would_interrupt(priority)
	var started: Variant = _play(
		SoldierVoiceCatalog.take_id(event, take),
		at,
		SoundCatalog.mix().own_voice_db if own else 0.0
	)
	if started == null or (started is bool and not started):
		return false
	if cut and is_instance_valid(_speaking) and _speaking.has_method(&"stop"):
		_speaking.stop()
	_speaking = started
	director.commit(event, speaker, take, SoldierVoiceCatalog.length(event, take))
	return true


## Says `event` after `delay` seconds, or (with `after_line`) after the line that speaks now.
func say_in(delay: float, event: StringName, speaker: int, after_line := false) -> void:
	var wait := delay + (director.wait() if after_line else 0.0)
	schedule.add(wait, func() -> void: say(event, speaker))


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"break_started":
			_break_ends = director.now() + event["seconds"]
		&"round_started":
			_kills.clear()
			if int(event.get("boss_count", 0)) == 0:
				say_in(_t.round_start_delay, &"round_start", _state.player_id)
		&"round_ended":
			say_in(_t.round_clear_delay, &"round_clear", _state.player_id, true)
		&"zombie_spawn_requested":
			if event["boss"]:
				say_in(_t.boss_delay, &"boss_arrive", _state.player_id)
		&"zombie_removed":
			_on_zombie_removed(event)
		&"player_hurt":
			_on_hurt(event)
		&"player_downed":
			_on_downed(event["player_id"])
		&"player_revived":
			say_in(0.3, &"revived", event["player_id"])
		&"reload_started":
			say(&"reload", event["shooter_id"])
		&"shot_fired":
			_on_shot(event)
		&"fire_rejected":
			if event["reason"] == &"empty":
				say(&"dry", event["shooter_id"])
		&"grenade_thrown":
			say(&"grenade", event["thrower_id"])
		&"purchase_made":
			_on_purchase(event)
		&"fuel_restored":
			say(&"power_on", _state.player_id)
		&"fuel_low", &"fuel_empty":
			say(&"power_low", _state.player_id)
		&"game_over":
			schedule.clear()
			director.clear()


func _on_zombie_removed(event: Dictionary) -> void:
	var killer: int = event["killer_id"]
	if event["cause"] != &"killed" or killer < 0:
		return
	if event["boss"]:
		say_in(_t.boss_delay, &"boss_dead", killer, true)
		return
	var times: Array = _kills.get(killer, [])
	var now := director.now()
	times = times.filter(func(t: float) -> bool: return now - t <= _t.streak_window)
	times.append(now)
	_kills[killer] = times
	if times.size() >= _t.streak_kills and say(&"streak", killer):
		_kills[killer] = []
		return
	say(&"kill", killer)


func _on_hurt(event: Dictionary) -> void:
	var who: int = event["player_id"]
	say(&"hurt", who)
	if event["health"] > 0.0 and event["health"] <= _t.low_health * event["max_health"]:
		say_in(0.3, &"close_call", who, true)


func _on_downed(who: int) -> void:
	say(&"downed", who)
	var rescuer := _nearest_standing(who)
	if rescuer >= 0:
		say_in(_t.rescue_delay, &"teammate_down", rescuer, true)


func _on_shot(event: Dictionary) -> void:
	var weapon := WeaponCatalog.get_def(event["weapon_id"])
	if weapon == null or weapon.is_melee():
		return
	var low := ceili(weapon.magazine_size * _t.low_magazine)
	if event["reserve"] == 0 and event["ammo"] > 0 and event["ammo"] <= low:
		say(&"low_ammo", event["shooter_id"])


func _on_purchase(event: Dictionary) -> void:
	var item := String(event["item_id"])
	var buyer: int = event["player_id"]
	if item.begins_with("door_"):
		say_in(0.5, &"door", buyer)
	elif item.begins_with("weapon_"):
		say_in(0.5, &"buy_big" if event["price"] >= _t.big_buy else &"buy_weapon", buyer)


## How far the nearest dead is from the local player (INF when there are none).
func _nearest_dead() -> float:
	var nearest := INF
	var here := _state.position()
	for zombie in _state.zombies:
		nearest = minf(nearest, here.distance_to(zombie["position"]))
	return nearest


## The nearest player on their feet other than `who`, or -1.
func _nearest_standing(who: int) -> int:
	var fallen := _player(who)
	var best := -1
	var best_distance := INF
	var players: Dictionary = _state.frame.get("players", {})
	for id: int in players:
		var player: Dictionary = players[id]
		if id == who or player.get("downed", false) or not player.has("pos"):
			continue
		var distance: float = (player["pos"] as Vector3).distance_to(
			fallen.get("pos", Vector3.ZERO)
		)
		if distance < best_distance:
			best = id
			best_distance = distance
	return best


func _player(id: int) -> Dictionary:
	return _state.frame.get("players", {}).get(id, {})


func _play(id: StringName, at: Variant, extra_db: float) -> Variant:
	if play.is_valid():
		return play.call(id, at, extra_db)
	return Audio.play(id, at, extra_db)
