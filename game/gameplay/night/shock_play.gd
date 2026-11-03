class_name ShockPlay
extends RefCounted
## The shock perk's burst, as the night server runs it (`docs/design/perks.md`): when a player who
## has had the reload shock starts a reload, every living zombie within `PerkTuning.shock_radius`
## takes `shock_damage` as a blast (the rules pay and kill, `ExplosionPlay`), is held still for
## `shock_stun_seconds` and shoved `shock_push` m/s. `shock_cooldown` apart, so a reload cancelled
## and begun again is no free shock.

## Seconds until each player's shock can fire again.
var _wait: Dictionary[int, float] = {}


## Moves the waits on by `delta` seconds.
func step(delta: float) -> void:
	for player_id in _wait:
		_wait[player_id] = maxf(_wait[player_id] - delta, 0.0)


func forget(player_id: int) -> void:
	_wait.erase(player_id)


## The shock of `player_id` at `at`, if the player has the perk and its wait is over: the rules and
## the zombies take it, and the `shock_burst` event comes back (player_id, point, radius, hits: the
## zombie ids). `{}` when nothing fired.
func fire(rules: GameRules, sim: ZombieSim, player_id: int, at: Vector3) -> Dictionary:
	if not PerkEffects.has(rules, player_id, ShopItem.Effect.SHOCK):
		return {}
	if _wait.get(player_id, 0.0) > 0.0:
		return {}
	var spec := rules.tuning.perks
	_wait[player_id] = spec.shock_cooldown
	var victims: Array = []
	var hit_ids: Array = []
	var ids := sim.zombies.keys()
	ids.sort()
	for zombie_id: int in ids:
		var zombie: ZombieBody = sim.zombies[zombie_id]
		var apart := Vector2(zombie.position.x - at.x, zombie.position.z - at.z)
		if not zombie.is_alive() or apart.length() > spec.shock_radius:
			continue
		victims.append({"zombie_id": zombie_id, "damage": spec.shock_damage, "leg_damage": 0.0})
		hit_ids.append(zombie_id)
		var away := Vector3(apart.x, 0.0, apart.y).normalized()
		sim.blast(zombie_id, away * spec.shock_push, spec.shock_stun_seconds)
	rules.apply(RulesAction.explosion(player_id, victims))
	return {
		"type": &"shock_burst",
		"player_id": player_id,
		"point": at,
		"radius": spec.shock_radius,
		"hits": hit_ids,
	}
