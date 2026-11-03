# What the bots know of the two wonder weapons (#788): a frozen zombie is a contact with a status
# (the frame carries it), one shot kills it so a bot shoots it once and not in a burst, and
# `WeaponWorth` rates a weapon whose hit freezes by the two pulls it takes to kill. Pure data on a
# `BotRig`: a tick is a step of the night and nothing waits on the clock.
extends GdUnitTestSuite

## Ticks the rig runs a zombie in front of the bot, long enough for the aim to settle and for a
## burst to have been fired (an automatic weapon's is three to five shots).
const WATCH := 120


func _frozen() -> int:
	return StatusCatalog.get_def(&"frozen").wire


func _rig(weapon: StringName) -> BotRig:
	var rig := BotRig.new(BotProfile.regular(), 7)
	rig.weapon = weapon
	rig.run(5)
	return rig


## A zombie 10 m ahead of the bot's view, frozen or not, watched for `WATCH` ticks: how many shots
## the bot fired at it.
func _shots_at(weapon: StringName, frozen: bool) -> int:
	var rig := _rig(weapon)
	var zombie := rig.put_zombie(
		1, Vector3(-sin(rig.bot.motor.yaw), 0.0, -cos(rig.bot.motor.yaw)) * 10.0
	)
	if frozen:
		zombie.status = _frozen()
	rig.run(WATCH)
	return rig.shot_ticks.size()


func test_a_frozen_zombie_is_a_contact_with_a_status() -> void:
	var rig := _rig(&"pistol")
	var zombie := rig.put_zombie(1, Vector3(0, 0, -8))
	zombie.status = _frozen()
	rig.run(30)
	var contact: Dictionary = rig.bot.perception.beliefs.contact(1)
	assert_int(contact.get("status", 0)).is_equal(_frozen())
	assert_bool(BotMotor.is_shatterable(contact)).is_true()
	zombie.status = StatusDef.NONE
	rig.run(5)
	assert_bool(BotMotor.is_shatterable(rig.bot.perception.beliefs.contact(1))).is_false()


func test_a_chilled_zombie_is_not_a_one_shot_kill() -> void:
	(
		assert_bool(BotMotor.is_shatterable({"status": StatusCatalog.get_def(&"chilled").wire}))
		. is_false()
	)
	assert_bool(BotMotor.is_shatterable({})).is_false()


func test_a_bot_with_an_automatic_gun_shoots_a_frozen_zombie_once_and_a_live_one_in_a_burst(
) -> void:
	var at_a_live_one := _shots_at(&"smg", false)
	var at_a_frozen_one := _shots_at(&"smg", true)
	assert_int(at_a_live_one).is_greater_equal(BotMotor.BURST_MIN)
	# Once, and again only after the wait for the first shot to have killed it.
	var allowed := ceili(float(WATCH) * BotRig.STEP / BotMotor.FROZEN_WAIT) + 1
	assert_int(at_a_frozen_one).is_greater_equal(1)
	assert_int(at_a_frozen_one).is_less_equal(allowed)
	assert_int(at_a_frozen_one).is_less(at_a_live_one)


func test_a_frozen_zombie_is_shot_again_when_the_first_shot_did_not_kill_it() -> void:
	var rig := _rig(&"pistol")
	var zombie := rig.put_zombie(
		1, Vector3(-sin(rig.bot.motor.yaw), 0.0, -cos(rig.bot.motor.yaw)) * 10.0
	)
	zombie.status = _frozen()
	rig.run(int(ceil(BotMotor.FROZEN_WAIT / BotRig.STEP)) * 3)
	# The rig never kills it: after each wait the bot tries again, so a miss costs half a second.
	assert_int(rig.shot_ticks.size()).is_greater_equal(2)


func test_the_catalogue_weapons_are_all_in_the_bots_coverage_table() -> void:
	for id in [&"ray_gun", &"freeze_gun"]:
		assert_bool(BotCoverage.WEAPONS.has(String(id))).is_true()


# --- What a weapon is worth ---


func test_a_weapon_whose_hit_freezes_kills_in_two_pulls_at_most() -> void:
	var freeze := WeaponCatalog.get_def(&"freeze_gun")
	assert_bool(WeaponWorth.shatters(freeze)).is_true()
	assert_bool(WeaponWorth.shatters(WeaponCatalog.get_def(&"ray_gun"))).is_false()
	assert_bool(WeaponWorth.shatters(WeaponCatalog.get_def(&"pistol"))).is_false()
	# Against 600 health its 30 damage would take twenty pulls; the freeze makes it two.
	var cycle := float(freeze.magazine_size) * freeze.fire_interval + freeze.reload_time
	var expected := 600.0 * float(freeze.magazine_size) / 2.0 / cycle
	assert_float(WeaponWorth.sustained_dps(freeze, 600.0)).is_equal_approx(expected, 0.01)
	# Against nothing named it is rated by half of a round-ten walker per pull.
	assert_float(WeaponWorth.of(freeze)).is_equal_approx(
		WeaponWorth.SHATTER_HEALTH / 2.0 * float(freeze.magazine_size) / cycle, 0.01
	)


func test_the_freeze_gun_is_worth_more_than_its_raw_damage_says() -> void:
	var freeze := WeaponCatalog.get_def(&"freeze_gun")
	var plain := freeze.duplicate() as WeaponDef
	plain.status = &""
	assert_float(WeaponWorth.of(freeze, 400.0)).is_greater(WeaponWorth.of(plain, 400.0))
	assert_float(WeaponWorth.of(freeze)).is_greater(WeaponWorth.of(plain))
	# A zombie it kills in one pull does not need the second.
	assert_float(WeaponWorth.sustained_dps(freeze, 20.0)).is_equal_approx(
		WeaponWorth.sustained_dps(plain, 20.0), 0.01
	)
