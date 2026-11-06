# The autopilot with every gun dry, pinned by the dead (#1351). Its flight from a zombie is a
# straight line away from it, which ends against a wall or a crate with the zombie at its back, and
# it never turned to walk its own way; and with nothing to shoot it kept fleeing, so the crowd
# closed a ring round it and it stood in it, never striking. A seed of the nightly stood 500 s with
# the shotgun at 0 and 0 and 955 points in the north-east corner of the projection booth, one zombie
# 0.9 m away that stood in the wall and hit it through it; others stood 100 to 640 s in a ring of
# five to twenty-six, and the round never ended. The first three tests are the real night (the
# server, the lot, the shop) played by hand a tick at a time; the others are the rule alone.
extends GdUnitTestSuite

const PLAYER := 1
## Where the nightly's autopilot stood: the booth's north-east corner, against the east wall and
## the north wall, and the zombie that hit it from inside the north wall.
const CORNER := Vector3(5.45, 0.1, 22.6)
const IN_THE_WALL := Vector3(4.7, -0.1, 22.1)
## A pin in the open: where a flight from the first zombie ended against the concession's wall.
const BESIDE := Vector3(5.45, 0.1, 23.7)
const NEAR_ZOMBIE := Vector3(4.7, 0.0, 22.6)
const DOORS: Array[StringName] = [&"door_concession", &"door_booth"]
## Points left once the doors are paid for: what the stall of the nightly held (955), enough for
## rounds and a re-cut but not a weapon.
const POINTS := 950
const TICKS_PER_SECOND := 60
## Seconds the pinned autopilot is given to kill the first zombie of the night.
const SECONDS := 60
## Where the autopilot stood in the nightly's other stalls (seed 3, round 10: 26 dead in attack
## within 1.9 m, both guns at 0 and 0, 465 points; seed 8: five to sixteen dead round it for 100 to
## 640 s), the field by the concession, and the 23 nearest of those dead, as they stood.
const MOB_SPOT := Vector3(-6.5, 0.1, -3.4)
const MOB: Array[Vector2] = [
	Vector2(-6.8, -3.6),
	Vector2(-6.1, -3.2),
	Vector2(-6.8, -3.0),
	Vector2(-5.9, -3.9),
	Vector2(-6.9, -4.2),
	Vector2(-6.4, -2.5),
	Vector2(-7.4, -3.6),
	Vector2(-5.8, -2.7),
	Vector2(-6.3, -4.4),
	Vector2(-7.4, -2.9),
	Vector2(-5.4, -3.4),
	Vector2(-7.1, -2.2),
	Vector2(-6.6, -2.0),
	Vector2(-7.4, -4.5),
	Vector2(-5.6, -2.3),
	Vector2(-7.8, -4.0),
	Vector2(-5.9, -4.7),
	Vector2(-5.3, -4.2),
	Vector2(-5.2, -2.7),
	Vector2(-8.0, -2.9),
	Vector2(-6.7, -5.0),
	Vector2(-8.1, -3.6),
	Vector2(-6.0, -1.8),
]
## Round one's crowd for that test, so that the mob can be made at once.
const MOB_CROWD := 40.0
## Kills the dry autopilot makes in `SECONDS` once it is in the mob: it makes 32 (`main` and the
## pin rule alone make none: it stands in the ring for the whole minute with 28 dead alive).
const MOB_KILLS := 10
## Metres from the corner by which it has got out of it.
const OUT_BY := 3.0
## Ticks between the physics frames the engine is given (a bought door's mesh needs some).
const FRAME_EVERY := 30
const SETTLE_FRAMES := 30

var _catcher := ErrorCatcher.new()


func after_test() -> void:
	_catcher.stop()


## The shipped table with a player the dead cannot kill (as the nightly's), and a night with the
## booth's door open and both guns of the autopilot empty.
func _dry_night(crowd: float = 0.0) -> Night:
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = AutopilotRun.PLAYER_HEALTH
	if crowd > 0.0:
		tuning.rounds.count_base = crowd
		tuning.rounds.alive_cap_start = crowd
		tuning.rounds.spawn_interval_start = 0.2
	var night := await NightFixture.start(self, Night.Mode.AUTOPILOT, tuning, 7)
	night.ticks_per_frame = 0
	var price := 0
	for door_id in DOORS:
		price += tuning.economy.item(door_id).price
	night.server.rules.apply(RulesAction.grant_points(PLAYER, price + POINTS))
	for door_id in DOORS:
		assert_int(RulesFixture.buy(night.server.rules, PLAYER, door_id)).is_equal(
			GameRules.BuyResult.OK
		)
	await NightFixture.settle_bake(night)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	night.server.combat.apply(CombatAction.give_weapon(PLAYER, &"shotgun"))
	night.server.combat.apply(CombatAction.equip(PLAYER, &"shotgun"))
	for id: StringName in [&"shotgun", WeaponCatalog.START_WEAPON]:
		var gun := night.server.combat.state_of(PLAYER, id)
		gun.ammo = 0
		gun.reserve = 0
	return night


## Puts the autopilot at `at` and the first zombie of the night at `zombie_at` in its attack, and
## runs until a zombie of the night is dead or the seconds are over.
func _run_pinned(night: Night, at: Vector3, zombie_at: Vector3) -> void:
	var zombie_id := NightFixture.first_zombie(night)
	night.server.body_of(PLAYER).teleport(at)
	var zombie: ZombieBody = night.server.sim.zombies[zombie_id]
	zombie.position = zombie_at
	zombie.enter(ZombieBody.Mode.ATTACK)
	for tick in SECONDS * TICKS_PER_SECOND:
		NightFixture.run(night, 1)
		if tick % FRAME_EVERY == 0:
			await get_tree().physics_frame
		if night.state.kills > 0:
			break


