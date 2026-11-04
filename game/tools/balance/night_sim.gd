class_name NightSim
extends RefCounted
## One whole night through the real rules, played by modelled players. Headless and node-free: it
## sends `GameRules` the same actions a server would (tick, hit, buy, set_downed, skip_break) and
## reads the same events. What is modelled is only the part the rules do not own: where the
## zombies are, whether a shot lands, whether a blow lands, when a player is down or up again, and
## what the players buy. See `SimSkill` for the player and `docs/design/rounds.md` for the model.
##
## Deterministic: the rules have their seed, the model has its own, and the step is fixed.

## Metres from a zombie's spawn to the player it walks to.
const SPAWN_DISTANCE_MIN := 18.0
const SPAWN_DISTANCE_MAX := 32.0
## Seconds a walker needs to tear its way through a barrier (a type's `barrier_speed` speeds it up).
const BARRIER_SECONDS := 6.0
## How far a night's play strays from the level's average, either way.
const NIGHT_SPREAD := 0.2
## Players see (and shoot) this far at the lightest, plus `VIEW_PER_LIGHT` more in full light: the
## night closes in, so late rounds are fought closer.
const VIEW_MIN := 8.0
const VIEW_PER_LIGHT := 25.0
## Zombies come at the lot from this many sides (windows); a player faces one at a time and turning
## to another costs this long.
const SIDES := 4
const TURN_SECONDS := 0.6
## Fire time lost per metre of knockback.
const STUN_PER_METRE := 0.3
## Players mend fully between rounds. A player buys a fuel can when the tank is below this.
const FUEL_BUY_BELOW := 35.0
## A player gives up a weapon for another only when the new one is worth this many times more, so a
## small difference (that comes and goes with the round's health) does not make them buy in circles.
const REPLACE_GAIN := WeaponWorth.REPLACE_GAIN
## Seconds per tick while the shopper waits at the crane in a break.
const CRANE_STEP := 0.25
## Prizes the simulator does not play (#788): the freeze is not modelled, and the ray gun's blast on
## a crowd and its dear rounds are, but its hurt to its shooter is not, so a shopper that won one
## would be worth more than it is. They are out of the crane's pool here, so the gate stays the
## eight weapons' until the wonder weapons are modelled.
const UNMODELLED: Array[StringName] = [&"weapon_ray_gun", &"weapon_freeze_gun"]
## Seconds to put a dry weapon away and take another.
const SWAP_SECONDS := 0.6
## A dry player with points to spend runs to a locker: the walk there, the purchase and the walk
## back, all without shooting while the dead keep coming. A weapon left worth less than this share
## of the best one carried is not worth fighting on with.
const RESUPPLY_SECONDS := 8.0
const RUN_BELOW := 0.75
## A player who reads the fight takes another loaded weapon in hand when it does at least this much
## more damage a second to the target in front of them than the one they hold (it costs a swap).
const SWITCH_GAIN := 1.4
## Magazines of reserve a player buys for each weapon before a special round, points permitting.
const PREPARED_MAGS := 6
## A weapon is worth buying rounds for when its sustained damage is at least this share of the best
## one the player carries.
const USEFUL_SHARE := 0.5

var rules: GameRules
var skill: SimSkill
var step: float
## The numbers the night (not the rules) owns: a zombie's swing. The shipped defaults, as the real
## night loads them. The player's health and mending are the rules' (`tuning.player`).
var zombies_tuning := ZombieTuning.shipped()

var _rng := RandomNumberGenerator.new()
var _players: Dictionary[int, SimPlayer] = {}
var _zombies: Dictionary[int, SimZombie] = {}
var _clock: float = 0.0
var _round_start_clock: float = 0.0
var _round: Dictionary = {}
var _result: Dictionary = {
	"rounds": {},
	"ttk": {},
	"spent_on": {},
	"hurt_by": {},
	"rounds_reached": 0,
	"died": false,
	"dry_rounds": 0,
	"runs": 0,
}
var _earned_mark: int = 0
var _kills_mark: int = 0
var _heads_mark: int = 0
var _spent_mark: int = 0
var _over: bool = false


func _init(
	p_tuning: RulesTuning,
	p_skill: SimSkill,
	players: int,
	seed_value: int,
	p_step: float,
	p_settings: MatchSettings = null
) -> void:
	step = p_step
	_leave_out_the_unmodelled(p_tuning)
	rules = GameRules.new(p_tuning, seed_value, p_settings)
	_rng.seed = seed_value ^ 0x51A7
	skill = p_skill.jittered(_rng, NIGHT_SPREAD)
	_set_lights()
	for id in range(1, players + 1):
		rules.apply(RulesAction.add_player(id))
		var player := SimPlayer.new()
		player.id = id
		for weapon_id in SimWeapons.START_ARMS:
			player.arms[weapon_id] = SimArm.of(weapon_id)
		player.weapon = SimWeapons.START
		player.health = p_tuning.health.max_health
		player.max_health = p_tuning.health.max_health
		player.regen_delay = p_tuning.health.regen_delay
		_players[id] = player


