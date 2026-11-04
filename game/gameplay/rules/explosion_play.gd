class_name ExplosionPlay
extends RefCounted
## One grenade blast, as the rules settle it: what it did to each zombie it reached. Static
## functions that take the rules (so no reference cycle is made), like `CranePlay`. The events are
## the rules' own (`zombie_damaged`, `zombie_removed`, `zombie_crippled`, `points_changed`).


## One blast: what it did to each zombie, in the order given. Each takes its damage off its health
## and pays like a hit (the blast that kills pays `explosion_kill`); a zombie that lives may then
## lose its legs. A zombie already gone is skipped, so a blast racing a gunshot is harmless.
static func explode(rules: GameRules, player_id: int, victims: Array) -> void:
	if rules.phase != GameRules.Phase.ACTIVE:
		rules._reject(&"wrong_phase", RulesAction.EXPLOSION)
		return
	if not rules.players.has(player_id):
		rules._reject(&"unknown_player", RulesAction.EXPLOSION)
		return
	for victim: Dictionary in victims:
		var zombie := rules._zombies.get(int(victim["zombie_id"])) as ZombieState
		if zombie != null:
			_blast_one(
				rules, player_id, zombie, float(victim["damage"]), float(victim["leg_damage"])
			)


static func _blast_one(
	rules: GameRules, player_id: int, zombie: ZombieState, damage: float, leg_damage: float
) -> void:
	var tuning := rules.tuning
	var type := rules._type(zombie.type)
	# A frozen zombie is killed by any blast, whatever it did to it.
	var shattered := rules.statuses != null and rules.statuses.shatterable(zombie.id)
	var dealt := zombie.health if shattered else minf(damage, zombie.health)
	zombie.health -= dealt
	zombie.leg_damage += minf(leg_damage, dealt)
	rules._emit_damaged(zombie, player_id, RulesAction.ZONE_BLAST, dealt)
	if zombie.health <= 0.0:
		rules._award(
			player_id, rules._scaled(tuning.explosives.explosion_kill, type), &"explosion_kill"
		)
		rules.players[player_id].kills += 1
		rules._remove_zombie(
			zombie.id, &"killed", player_id, RulesAction.ZONE_BLAST, false, shattered
		)
		return
	if zombie.paid_hits < rules._paid_hit_limit(type):
		zombie.paid_hits += 1
		rules._award(player_id, rules._scaled(tuning.economy.hit, type), &"hit")
	var cause := rules._cripple_cause(zombie)
	if cause != &"":
		zombie.crippled = true
		var crawler := tuning.roster.type_of(rules._type(zombie.type).crawls_into)
		if crawler != null:
			zombie.type = crawler.id
		(
			rules
			. _emit(
				&"zombie_crippled",
				{
					"zombie_id": zombie.id,
					"zombie_type": zombie.type,
					"look": rules._type(zombie.type).look_for(zombie.id << 8),
					"player_id": player_id,
					"cause": cause,
					"health": zombie.health,
					"speed_scale": tuning.explosives.crawler_speed_fraction,
				}
			)
		)
