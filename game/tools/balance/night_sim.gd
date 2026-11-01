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
const REVIVE_SECONDS := 6.0
const REVIVE_HEALTH := 0.5
## Fire time lost per metre of knockback.
const STUN_PER_METRE := 0.3
## Players mend fully between rounds. A player buys a fuel can when the tank is below this.
const FUEL_BUY_BELOW := 35.0

var rules: GameRules
var skill: SimSkill
var step: float
## The numbers the night (not the rules) owns: a zombie's swing. The shipped defaults, as the real
## night loads them. The player's health and mending are the rules' (`tuning.player`).
var zombies_tuning := ZombieTuning.new()

var _rng := RandomNumberGenerator.new()
var _players: Dictionary[int, SimPlayer] = {}
var _zombies: Dictionary[int, SimZombie] = {}
var _clock: float = 0.0
var _round_start_clock: float = 0.0
var _round: Dictionary = {}
var _result: Dictionary = {
	"rounds": {}, "ttk": {}, "spent_on": {}, "hurt_by": {}, "rounds_reached": 0, "died": false
}
var _earned_mark: int = 0
var _spent_mark: int = 0
var _over: bool = false


func _init(
	p_tuning: RulesTuning, p_skill: SimSkill, players: int, seed_value: int, p_step: float
) -> void:
	step = p_step
	rules = GameRules.new(p_tuning, seed_value)
	_rng.seed = seed_value ^ 0x51A7
	skill = p_skill.jittered(_rng, NIGHT_SPREAD)
	_set_lights()
	for id in range(1, players + 1):
		rules.apply(RulesAction.add_player(id))
		var player := SimPlayer.new()
		player.id = id
		player.weapon = SimWeapons.START
		player.ammo = SimWeapons.magazine(SimWeapons.START)
		player.health = p_tuning.health.max_health
		player.max_health = p_tuning.health.max_health
		player.regen_delay = p_tuning.health.regen_delay
		_players[id] = player


## Plays until everyone is down or `max_rounds` rounds have been cleared. Returns the night's
## record.
func run(max_rounds: int) -> Dictionary:
	_handle(rules.apply(RulesAction.start()))
	while not _over:
		if rules.phase == GameRules.Phase.BREAK:
			_between_rounds()
			if rules.round_number >= max_rounds:
				break
			_handle(rules.apply(RulesAction.skip_break()))
		elif rules.phase == GameRules.Phase.ACTIVE:
			_step()
		else:
			break
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
		for other: SimPlayer in _players.values():
			if not other.downed and engaged.get(other.id, 0) == 0:
				player.revive += step
				break
		if player.revive >= REVIVE_SECONDS:
			player.downed = false
			player.health = player.max_health * REVIVE_HEALTH
			player.last_hit = _clock
			_handle(rules.apply(RulesAction.set_downed(player.id, false)))
		return
	player.stun = maxf(player.stun - step, 0.0)
	if _clock - player.last_hit >= player.regen_delay:
		var mended := rules.tuning.health.regen_per_second * step
		player.health = minf(player.health + mended, player.max_health)


# --- Shooting ---


func _shoot(player: SimPlayer) -> void:
	var weapon := player.weapon
	if player.reload_left > 0.0:
		# A reload runs on the clock, shooting or not; what is left of the step is shot time.
		player.reload_left -= step
		if player.reload_left > 0.0:
			return
		player.ammo = SimWeapons.magazine(weapon)
		player.carry = minf(-player.reload_left, step) * skill.uptime
		player.reload_left = 0.0
	else:
		player.carry += step * skill.uptime
	if player.stun > 0.0:
		player.carry = 0.0
		return
	var interval := SimWeapons.interval(weapon)
	while player.carry >= interval and not _over:
		var zombie := _pick_target(player)
		if zombie == null:
			player.carry = 0.0
			return
		player.carry -= interval
		_fire_at(player, zombie)
		player.ammo -= 1
		if player.ammo <= 0:
			player.reload_left = SimWeapons.reload_seconds(weapon)
			player.carry = 0.0
			return


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
	var damage := SimWeapons.damage(player.weapon, zone, maxf(zombie.distance, 0.0))
	_splash(player, zombie)
	_handle(rules.apply(RulesAction.hit(player.id, zombie.id, zone, damage)))


## A bursting shot hurts the others on the same side near the one it hit (a flare); the one it hit
## takes the direct hit only, as in the combat server.
func _splash(player: SimPlayer, hit: SimZombie) -> void:
	if SimWeapons.def(player.weapon).splash_radius <= 0.0:
		return
	for other: SimZombie in _zombies.values().duplicate():
		if other == hit or other.side != hit.side:
			continue
		var blast := SimWeapons.splash(player.weapon, absf(other.distance - hit.distance))
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
					revived.health = revived.max_health * REVIVE_HEALTH
			&"game_over":
				_over = true


func _spawned(event: Dictionary) -> void:
	var zombie := SimZombie.new()
	zombie.id = event["zombie_id"]
	zombie.type = event["zombie_type"]
	zombie.boss = event["boss"]
	zombie.speed = event["speed"]
	zombie.damage = event["damage"]
	zombie.knockback = event["knockback"]
	zombie.telegraph = event["telegraph_seconds"]
	zombie.hit_chance = event["hit_chance"]
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
		player.last_hit = -100.0
		player.stun = 0.0
	for player: SimPlayer in _players.values():
		_shop(player)
		_refresh(player)


## Reads what the player now owns off the rules. Tonics are shop entries the night gives no effect
## yet, so they change nothing here either.
func _refresh(player: SimPlayer) -> void:
	var owned: PlayerState = rules.players[player.id]
	player.weapon = SimWeapons.best(owned.weapons)
	player.ammo = SimWeapons.magazine(player.weapon)
	player.reload_left = 0.0
	player.carry = 0.0


func _shop(player: SimPlayer) -> void:
	if rules.generator.fuel < FUEL_BUY_BELOW:
		_buy(player, &"fuel_can")
	var wanted := skill.shopping.duplicate()
	var bought := true
	while bought:
		bought = false
		for item_id: StringName in wanted:
			if _buy(player, item_id):
				wanted.erase(item_id)
				bought = true
				break


func _buy(player: SimPlayer, item_id: StringName) -> bool:
	if rules.points_of(player.id) < rules.price_of(item_id):
		return false
	var price := rules.price_of(item_id)
	for event in rules.apply(RulesAction.buy(player.id, item_id)):
		if event["type"] == &"purchase_made":
			var spent: Dictionary = _result["spent_on"]
			spent[item_id] = spent.get(item_id, 0) + price
			return true
	return false


class SimPlayer:
	extends RefCounted
	var id: int = 0
	var health: float = 100.0
	var max_health: float = 100.0
	var downed: bool = false
	var weapon: StringName = &"pistol"
	## Shot time banked toward the next trigger pull, in seconds.
	var carry: float = 0.0
	var ammo: int = 10
	var reload_left: float = 0.0
	var stun: float = 0.0
	var last_hit: float = -100.0
	var revive: float = 0.0
	var regen_delay: float = 5.0
	var damage_taken: float = 0.0
	## The lowest share of health the player reached this round.
	var lowest: float = 1.0
	var side: int = 0


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
	var damage: float = 20.0
	var knockback: float = 0.0
	var telegraph: float = 0.0
	var hit_chance: float = 1.0
	var target: int = 1
	var side: int = 0
	var first_hit: float = -1.0
	var shots: int = 0