func test_a_dry_autopilot_in_a_corner_with_a_zombie_in_the_wall_walks_out() -> void:
	var night := await _dry_night()
	_catcher.start()
	await _run_pinned(night, CORNER, IN_THE_WALL)
	assert_float(night.state.position().distance_to(CORNER)).is_greater(OUT_BY)
	assert_int(night.state.kills).is_greater(0)
	assert_array(_catcher.lines).is_empty()
	night.queue_free()
	await get_tree().physics_frame


## Runs until `count` zombies are on the lot and returns their bodies.
func _wait_for_dead(night: Night, count: int) -> Array[ZombieBody]:
	NightFixture.first_zombie(night)
	for _tick in 6000:
		if night.server.sim.zombies.size() >= count:
			break
		NightFixture.run(night, 1)
	var bodies: Array[ZombieBody] = []
	for id: int in night.server.sim.zombies:
		bodies.append(night.server.sim.zombies[id])
	return bodies


func test_a_dry_autopilot_in_a_mob_of_the_dead_strikes_its_way_out_and_goes_for_rounds() -> void:
	var night := await _dry_night(MOB_CROWD)
	_catcher.start()
	var bodies := _wait_for_dead(night, MOB.size())
	assert_int(bodies.size()).is_greater_equal(MOB.size())
	night.server.body_of(PLAYER).teleport(MOB_SPOT)
	for id: StringName in [&"shotgun", WeaponCatalog.START_WEAPON]:
		var gun := night.server.combat.state_of(PLAYER, id)
		gun.ammo = 0
		gun.reserve = 0
	for i in mini(bodies.size(), MOB.size()):
		bodies[i].position = Vector3(MOB[i].x, 0.0, MOB[i].y)
		bodies[i].enter(ZombieBody.Mode.ATTACK)
	for tick in SECONDS * TICKS_PER_SECOND:
		NightFixture.run(night, 1)
		if tick % FRAME_EVERY == 0:
			await get_tree().physics_frame
	assert_int(night.state.kills).is_greater_equal(MOB_KILLS)
	assert_array(_catcher.lines).is_empty()
	night.queue_free()
	await get_tree().physics_frame


func test_a_dry_autopilot_with_a_zombie_on_it_in_the_open_gets_free_and_kills_it() -> void:
	var night := await _dry_night()
	_catcher.start()
	await _run_pinned(night, BESIDE, NEAR_ZOMBIE)
	assert_int(night.state.kills).is_greater(0)
	assert_array(_catcher.lines).is_empty()
	night.queue_free()
	await get_tree().physics_frame


# --- The rule alone ---


## Stands against a wall for `seconds`, as a flight into a corner does, the pilot wanting to go on.
func _press(pilot: Autopilot, seconds: float) -> void:
	var delta := 1.0 / TICKS_PER_SECOND
	for _i in int(seconds * TICKS_PER_SECOND):
		pilot._unstuck(Vector3.RIGHT, CORNER, delta)


func test_pressed_against_a_wall_it_sidesteps_and_then_walks_its_own_way() -> void:
	var pilot := Autopilot.new(ClientState.new(), RID())
	_press(pilot, Autopilot.STUCK_AFTER + 0.1)
	assert_float(pilot._breakout).is_equal(0.0)
	_press(pilot, Autopilot.SIDESTEP_FOR + Autopilot.STUCK_AFTER + 0.1)
	assert_float(pilot._breakout).is_greater(0.0)


func test_a_sidestep_now_and_then_is_not_a_pin() -> void:
	var pilot := Autopilot.new(ClientState.new(), RID())
	var delta := 1.0 / TICKS_PER_SECOND
	for _round in 3:
		_press(pilot, Autopilot.STUCK_AFTER + 0.1)
		# Walks free for longer than the window before it catches on something again.
		for step in int((Autopilot.PINNED_WINDOW + 0.5) * TICKS_PER_SECOND):
			pilot._unstuck(Vector3.RIGHT, CORNER + Vector3(step * 0.05, 0.0, 0.0), delta)
	assert_float(pilot._breakout).is_equal(0.0)


func _pilot_holding(held: StringName, ammo: int, reserve: int) -> Autopilot:
	var state := ClientState.new()
	state.frame = {
		"players":
		{
			PLAYER:
			{
				"weapon": held,
				"ammo": ammo,
				"reserve": reserve,
				"arms": {held: [ammo, reserve, 0]},
				"points": POINTS,
			}
		},
	}
	return Autopilot.new(state, RID())


func test_a_gun_with_no_round_in_it_and_none_to_load_cannot_shoot() -> void:
	var pilot := _pilot_holding(&"shotgun", 0, 0)
	assert_bool(pilot._cannot_shoot(pilot._held())).is_true()


func test_a_gun_with_a_round_or_one_to_load_can_shoot() -> void:
	var loaded := _pilot_holding(&"shotgun", 2, 0)
	assert_bool(loaded._cannot_shoot(loaded._held())).is_false()
	var reloading := _pilot_holding(&"shotgun", 0, 8)
	assert_bool(reloading._cannot_shoot(reloading._held())).is_false()


func test_a_blade_is_never_dry_and_a_free_hand_is_not_either() -> void:
	var blade := _pilot_holding(&"crowbar", 0, 0)
	assert_bool(blade._cannot_shoot(blade._held())).is_false()
	assert_bool(blade._cannot_shoot(null)).is_false()


func test_the_melee_reach_is_the_quick_melees() -> void:
	assert_float(Autopilot.QUICK_REACH).is_equal(WeaponCatalog.quick_melee().melee_range)