## Plays until everyone is down or `max_rounds` rounds have been cleared. Returns the night's
## record.
## Takes the prizes of `UNMODELLED` out of the crane's pool and weights of `tuning` (a copy the
## caller owns, as every simulated night's is).
static func _leave_out_the_unmodelled(tuning: RulesTuning) -> void:
	var item := tuning.economy.item(&"crane_play")
	if item == null:
		return
	var pool: Array[StringName] = []
	var weights := PackedFloat32Array()
	for i in item.pool.size():
		if not UNMODELLED.has(item.pool[i]):
			pool.append(item.pool[i])
			weights.append(item.weight_of(item.pool[i]))
	item.pool = pool
	item.pool_weights = weights


func run(max_rounds: int) -> Dictionary:
	_handle(rules.apply(RulesAction.start()))
	while not _over:
		if rules.phase == GameRules.Phase.BREAK:
			_between_rounds()
			if rules.round_number >= max_rounds:
				break
			_handle(rules.apply(RulesAction.skip_break()))
		elif rules.phase == GameRules.Phase.ACTIVE:
			# A long wait in the break (the crane's spin) can run the break out: that round is one
			# past the last the cell counts, so the night ends where it was meant to.
			if rules.round_number > max_rounds:
				break
			_step()
		else:
			break
	for player: SimPlayer in _players.values():
		if player.dry:
			_result["dry_rounds"] += 1
	_result["died"] = rules.phase == GameRules.Phase.OVER
	_result["rounds_reached"] = rules.round_number
	_close_round(false)
	return _result


# --- One step of an active round ---


func _step() -> void:
	_clock += step
	_handle(rules.apply(RulesAction.tick(step)))
	if _over or rules.phase != GameRules.Phase.ACTIVE:
		return
	var engaged := _move_zombies()
	for player: SimPlayer in _players.values():
		_mend(player, engaged)
	for player: SimPlayer in _players.values():
		if not player.downed and not _over:
			_shoot(player)


## Moves every zombie, lands blows, and returns how many zombies are in reach of each player.
func _move_zombies() -> Dictionary:
	var engaged := {}
	var pace := 1.0 + (1.0 - _lit_share()) * (rules.tuning.rounds.dark_speed_multiplier - 1.0)
	for zombie: SimZombie in _zombies.values():
		if zombie.stun > 0.0:
			# Held still by a shock (the shock perk): no step, no blow.
			zombie.stun -= step
			continue
		if zombie.distance > 0.0:
			zombie.distance -= zombie.speed * pace * step
			continue
		if zombie.barrier > 0.0:
			zombie.barrier -= step * zombie.barrier_speed
			continue
		var target := _target_of(zombie)
		if target == null:
			continue
		engaged[target.id] = engaged.get(target.id, 0) + 1
		zombie.swing += step
		if zombie.swing >= zombies_tuning.swing_seconds + zombie.telegraph:
			zombie.swing = 0.0
			_blow(zombie, target)
		if _over:
			break
	return engaged


func _target_of(zombie: SimZombie) -> SimPlayer:
	var target: SimPlayer = _players.get(zombie.target)
	if target != null and not target.downed:
		return target
	var standing: Array[SimPlayer] = []
	for player: SimPlayer in _players.values():
		if not player.downed:
			standing.append(player)
	if standing.is_empty():
		return null
	var chosen := standing[_rng.randi() % standing.size()]
	zombie.target = chosen.id
	return chosen


func _blow(zombie: SimZombie, target: SimPlayer) -> void:
	var land := 1.0 - skill.dodge
	if zombie.telegraph > 0.0:
		land = minf(land, 1.0) * exp(-zombie.telegraph * skill.read)
	if _rng.randf() >= land:
		return
	target.health -= zombie.damage
	var hurt: Dictionary = _result["hurt_by"]
	hurt[zombie.type] = hurt.get(zombie.type, 0.0) + zombie.damage
	target.lowest = minf(target.lowest, maxf(target.health, 0.0) / target.max_health)
	target.damage_taken += zombie.damage
	target.last_hit = _clock
	target.stun = maxf(target.stun, zombie.knockback * STUN_PER_METRE)
	if target.health <= 0.0:
		target.downed = true
		target.revive = 0.0
		_handle(rules.apply(RulesAction.set_downed(target.id, true)))


