class_name CombatProbe
extends RefCounted
## What a fight looked like from outside, for the suites that hold a bot to the balance simulator's
## skill levels (bots plan, phase 3): the shots a seat fired and where they landed, the swings that
## were aimed at it and how many landed, and what it killed. It reads the server's events and the
## dead on the lot, which a bot never does. Attach with `watch`; call `tick` after every step.

const HEAD := &"head"
const RANGE := Vector2(5.0, 20.0)

var player_id := 1
var shots := 0
var hits := 0
var heads := 0
## The same three counted only for shots at a target `RANGE` metres away (x: nearest, y: farthest):
## a shot at point blank lands whatever the aim, so the skill is read from the shots that aim
## decided.
var range_shots := 0
var range_hits := 0
var range_heads := 0
var kills := 0
var swings := 0
## Swings that reached the moment of their blow (a hit that staggers the zombie takes its swing
## away; that is the gun's doing and not a step aside), and the blows that landed.
var completed := 0
var blows := 0
var damage_taken := 0.0
var grenades_thrown := 0
## Zombies of this look were the targets (empty: any).
var only_look: StringName = &""
## Hits by zone.
var zones: Dictionary = {}

## At the last shot: how far the view's pitch was above the pitch of a walker's chest at the same
## range (negative: lower).
var last_aim_gap := 0.0

var _night: SeatedNight
var _bot: BotClient
var _last_range := -1.0
var _swinging := {}
var _struck := {}


func watch(night: SeatedNight, id: int = 1) -> CombatProbe:
	_night = night
	player_id = id
	for bot in night.host.bots:
		if bot.state.player_id == id:
			_bot = bot
	night.on_event = _on_event
	return self


## Lets go of the night (it holds a callable to this object).
func stop() -> void:
	if _night != null:
		_night.on_event = Callable()
	_night = null


## Counts the swings that began at the seat since the last call (a zombie that entered its attack
## and was not tearing boards).
func tick() -> void:
	for zombie_id: int in _night.server.sim.zombies:
		var zombie: ZombieBody = _night.server.sim.zombies[zombie_id]
		var attacking := zombie.mode == ZombieBody.Mode.ATTACK and not zombie.tearing
		if attacking and not _swinging.get(zombie_id, false) and zombie.target_id == player_id:
			swings += 1
		_swinging[zombie_id] = attacking
		var struck := attacking and zombie.struck
		if struck and not _struck.get(zombie_id, false) and zombie.target_id == player_id:
			completed += 1
		_struck[zombie_id] = struck


func hit_rate() -> float:
	return float(hits) / float(maxi(shots, 1))


func head_share() -> float:
	return float(heads) / float(maxi(hits, 1))


## The share of the blows that came due on the seat and did not hurt it (it had stepped out of
## reach): the simulator's `dodge`, a plain blow that misses.
func dodge() -> float:
	return 1.0 - float(blows) / float(maxi(completed, 1))


func range_hit_rate() -> float:
	return float(range_hits) / float(maxi(range_shots, 1))


func range_head_share() -> float:
	return float(range_heads) / float(maxi(range_hits, 1))


func _in_range() -> bool:
	return _last_range >= RANGE.x and _last_range <= RANGE.y


## Metres from the seat to the zombie the bot was aiming at when the shot went (-1 for none).
func _range_to_target() -> float:
	if _bot == null or not _night.server.sim.zombies.has(_bot.motor.target_id):
		return -1.0
	var zombie: ZombieBody = _night.server.sim.zombies[_bot.motor.target_id]
	var here := _night.server.body_of(player_id).global_position
	return Vector2(zombie.position.x - here.x, zombie.position.z - here.z).length()


func _on_event(event: Dictionary) -> void:
	match event["type"]:
		&"shot_fired":
			if event["shooter_id"] == player_id:
				shots += 1
				_last_range = _range_to_target()
				if _bot != null and _last_range > 0.0:
					var chest := atan2(BotLevel.CHEST_HEIGHT - BotLevel.EYE_HEIGHT, _last_range)
					last_aim_gap = _bot.motor.pitch - chest
				if _in_range():
					range_shots += 1
		&"zombie_damaged":
			if event["player_id"] == player_id:
				hits += 1
				var zone: StringName = event["zone"]
				zones[zone] = zones.get(zone, 0) + 1
				if zone == HEAD:
					heads += 1
				if _in_range():
					range_hits += 1
					if zone == HEAD:
						range_heads += 1
		&"zombie_removed":
			if event["cause"] == &"killed" and event["killer_id"] == player_id:
				kills += 1
		&"player_hurt":
			if event["player_id"] == player_id:
				blows += 1
				damage_taken += float(event["damage"])
		&"grenade_thrown":
			if event["thrower_id"] == player_id:
				grenades_thrown += 1
