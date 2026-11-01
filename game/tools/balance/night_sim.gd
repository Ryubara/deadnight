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
## Seconds between a zombie's blows, plus the type's telegraph.
const SWING_SECONDS := 1.2
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
const PLAYER_HEALTH := 100.0
const HEARTY_BONUS := 50.0
## A player not hit for this long starts to mend (second wind halves it).
const REGEN_DELAY := 4.0
const REGEN_PER_SECOND := 25.0
const REVIVE_SECONDS := 6.0
const REVIVE_HEALTH := 0.5
## Fire time lost per metre of knockback.
const STUN_PER_METRE := 0.3
## Players mend fully between rounds.
const FUEL_BUY_BELOW := 35.0
const DARK_FUEL := 10.0

var rules: GameRules
var skill: SimSkill
var step: float

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
	for id in range(1, players + 1):
		rules.apply(RulesAction.add_player(id))
		var player := SimPlayer.new()
		player.id = id
		player.weapon = SimWeapons.START
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
	var lit := 1.0
	if rules.generator.fuel > DARK_FUEL:
		lit = 1.0 - skill.light_use * (1.0 - rules.tuning.rounds.lit_speed_multiplier)
	for zombie: SimZombie in _zombies.values():
		if zombie.distance > 0.0:
			zombie.distance -= zombie.speed * lit * step
			continue
		if zombie.barrier > 0.0:
			zombie.barrier -= step * zombie.barrier_speed
			continue
		var target := _target_of(zombie)
		if target == null:
			continue
		engaged[target.id] = engaged.get(target.id, 0) + 1
		zombie.swing += step
		if zombie.swing >= SWING_SECONDS + zombie.telegraph:
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
	land -= target.dodge_bonus
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
				player.revive += step * other.revive_speed
				break
		if player.revive >= REVIVE_SECONDS:
			player.downed = false
			player.health = player.max_health * REVIVE_HEALTH
			player.last_hit = _clock
			_handle(rules.apply(RulesAction.set_downed(player.id, false)))
		return
	player.stun = maxf(player.stun - step, 0.0)
	if _clock - player.last_hit >= player.regen_delay:
		player.health = minf(player.health + REGEN_PER_SECOND * step, player.max_health)


# --- Shooting ---


func _shoot(player: SimPlayer) -> void:
	if player.stun > 0.0:
		return
	player.carry += SimWeapons.rate(player.weapon) * player.fire_speed * skill.uptime * step
	while player.carry >= 1.0 and not _over:
		var zombie := _pick_target(player)
		if zombie == null:
			player.carry = 0.0
			return
		player.carry -= 1.0
		_fire_at(player, zombie)


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
	var damage := SimWeapons.damage(player.weapon) * float(SimWeapons.ZONE_MULTIPLIER[zone])
	_handle(rules.apply(RulesAction.hit(player.id, zombie.id, zone, damage)))


# --- Events ---


func _handle(events: Array[Dictionary]) -> void:
	for event in events:
		match event["type"]:
			&"zombie_spawn_requested":
				_spawned(event)
			&"zombie_changed":
				var zombie: SimZombie = _zombies.get(event["zombie_id"])
				if zombie != null:
					zombie.speed = event["speed"]
					zombie.hit_chance = rules.tuning.roster.type_of(event["zombie_type"]).hit_chance
					zombie.barrier = 0.0
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


## Reads what the player now owns off the rules and sets the numbers that depend on it.
func _refresh(player: SimPlayer) -> void:
	var owned: PlayerState = rules.players[player.id]
	player.weapon = SimWeapons.best(owned.weapons)
	player.max_health = PLAYER_HEALTH + (HEARTY_BONUS if owned.tonics.has(&"tonic_hearty") else 0.0)
	player.regen_delay = REGEN_DELAY * (0.5 if owned.tonics.has(&"tonic_second_wind") else 1.0)
	var quick := owned.tonics.has(&"tonic_quick_hands")
	player.fire_speed = 1.2 if quick else 1.0
	player.revive_speed = 2.0 if quick else 1.0
	player.dodge_bonus = 0.1 if owned.tonics.has(&"tonic_fleet") else 0.0


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
	var health: float = PLAYER_HEALTH
	var max_health: float = PLAYER_HEALTH
	var downed: bool = false
	var weapon: StringName = &"pistol"
	var carry: float = 0.0
	var stun: float = 0.0
	var last_hit: float = -100.0
	var revive: float = 0.0
	var regen_delay: float = REGEN_DELAY
	var fire_speed: float = 1.0
	var revive_speed: float = 1.0
	var dodge_bonus: float = 0.0
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