func _mend(player: SimPlayer, engaged: Dictionary) -> void:
	if player.downed:
		# A player who bled out stays down until the round ends (the rules say when).
		if player.dead:
			return
		var helper: SimPlayer = null
		for other: SimPlayer in _players.values():
			if not other.downed and engaged.get(other.id, 0) == 0:
				helper = other
				player.revive += step
				break
		# The real revive: the rules' own channel time and share of health, sent as the action a
		# teammate's hold on use ends in.
		if helper != null and player.revive >= PerkEffects.revive_seconds(rules, helper.id):
			player.last_hit = _clock
			_handle(rules.apply(RulesAction.revive(helper.id, player.id)))
		return
	player.stun = maxf(player.stun - step, 0.0)
	if _clock - player.last_hit >= player.regen_delay:
		var mended := rules.tuning.health.regen_per_second * step
		player.health = minf(player.health + mended, player.max_health)


# --- Shooting ---


## The weapon in hand: a carried one, or the knife when no melee weapon is carried and the firearms
## are dry (the always-available blow: the quick melee's own numbers, #411).
func _held_arm(player: SimPlayer) -> SimArm:
	return player.arms.get(player.weapon, player.knife)


func _shoot(player: SimPlayer) -> void:
	var weapon := player.weapon
	var arm := _held_arm(player)
	if player.reload_left > 0.0:
		# A reload runs on the clock, shooting or not; what is left of the step is shot time.
		player.reload_left -= step
		if player.reload_left > 0.0:
			return
		arm.reload()
		player.carry = minf(-player.reload_left, step) * skill.uptime
		player.reload_left = 0.0
	else:
		player.carry += step * skill.uptime
	if player.stun > 0.0:
		player.carry = 0.0
		return
	var melee := SimWeapons.is_melee(weapon)
	var interval := SimWeapons.interval(weapon)
	if not melee:
		interval *= PerkEffects.fire_interval_scale(rules, player.id)
	while player.carry >= interval and not _over:
		var zombie := _pick_melee(player) if melee else _pick_target(player)
		if zombie == null:
			player.carry = 0.0
			return
		if skill.swaps and not melee and _switch_for(player, zombie):
			return
		player.carry -= interval
		_fire_at(player, zombie)
		if melee:
			continue
		arm.mag -= 1
		if arm.mag <= 0:
			if arm.reserve > 0:
				player.reload_left = (
					SimWeapons.reload_seconds(weapon)
					* PerkEffects.reload_time_scale(rules, player.id)
				)
				_shock(player)
			else:
				_out_of_rounds(player)
			player.carry = 0.0
			return


## The shock perk: a reload gives off a shock that hurts and holds the dead within its radius (a
## zombie's `distance` is how far it is from the players). The wait between shocks is the tuning's.
func _shock(player: SimPlayer) -> void:
	if player.shock_wait > _clock or not PerkEffects.has(rules, player.id, ShopItem.Effect.SHOCK):
		return
	var spec := rules.tuning.perks
	player.shock_wait = _clock + spec.shock_cooldown
	var victims: Array = []
	var ids := _zombies.keys()
	ids.sort()
	for zombie_id: int in ids:
		var zombie: SimZombie = _zombies[zombie_id]
		if zombie.distance > spec.shock_radius:
			continue
		zombie.stun = spec.shock_stun_seconds
		victims.append({"zombie_id": zombie_id, "damage": spec.shock_damage, "leg_damage": 0.0})
	if not victims.is_empty():
		_handle(rules.apply(RulesAction.explosion(player.id, victims)))


## Takes the weapon that does the most to this target if it beats the one in hand by `SWITCH_GAIN`
## (a shotgun for what is at the door, the rifle for what is far). True when it swapped, which
## costs a moment.
func _switch_for(player: SimPlayer, zombie: SimZombie) -> bool:
	var distance := maxf(zombie.distance, 0.0)
	var held := _worth_at(_held_arm(player), distance)
	var pick := player.weapon
	var pick_worth := held * SWITCH_GAIN
	for weapon_id: StringName in player.arms:
		var worth := _worth_at(player.arms[weapon_id], distance)
		if worth > pick_worth:
			pick = weapon_id
			pick_worth = worth
	if pick == player.weapon:
		return false
	player.weapon = pick
	player.reload_left = 0.0
	player.stun = maxf(player.stun, SWAP_SECONDS)
	player.carry = 0.0
	return true


## The health of the walker this round sends: what the players size their weapons against.
func _health() -> float:
	return rules.tuning.rounds.health_for_round(rules.round_number)


