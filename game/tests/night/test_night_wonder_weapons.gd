# The ray gun and the freeze gun in the real night (#788): the freeze gun's bolt freezes the zombie
# it hits for three seconds (it stops, does not attack, and the frame and the client's view say so),
# any hit on a frozen zombie but its own kills it and shatters it (the server removes it at once and
# the client draws the pieces), and the ray gun's bolt flies and bursts, drawn in blue, and hurts
# its shooter by a quarter of the splash. A night run by hand: a tick is 1/60 s and nothing waits
# on the clock.
extends GdUnitTestSuite

const SETTLE := 30
## Ticks the first zombie may take to come up out of the ground.
const EMERGE_TICKS := 150
## The trigger to the shot leaving: the body turns to the view first (#477).
const TURN_LIMIT := 60
const FLIGHT_LIMIT := 200
## How far from the player the test stands a zombie (m), straight ahead on the open ground.
const AHEAD := 6.0
const THAW_TICKS := 190

var _night: Night
var _heard: Array[Dictionary] = []
var _zombie := -1


func before_test() -> void:
	_heard = []
	var tuning := RulesFixture.tuning()
	# Zombies that two hits do not kill.
	tuning.rounds.health_base = 600.0
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	_night.state.event_received.connect(_hear)
	NightFixture.run(_night, SETTLE)
	_night.server.combat.apply(CombatAction.give_weapon(1, &"freeze_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"freeze_gun"))
	_zombie = NightFixture.first_zombie(_night)
	NightFixture.run(_night, EMERGE_TICKS)


func after_test() -> void:
	_night.state.event_received.disconnect(_hear)
	_night.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _hear(event: Dictionary) -> void:
	_heard.append(event)


func _of(type: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in _heard:
		if event["type"] == type:
			found.append(event)
	return found


func _body() -> ZombieBody:
	return _night.server.sim.zombies[_zombie]


## Stands the zombie `ahead` metres in front of the player (the +z of the open ground) and still:
## its walk is what the freeze is judged against, so it keeps its speed but is held in place by the
## test until it has something to walk to (`speed` is what it is given).
func _place(ahead: float, speed: float = 0.0) -> void:
	var body := _body()
	body.position = _night.state.position() + Vector3(0.0, 0.0, ahead)
	body.speed = speed
	NightFixture.run(_night, 3)


## Pulls the trigger once at the zombie and runs until a shot has left and, for a bolt, burst.
func _shoot(bolt := true) -> void:
	var shots := _of(&"shot_fired").size()
	var command := NightFixture.shoot_at(_night, _body().position)
	NightFixture.run(_night, 1, command)
	var ticks := 0
	while _of(&"shot_fired").size() == shots and ticks < TURN_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	assert_int(_of(&"shot_fired").size()).is_equal(shots + 1)
	var bursts := _of(&"projectile_burst").size()
	ticks = 0
	while bolt and _of(&"projectile_burst").size() == bursts and ticks < FLIGHT_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	NightFixture.run(_night, 3)


func _entry() -> Dictionary:
	for entry in _night.state.zombies:
		if entry["id"] == _zombie:
			return entry
	return {}


func _let_the_gun_cool() -> void:
	NightFixture.run(_night, 40)


func test_the_freeze_gun_freezes_what_it_hits_and_the_frame_and_the_view_say_so() -> void:
	_place(AHEAD)
	_shoot()
	var applied := _of(&"status_applied")
	assert_array(applied).is_not_empty()
	assert_int(applied[0]["target_id"]).is_equal(_zombie)
	assert_str(String(applied[0]["status"])).is_equal("frozen")
	var wire := StatusCatalog.get_def(&"frozen").wire
	assert_int(_night.server.sim.zombies[_zombie].status).is_equal(wire)
	# The snapshot every client draws from carries it, and the client's view wears it.
	assert_int(_entry()["status"]).is_equal(wire)
	assert_int(_night.view.horde.view_of(_zombie).status()).is_equal(wire)
	assert_bool(_night.view.horde.view_of(_zombie).is_held()).is_true()


func test_a_frozen_zombie_stands_for_three_seconds_and_then_walks_again() -> void:
	_place(AHEAD)
	_shoot()
	# Given a speed again, it still does not move: the freeze holds it.
	_body().speed = 2.0
	var held := _body().position
	NightFixture.run(_night, 150)
	assert_vector(_body().position).is_equal(held)
	assert_int(_entry()["status"]).is_not_equal(StatusDef.NONE)
	# Past the three seconds it thaws and goes for the player.
	NightFixture.run(_night, THAW_TICKS - 150)
	assert_array(_of(&"status_ended")).has_size(1)
	assert_int(_entry()["status"]).is_equal(StatusDef.NONE)
	assert_int(_night.view.horde.view_of(_zombie).status()).is_equal(StatusDef.NONE)
	NightFixture.run(_night, 90)
	assert_float(_body().position.distance_to(held)).is_greater(1.0)


func test_a_frozen_zombie_beside_the_player_does_not_attack() -> void:
	_place(1.0)
	# The shot: the player is at arm's length, so the zombie has already swung at them by now; what
	# matters is what comes after the freeze.
	_shoot()
	_body().speed = 2.0
	var health := _night.server.health_of(1)
	NightFixture.run(_night, 150)
	assert_array(_of(&"player_damaged")).is_empty()
	assert_float(_night.server.health_of(1)).is_equal(health)
	assert_int(_body().mode).is_not_equal(ZombieBody.Mode.ATTACK)


func test_any_hit_on_a_frozen_zombie_kills_it_and_it_shatters_on_the_server_and_the_client(
) -> void:
	_place(AHEAD)
	_shoot()
	_let_the_gun_cool()
	_night.server.combat.apply(CombatAction.equip(1, &"house_pistol"))
	NightFixture.run(_night, 40)
	_shoot(false)
	# The server: it is dead at once, removed whole, no corpse falling.
	assert_bool(_night.server.sim.zombies.has(_zombie)).is_false()
	assert_bool(_night.server.rules.has_zombie(_zombie)).is_false()
	var removed := _of(&"zombie_removed")
	assert_array(removed).has_size(1)
	assert_bool(removed[0]["shattered"]).is_true()
	assert_array(_of(&"zombie_shattered")).has_size(1)
	assert_int(_of(&"zombie_shattered")[0]["zombie_id"]).is_equal(_zombie)
	# The client: the pieces fly, and the zombie's body is gone.
	assert_int(_night.view.effects.shards.live_count()).is_greater(0)
	assert_object(_night.view.horde.view_of(_zombie)).is_null()
	(
		assert_array(
			_night.state.zombies.filter(func(e: Dictionary) -> bool: return e["id"] == _zombie)
		)
		. is_empty()
	)
	# It is not a body lying on the ground (a dying zombie is drawn for a while): nothing is left.
	(
		assert_array(
			_of(&"damage_dealt").filter(func(e: Dictionary) -> bool: return e["shattered"])
		)
		. has_size(1)
	)


func test_a_zombie_that_is_not_frozen_falls_and_is_not_shattered() -> void:
	_place(AHEAD)
	_night.server.combat.apply(CombatAction.equip(1, &"house_pistol"))
	_night.server.rules.apply(RulesAction.hit(1, _zombie, &"body", RulesFixture.KILLING_DAMAGE))
	NightFixture.run(_night, 3)
	assert_array(_of(&"zombie_shattered")).is_empty()
	assert_bool(_night.server.sim.zombies.has(_zombie)).is_true()
	assert_int(_body().mode).is_equal(ZombieBody.Mode.DYING)


func test_a_grenade_blast_on_a_frozen_zombie_shatters_it() -> void:
	_place(AHEAD)
	_shoot()
	var broken: Array[Dictionary] = []
	_night.server.director.zombie_shattered.connect(func(e: Dictionary) -> void: broken.append(e))
	# The rules' own answer to a grenade's blast on it (the grenade's flight is `GrenadeServer`'s).
	_night.server.rules.apply(
		RulesAction.explosion(1, [{"zombie_id": _zombie, "damage": 1.0, "leg_damage": 0.0}])
	)
	assert_array(broken).has_size(1)
	assert_int(broken[0]["zombie_id"]).is_equal(_zombie)
	assert_bool(_night.server.sim.zombies.has(_zombie)).is_false()
	assert_bool(_night.server.rules.has_zombie(_zombie)).is_false()


func test_the_ray_guns_bolt_flies_bursts_and_is_drawn_in_blue() -> void:
	_night.server.combat.apply(CombatAction.give_weapon(1, &"ray_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"ray_gun"))
	NightFixture.run(_night, 3)
	_place(AHEAD)
	_shoot()
	var spawned := _of(&"projectile_spawned")
	assert_array(spawned).has_size(1)
	assert_str(String(spawned[0]["weapon_id"])).is_equal("ray_gun")
	# The copy in the air is the bolt in the ray gun's own colours, not the flare's.
	var def := WeaponCatalog.get_def(&"ray_gun")
	assert_bool(def.bolt_halo_colour.b > def.bolt_halo_colour.r).is_true()
	var ticks := 0
	while _of(&"projectile_burst").is_empty() and ticks < FLIGHT_LIMIT:
		NightFixture.run(_night, 1)
		ticks += 1
	assert_array(_of(&"projectile_burst")).has_size(1)
	assert_int(_night.view.projectiles_in_flight()).is_equal(0)
	assert_int(_night.view.effects.bolt_bursts.live_count()).is_equal(1)
	assert_array(_of(&"damage_dealt")).is_not_empty()


func test_the_ray_gun_hurts_its_shooter_by_a_quarter_of_the_splash_at_their_distance() -> void:
	_night.server.combat.apply(CombatAction.give_weapon(1, &"ray_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"ray_gun"))
	NightFixture.run(_night, 3)
	_place(2.4)
	var health := _night.server.health_of(1)
	_shoot()
	var burst: Dictionary = _of(&"projectile_burst")[0]
	var def := WeaponCatalog.get_def(&"ray_gun")
	var chest := _night.server.body_of(1).global_position + Vector3(0.0, 1.0, 0.0)
	var expected := (
		DamageModel.splash(def, chest.distance_to(burst["point"])) * def.self_splash_share
	)
	assert_float(expected).is_greater(0.0)
	assert_float(health - _night.server.health_of(1)).is_equal_approx(expected, 0.5)
	assert_array(_of(&"player_hurt")).is_not_empty()


func test_a_burst_far_from_the_shooter_does_not_hurt_them() -> void:
	_night.server.combat.apply(CombatAction.give_weapon(1, &"ray_gun"))
	_night.server.combat.apply(CombatAction.equip(1, &"ray_gun"))
	NightFixture.run(_night, 3)
	_place(AHEAD)
	var health := _night.server.health_of(1)
	_shoot()
	assert_float(_night.server.health_of(1)).is_equal(health)


func test_the_freeze_guns_burst_does_not_hurt_its_shooter() -> void:
	_place(2.4)
	var health := _night.server.health_of(1)
	_shoot()
	assert_float(_night.server.health_of(1)).is_equal(health)