## Health a second a loaded firearm takes off a body `distance` metres away (0 when it is empty).
func _worth_at(arm: SimArm, distance: float) -> float:
	if SimWeapons.is_melee(arm.id) or arm.mag <= 0:
		return 0.0
	return SimWeapons.kill_rate_of(arm.def(), distance, _health())


## The magazine and the reserve are both empty: take the best weapon that still has rounds, or the
## crowbar, and lose a moment doing it.
func _out_of_rounds(player: SimPlayer) -> void:
	var before := player.weapon
	player.weapon = SimWeapons.best_armed(player.arms, _health())
	var best := 0.0
	for weapon_id: StringName in player.arms:
		if not SimWeapons.is_melee(weapon_id):
			best = maxf(best, SimWeapons.sustained_dps_of(player.arms[weapon_id].def(), _health()))
	var left := (
		0.0
		if SimWeapons.is_melee(player.weapon)
		else SimWeapons.sustained_dps_of(_held_arm(player).def(), _health())
	)
	if left < best * RUN_BELOW and _resupply_run(player):
		return
	if player.weapon != before:
		player.stun = maxf(player.stun, SWAP_SECONDS)
		if SimWeapons.is_melee(player.weapon):
			player.dry = true


## The run to a locker in the middle of a round: buys what the points allow (down to the usual
## floor of magazines), then spends the time away. False when nothing could be bought.
func _resupply_run(player: SimPlayer) -> bool:
	var bought := 0
	for weapon_id in _useful(player):
		var arm: SimArm = player.arms[weapon_id]
		bought += _restock(player, weapon_id, arm.def().magazine_size * skill.ammo_floor_mags)
	if bought <= 0:
		return false
	_result["runs"] += 1
	player.weapon = SimWeapons.best_armed(player.arms, _health())
	player.stun = maxf(player.stun, RESUPPLY_SECONDS)
	player.reload_left = 0.0
	return true


## A zombie within reach of a blow that is after this player: the crowbar needs no sight, only a
## dead man at arm's length.
func _pick_melee(player: SimPlayer) -> SimZombie:
	for zombie: SimZombie in _zombies.values():
		if zombie.target == player.id and zombie.distance <= 0.0 and zombie.barrier <= 0.0:
			return zombie
	return null


## The nearest zombie on the side the player faces. A player turns to another side when nothing is
## left on this one, or when a zombie is already at the door on another side and none is here.
func _pick_target(player: SimPlayer) -> SimZombie:
	var own: SimZombie = null
	var any: SimZombie = null
	var facing: SimZombie = null
	var view := (
		VIEW_MIN + VIEW_PER_LIGHT * rules.tuning.rounds.ambient_for_round(rules.round_number)
	)
	for zombie: SimZombie in _zombies.values():
		if zombie.distance > view:
			continue
		if any == null or zombie.distance < any.distance:
			any = zombie
		if zombie.target == player.id and (own == null or zombie.distance < own.distance):
			own = zombie
	var pool_first := own if own != null else any
	if pool_first == null:
		return null
	for zombie: SimZombie in _zombies.values():
		if (
			zombie.side == player.side
			and zombie.distance <= view
			and (zombie.target == player.id or own == null)
			and (facing == null or zombie.distance < facing.distance)
		):
			facing = zombie
	if facing != null and (facing.distance <= 0.0 or pool_first.distance > 0.0):
		return facing
	player.side = pool_first.side
	player.stun = TURN_SECONDS
	return null


func _fire_at(player: SimPlayer, zombie: SimZombie) -> void:
	zombie.shots += 1
	if _rng.randf() >= skill.accuracy * zombie.hit_chance:
		return
	var zone := &"body"
	var roll := _rng.randf()
	if zombie.boss:
		if roll < skill.weak_spot_rate:
			zone = &"weak"
	elif roll < skill.head_rate:
		zone = &"head"
	elif roll < skill.head_rate + skill.limb_rate:
		zone = &"limb"
	if zombie.first_hit < 0.0:
		zombie.first_hit = _clock
	var melee := SimWeapons.is_melee(player.weapon)
	var damage := SimWeapons.damage_of(_held_arm(player).def(), zone, maxf(zombie.distance, 0.0))
	_splash(player, zombie)
	_handle(rules.apply(RulesAction.hit(player.id, zombie.id, zone, damage, melee)))


## A bursting shot hurts the others on the same side near the one it hit (a flare); the one it hit
## takes the direct hit only, as in the combat server.
func _splash(player: SimPlayer, hit: SimZombie) -> void:
	var weapon: WeaponDef = _held_arm(player).def()
	if weapon.splash_radius <= 0.0:
		return
	for other: SimZombie in _zombies.values().duplicate():
		if other == hit or other.side != hit.side:
			continue
		var blast := SimWeapons.splash_of(weapon, absf(other.distance - hit.distance))
		if blast > 0.0 and not _over:
			_handle(rules.apply(RulesAction.hit(player.id, other.id, &"body", blast)))


# --- Events ---


func _handle(events: Array[Dictionary]) -> void:
	for event in events:
		match event["type"]:
			&"zombie_spawn_requested":
				_spawned(event)
			&"zombie_removed":
				_removed(event)
			&"round_started":
				_open_round(event)
			&"round_ended":
				_close_round(true)
			&"player_revived":
				var revived: SimPlayer = _players.get(event["player_id"])
				if revived != null and revived.downed:
					revived.downed = false
					revived.dead = false
					revived.health = rules.health_of(revived.id)
			&"perks_lost":
				var lost: SimPlayer = _players.get(event["player_id"])
				if lost != null:
					_lose_perks(lost)
			&"player_died":
				var dead: SimPlayer = _players.get(event["player_id"])
				if dead != null:
					dead.dead = true
			&"game_over":
				_over = true


## A player went down and lost tonics: the most health and the weapons the rules took away.
func _lose_perks(player: SimPlayer) -> void:
	var owned: PlayerState = rules.players[player.id]
	player.max_health = owned.max_health
	var carried: Array[StringName] = []
	for shop_id in owned.weapons:
		carried.append(WeaponCatalog.catalog_id(shop_id))
	for weapon_id in player.arms.keys():
		if not carried.has(weapon_id):
			player.arms.erase(weapon_id)
	if not player.arms.has(player.weapon):
		player.weapon = SimWeapons.best_armed(player.arms, _health())
		player.reload_left = 0.0


func _spawned(event: Dictionary) -> void:
	var zombie := SimZombie.new()
	zombie.id = event["zombie_id"]
	zombie.type = event["zombie_type"]
	zombie.boss = event["boss"]
	zombie.speed = event["speed"]
	zombie.damage = event["damage"]
	zombie.knockback = event["knockback"]
	zombie.telegraph = event["telegraph_seconds"]
	# A crawling look is shot at through zones fitted to its body on the ground, so it is no harder to
	# hit than a walker (`ZombieProfile.hit_scale`, #694): the type's chance sized an upright set.
	zombie.hit_chance = 1.0 if ZombieModels.crawls(event["look"]) else event["hit_chance"]
	zombie.barrier_speed = event["barrier_speed"]
	zombie.barrier = BARRIER_SECONDS if zombie.barrier_speed > 0.0 else 0.0
	zombie.distance = _rng.randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
	zombie.target = 1 + _rng.randi() % _players.size()
	zombie.side = _rng.randi() % SIDES
	_zombies[zombie.id] = zombie


func _removed(event: Dictionary) -> void:
	var zombie: SimZombie = _zombies.get(event["zombie_id"])
	_zombies.erase(event["zombie_id"])
	if zombie == null or event["cause"] != &"killed":
		return
	var ttk: Array = _result["ttk"].get(zombie.type, [0, 0.0, 0])
	ttk[0] += 1
	ttk[1] += _clock - zombie.first_hit if zombie.first_hit >= 0.0 else 0.0
	ttk[2] += zombie.shots
	_result["ttk"][zombie.type] = ttk


func _open_round(event: Dictionary) -> void:
	_round_start_clock = _clock
	_earned_mark = _total("points_earned")
	_kills_mark = _total("kills")
	_heads_mark = _total("headshot_kills")
	_spent_mark = _total("points_spent")
	for player: SimPlayer in _players.values():
		player.damage_taken = 0.0
		player.lowest = 1.0
	_round = {
		"special": event["special_id"],
		"zombies": event["zombie_count"],
		"bosses": event["boss_count"],
		"cleared": false,
	}
	_result["rounds"][event["round"]] = _round


func _close_round(cleared: bool) -> void:
	if _round.is_empty():
		return
	var damage := 0.0
	var pressure := 0.0
	for player: SimPlayer in _players.values():
		damage += player.damage_taken
		pressure += 1.0 - player.lowest
	_round["damage"] = damage / float(_players.size())
	_round["pressure"] = pressure / float(_players.size())
	_round["duration"] = _clock - _round_start_clock
	_round["earned"] = float(_total("points_earned") - _earned_mark) / float(_players.size())
	# Zombies killed in the round (all players together), and the share of them shot in the head.
	_round["kills"] = _total("kills") - _kills_mark
	_round["head_kills"] = _total("headshot_kills") - _heads_mark
	_round["cleared"] = cleared
	_round = {}


func _total(field: String) -> int:
	var sum := 0
	for player: PlayerState in rules.players.values():
		sum += player.get(field)
	return sum


# --- Lights ---


## Puts the circuits the modelled player keeps on, on, and every other off, as a player at the
## switches would. The generator burns for each one and the dead keep their round's pace on lit
## ground only while it has fuel (off it they are faster), so the light costs what it costs in the
## game.
func _set_lights() -> void:
	for circuit_id: StringName in rules.tuning.fuel.circuit_drain:
		rules.apply(RulesAction.set_circuit(circuit_id, skill.circuits.has(circuit_id)))


## Share of the dead's walk that is on lit ground right now: the skill's share, scaled by how many
## of its circuits are lit and by the brownout as the tank runs dry.
func _lit_share() -> float:
	if skill.circuits.is_empty():
		return 0.0
	var lit := 0
	for circuit_id in skill.circuits:
		if rules.generator.is_lit(circuit_id):
			lit += 1
	return (
		skill.light_use * float(lit) / float(skill.circuits.size()) * rules.generator.power_level()
	)


# --- Between rounds ---


func _between_rounds() -> void:
	for player: SimPlayer in _players.values():
		_refresh(player)
		player.health = player.max_health
		player.downed = false
		player.dead = false
		player.last_hit = -100.0
		player.stun = 0.0
	for player: SimPlayer in _players.values():
		_shop(player)
		_refresh(player)


## Reads what the player now owns off the rules: weapons, and the most health a tonic gave (the
## rules own both; a re-cut is applied where it is bought, `_buy_upgrade`).
func _refresh(player: SimPlayer) -> void:
	var owned: PlayerState = rules.players[player.id]
	player.max_health = owned.max_health
	var carried: Array[StringName] = []
	for shop_id in owned.weapons:
		var weapon_id := WeaponCatalog.catalog_id(shop_id)
		carried.append(weapon_id)
		if not player.arms.has(weapon_id):
			player.arms[weapon_id] = SimArm.of(weapon_id)
	# A weapon the rules released (the hands are full) is gone, rounds and all.
	for weapon_id in player.arms.keys():
		if not carried.has(weapon_id):
			player.arms.erase(weapon_id)
	# A player reloads in the break, for free.
	for arm: SimArm in player.arms.values():
		arm.reload()
	player.weapon = SimWeapons.best_armed(player.arms, _health())
	player.reload_left = 0.0
	player.carry = 0.0
	if player.dry:
		player.dry = false
		_result["dry_rounds"] += 1


## What a player does with their points between rounds, in order: fuel, the rounds they cannot
## fight without (`skill.ammo_floor_mags` magazines of reserve for each weapon worth shooting), the
## things they are saving for (doors, weapons), and last topping the reserves up with what is left
## over once the next thing on the list is paid for.
func _shop(player: SimPlayer) -> void:
	if rules.generator.fuel < FUEL_BUY_BELOW:
		_buy(player, &"fuel_can")
	# The marquee announces a special round: everyone fills up for it, whatever else they save for.
	var prepared := rules.tuning.specials.special_for(rules.round_number + 1) != null
	var floor_mags := PREPARED_MAGS if prepared else skill.ammo_floor_mags
	for weapon_id in _useful(player):
		var arm: SimArm = player.arms[weapon_id]
		_restock(player, weapon_id, arm.def().magazine_size * floor_mags)
	var wanted := skill.shopping.duplicate()
	var bought := true
	while bought:
		bought = false
		for item_id: StringName in wanted:
			if _buy(player, item_id) > 0:
				wanted.erase(item_id)
				bought = true
				_refresh(player)
				break
			# Saving for the next big thing: nothing after it is bought until it is.
			if skill.saves_for.has(item_id) and _can_ever_buy(player, item_id):
				break
	var keep := rules.price_of(wanted[0], player.id) if not wanted.is_empty() else 0
	var topoff := 1.0 if prepared else skill.ammo_topoff
	for weapon_id in _useful(player):
		var top := int(float(player.arms[weapon_id].def().reserve_max) * topoff)
		_restock(player, weapon_id, top, keep)


## The carried firearms worth buying rounds for, best first.
func _useful(player: SimPlayer) -> Array[StringName]:
	var best := 0.0
	for weapon_id: StringName in player.arms:
		if not SimWeapons.is_melee(weapon_id):
			best = maxf(best, SimWeapons.sustained_dps_of(player.arms[weapon_id].def(), _health()))
	var useful: Array[StringName] = []
	for weapon_id: StringName in player.arms:
		if SimWeapons.is_melee(weapon_id):
			continue
		if (
			SimWeapons.sustained_dps_of(player.arms[weapon_id].def(), _health())
			>= best * USEFUL_SHARE
		):
			useful.append(weapon_id)
	useful.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return (
				SimWeapons.sustained_dps_of(player.arms[a].def(), _health())
				> SimWeapons.sustained_dps_of(player.arms[b].def(), _health())
			)
	)
	return useful


## Buys rounds for a weapon, a purchase at a time, until its reserve holds `target` rounds, it is
## full, or the player cannot pay and still keep `keep` points. Returns the rounds bought.
func _restock(player: SimPlayer, weapon_id: StringName, target: int, keep: int = 0) -> int:
	var arm: SimArm = player.arms[weapon_id]
	var item := _ammo_item(weapon_id)
	var total := 0
	if item == null:
		return total
	while arm.reserve < mini(target, arm.def().reserve_max):
		var room := arm.def().reserve_max - arm.reserve
		var price := item.ammo_price(rules.round_number, room)
		if rules.points_of(player.id) - price < keep:
			break
		var rounds := _buy(player, item.id, room)
		if rounds <= 0:
			break
		arm.reserve += rounds
		total += rounds
	return total


func _ammo_item(weapon_id: StringName) -> ShopItem:
	for item in rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.AMMO and item.weapon == weapon_id:
			return item
	return null


## Buys one item; returns 0 when it did not sell, else 1 (for ammunition, the rounds that went into
## the reserve). `rounds` is the room an ammunition purchase has (the combat server's number in the
## game).
func _buy(player: SimPlayer, item_id: StringName, rounds: int = -1) -> int:
	var weapon := _re_cut_weapon(player) if item_id == &"upgrade_weapon" else &""
	if _is_weapon_item(item_id):
		if not _worth_taking(player, item_id):
			return 0
		weapon = _weakest(player)
	if item_id == &"crane_play" and not _crane_can_pay_off(player):
		return 0
	for event in rules.apply(RulesAction.buy(player.id, item_id, rounds, weapon)):
		if event["type"] == &"purchase_made":
			var spent: Dictionary = _result["spent_on"]
			spent[item_id] = spent.get(item_id, 0) + event["price"]
			if item_id == &"crane_play":
				return 1 if _play_crane(player, event["price"]) else 0
			if item_id == &"upgrade_weapon":
				player.arms[weapon].upgrade(rules.tuning.upgrade)
			return int(event["detail"].get("rounds", 1))
	return 0


## Whether the shop sells this item as a weapon.
func _is_weapon_item(item_id: StringName) -> bool:
	var item := rules.tuning.economy.item(item_id)
	return item != null and item.kind == ShopItem.Kind.WEAPON


## The carried weapon worth least: what the player gives up when the hands are full.
func _weakest(player: SimPlayer) -> StringName:
	var weakest: StringName = &""
	var least := INF
	for weapon_id: StringName in player.arms:
		var worth := SimWeapons.worth_of(player.arms[weapon_id].def(), _health())
		if worth < least:
			least = worth
			weakest = weapon_id
	return weakest


## Whether a weapon (a shop id) is worth taking: it must be worth more than what it would put
## away. Full hands give up the weakest weapon carried; a free hand is worth the quick melee (#411),
## the blow every player has, so a weapon that does less than that is not worth a slot or a price.
func _worth_taking(player: SimPlayer, shop_id: StringName) -> bool:
	var given_up := player.knife
	if player.arms.size() >= PerkEffects.carry_limit(rules, player.id):
		given_up = player.arms[_weakest(player)]
	return (
		SimWeapons.worth_of(SimWeapons.def(shop_id), _health())
		> SimWeapons.worth_of(given_up.def(), _health()) * REPLACE_GAIN
	)


## Whether a play can give a weapon worth taking: some prize the player lacks beats their weakest.
## Nobody pays for a prize they would leave on the glass.
func _crane_can_pay_off(player: SimPlayer) -> bool:
	var item := rules.tuning.economy.item(&"crane_play")
	for shop_id in item.pool_without(rules.players[player.id].weapons):
		if _worth_taking(player, shop_id):
			return true
	return false


## The weapon a player puts on the bench: the firearm that kills most, re-cut, among those not yet
## re-cut. `&""` when there is none.
func _re_cut_weapon(player: SimPlayer) -> StringName:
	var spec := rules.tuning.upgrade
	var best_id: StringName = &""
	var best_rate := -1.0
	if rules.players[player.id].upgraded.size() >= skill.re_cuts:
		return best_id
	for weapon_id: StringName in player.arms:
		var arm: SimArm = player.arms[weapon_id]
		if arm.tier() > 0 or not spec.allows(weapon_id):
			continue
		var rate := SimWeapons.sustained_dps_of(arm.def().upgraded(spec), _health())
		if rate > best_rate:
			best_rate = rate
			best_id = weapon_id
	return best_id


## Whether the item may still be sold to this player some day, so saving for it is sensible (it is
## not already owned, and there is a weapon to re-cut).
func _can_ever_buy(player: SimPlayer, item_id: StringName) -> bool:
	if item_id == &"upgrade_weapon":
		return _re_cut_weapon(player) != &""
	if item_id == &"crane_play":
		return _crane_can_pay_off(player)
	if _is_weapon_item(item_id):
		return _worth_taking(player, item_id) and not rules.players[player.id].weapons.has(item_id)
	var tonics := rules.players[player.id].tonics
	return (
		not tonics.has(item_id) and tonics.size() < rules.settings.tonic_limit(rules.tuning.economy)
	)


## Spins the crane out in the break (the shopper stands at the glass, so the weapon is taken the
## moment it is held out). False when the crane broke down: the price is back and the player tries
## again at the next break.
func _play_crane(player: SimPlayer, price: int) -> bool:
	var won := false
	var broke := false
	while not rules.crane.is_ready() and rules.phase == GameRules.Phase.BREAK:
		var caused := rules.apply(RulesAction.tick(CRANE_STEP))
		for event in caused:
			if event["type"] == &"crane_prize_ready":
				# The prize is taken when it beats the weakest weapon carried; else it fades.
				if _worth_taking(player, event["weapon"]):
					rules.apply(RulesAction.crane_take(player.id, _weakest(player)))
					won = true
			elif event["type"] == &"crane_breakdown":
				broke = true
		_handle(caused)
	if broke:
		var spent: Dictionary = _result["spent_on"]
		spent[&"crane_play"] -= price
	return won


class SimPlayer:
	extends RefCounted
	var id: int = 0
	var health: float = 100.0
	var max_health: float = 100.0
	var downed: bool = false
	## Bled out: down until the round ends.
	var dead: bool = false
	var weapon: StringName = &"house_pistol"
	## Every weapon carried (catalogue id to its magazine and reserve).
	var arms: Dictionary[StringName, SimArm] = {}
	## The blow every player has whatever they carry.
	var knife: SimArm = SimArm.of(WeaponCatalog.QUICK_MELEE)
	## Ran out of every firearm this round and fought with the quick melee.
	var dry: bool = false
	## Shot time banked toward the next trigger pull, in seconds.
	var carry: float = 0.0
	var reload_left: float = 0.0
	var stun: float = 0.0
	var last_hit: float = -100.0
	var revive: float = 0.0
	## The clock at which the shock perk may fire again.
	var shock_wait: float = 0.0
	var regen_delay: float = 5.0
	var damage_taken: float = 0.0
	## The lowest share of health the player reached this round.
	var lowest: float = 1.0
	var side: int = 0


## One weapon carried: rounds in the magazine and in reserve, as the combat server keeps them.
class SimArm:
	extends RefCounted
	var id: StringName = &""
	var mag: int = 0
	var reserve: int = 0
	var _def: WeaponDef

	static func of(weapon_id: StringName) -> SimArm:
		var arm := SimArm.new()
		arm.id = weapon_id
		arm._def = SimWeapons.def(weapon_id)
		arm.mag = arm._def.magazine_size
		arm.reserve = arm._def.reserve_start
		return arm

	## The definition in use: the catalogue's, or its re-cut copy.
	func def() -> WeaponDef:
		return _def

	func tier() -> int:
		return _def.tier

	## A re-cut, as `WeaponState.upgrade` does it: the numbers of `WeaponDef.upgraded`, then the
	## magazine and the reserve full.
	func upgrade(spec: UpgradeTuning) -> void:
		_def = _def.upgraded(spec)
		mag = _def.magazine_size
		reserve = _def.reserve_max

	## A reload: the magazine fills from the reserve, as far as the reserve goes.
	func reload() -> void:
		var moved := mini(def().magazine_size - mag, reserve)
		mag += moved
		reserve -= moved


class SimZombie:
	extends RefCounted
	var id: int = 0
	var type: StringName = &"walker"
	var boss: bool = false
	var speed: float = 1.0
	var distance: float = 20.0
	var barrier: float = 0.0
	var barrier_speed: float = 1.0
	var swing: float = 0.0
	## Seconds a shock still holds it.
	var stun: float = 0.0
	var damage: float = 20.0
	var knockback: float = 0.0
	var telegraph: float = 0.0
	var hit_chance: float = 1.0
	var target: int = 1
	var side: int = 0
	var first_hit: float = -1.0
	var shots: int = 0
