extends GdUnitTestSuite
## The re-cut plan of #785 (docs/design/upgrades.md, "What each weapon becomes") against the
## shipped table: every weapon the plan re-cuts has a profile that makes the plan's numbers, the
## melee weapons have none, and a weapon with a profile is re-cut the way the table says wherever
## it is made (the weapon state, the combat server, the simulator all call `WeaponDef.upgraded`).

## The plan, one row per weapon: the plain numbers the design page gives the weapon (damage per
## pellet, pellets, magazine, reserve at the start, reserve limit, blast), then what its re-cut
## makes of them: hit, magazine, reserve at the start, reserve limit, blast, fire interval (0:
## unchanged) and the element's id (empty for none). The nine new weapons are not in the catalogue
## until their own pull requests land, so the plain numbers are here and the row is checked
## against them; a weapon that is in the catalogue is checked against its own file as well.
const PLAN := {
	&"pistol": [24.0, 1, 10, 40, 80, 0.0, 42.0, 15, 60, 120, 0.0, 0.40, &"explosive"],
	&"smg": [14.0, 1, 30, 120, 180, 0.0, 24.5, 45, 180, 270, 0.0, 0.0, &""],
	&"shotgun": [22.0, 8, 2, 16, 32, 0.0, 38.5, 3, 24, 48, 0.0, 0.0, &""],
	&"rifle": [95.0, 1, 8, 40, 80, 0.0, 166.25, 12, 60, 120, 0.0, 0.0, &""],
	&"flare_gun": [0.0, 1, 1, 2, 2, 0.0, 0.0, 2, 4, 4, 0.0, 0.0, &"ground_fire"],
	&"mp5": [15.0, 1, 30, 120, 180, 0.0, 26.25, 45, 180, 270, 0.0, 0.0, &""],
	&"ppsh": [10.0, 1, 50, 100, 200, 0.0, 17.5, 75, 150, 300, 0.0, 0.0, &""],
	&"m4a1": [20.0, 1, 30, 90, 150, 0.0, 35.0, 45, 135, 225, 0.0, 0.0, &""],
	&"m249": [15.0, 1, 100, 150, 250, 0.0, 26.25, 150, 225, 375, 0.0, 0.0, &""],
	&"fifty_cal": [220.0, 1, 5, 20, 40, 0.0, 385.0, 8, 30, 60, 0.0, 0.0, &""],
	&"pump_870": [22.0, 6, 6, 42, 66, 0.0, 38.5, 9, 63, 99, 0.0, 0.0, &"fire"],
	&"dual_pistols": [17.0, 1, 24, 72, 120, 0.0, 29.75, 36, 108, 180, 0.0, 0.0, &"shock"],
	&"ray_gun": [300.0, 1, 10, 40, 60, 160.0, 525.0, 15, 60, 90, 280.0, 0.0, &""],
	&"freeze_gun": [30.0, 1, 6, 24, 36, 0.0, 52.5, 9, 36, 54, 0.0, 0.0, &""],
}
## What the plan leaves without a re-cut: nothing to put rounds in.
const NOT_RE_CUT: Array[StringName] = [&"crowbar", &"baseball_bat", &"fire_axe"]

var _spec := UpgradeTuning.shipped()


func _plain(id: StringName) -> WeaponDef:
	if WeaponCatalog.IDS.has(id):
		return WeaponCatalog.get_def(id)
	var row: Array = PLAN[id]
	var def := WeaponDef.new()
	def.id = id
	def.display_name = String(id)
	def.damage = row[0]
	def.pellets = row[1]
	def.magazine_size = row[2]
	def.reserve_start = row[3]
	def.reserve_max = row[4]
	def.splash_damage = row[5]
	return def


func test_the_table_has_a_profile_for_each_of_the_fourteen_and_for_no_other() -> void:
	assert_int(_spec.profiles.size()).is_equal(PLAN.size())
	for id: StringName in PLAN:
		assert_bool(_spec.allows(id)).override_failure_message(String(id)).is_true()
	for id in NOT_RE_CUT:
		assert_bool(_spec.allows(id)).override_failure_message(String(id)).is_false()
	for id in _spec.weapon_ids():
		assert_bool(PLAN.has(id)).override_failure_message(String(id)).is_true()


func test_each_profile_makes_the_numbers_of_the_plan() -> void:
	for id: StringName in PLAN:
		var row: Array = PLAN[id]
		var tuned := _plain(id).upgraded(_spec)
		var named := String(id)
		assert_float(tuned.damage).override_failure_message(named + " hit").is_equal_approx(
			row[6], 0.005
		)
		assert_int(tuned.magazine_size).override_failure_message(named + " magazine").is_equal(
			row[7]
		)
		assert_int(tuned.reserve_start).override_failure_message(named + " reserve").is_equal(
			row[8]
		)
		assert_int(tuned.reserve_max).override_failure_message(named + " limit").is_equal(row[9])
		(
			assert_float(tuned.splash_damage)
			. override_failure_message(named + " blast")
			. is_equal_approx(row[10], 0.005)
		)
		var interval: float = row[11]
		if interval > 0.0:
			assert_float(tuned.fire_interval).override_failure_message(named + " rate").is_equal(
				interval
			)
		else:
			assert_float(tuned.fire_interval).is_equal(_plain(id).fire_interval)
		var element: StringName = row[12]
		var shown := tuned.element.id if tuned.element != null else &""
		assert_str(shown).override_failure_message(named + " element").is_equal(element)


func test_a_weapon_in_the_catalogue_is_the_plans_plain_weapon() -> void:
	# The plan's plain numbers are the design page's table; a definition that drifted from it would
	# make every row above a different weapon's.
	for id: StringName in PLAN:
		if not WeaponCatalog.IDS.has(id):
			continue
		var row: Array = PLAN[id]
		var def := WeaponCatalog.get_def(id)
		var named := String(id)
		assert_float(def.damage).override_failure_message(named).is_equal(row[0])
		assert_int(def.pellets).override_failure_message(named).is_equal(row[1])
		assert_int(def.magazine_size).override_failure_message(named).is_equal(row[2])
		assert_int(def.reserve_start).override_failure_message(named).is_equal(row[3])
		assert_int(def.reserve_max).override_failure_message(named).is_equal(row[4])


func test_every_firearm_of_the_catalogue_can_be_re_cut_and_no_blade_can() -> void:
	for id in WeaponCatalog.IDS:
		var def := WeaponCatalog.get_def(id)
		assert_bool(_spec.allows(id)).override_failure_message(String(id)).is_equal(
			not def.is_melee()
		)


func test_the_flare_gun_holds_three_shots_and_six_re_cut() -> void:
	var plain := WeaponCatalog.get_def(&"flare_gun")
	assert_int(plain.magazine_size + plain.reserve_max).is_equal(3)
	assert_int(plain.reserve_start).is_equal(plain.reserve_max)
	var tuned := plain.upgraded(_spec)
	assert_int(tuned.magazine_size + tuned.reserve_max).is_equal(6)
	# It still hurts no one: the re-cut's gain is the fire it leaves.
	assert_float(tuned.damage).is_equal(0.0)
	assert_bool(tuned.element.has_ground()).is_true()


func test_a_re_cut_name_is_a_string_of_the_profile_or_the_prefix_and_the_name() -> void:
	for id: StringName in PLAN:
		var cut := _spec.profile_of(id)
		var plain := _plain(id)
		var tuned := plain.upgraded(_spec)
		if cut.recut_name != "":
			assert_str(tuned.display_name).is_equal(cut.recut_name)
		else:
			assert_str(tuned.display_name).is_equal(_spec.name_prefix + plain.display_name)
		assert_str(tuned.display_name).is_not_equal(plain.display_name)
	for id in [&"pistol", &"smg", &"shotgun", &"rifle", &"flare_gun"]:
		(
			assert_str(_spec.profile_of(id).recut_name)
			. override_failure_message(String(id))
			. is_not_empty()
		)


func test_the_revolver_fires_slower_once_re_cut_and_nothing_else_changes_its_rate() -> void:
	var state := WeaponState.new(WeaponCatalog.get_def(&"pistol"))
	state.upgrade(_spec)
	assert_float(state.def.fire_interval).is_equal(0.40)
	state.fire()
	assert_float(state.cooldown).is_equal_approx(0.40, 0.001)
	for id in [&"smg", &"shotgun", &"rifle", &"flare_gun"]:
		var plain := WeaponCatalog.get_def(id)
		assert_float(plain.upgraded(_spec).fire_interval).is_equal(plain.fire_interval)
		assert_float(plain.upgraded(_spec).reload_time).is_equal(plain.reload_time)


func test_the_re_cut_of_a_weapon_is_a_copy_and_the_file_stays_plain() -> void:
	var plain := WeaponCatalog.get_def(&"pistol")
	plain.upgraded(_spec)
	assert_int(plain.tier).is_equal(0)
	assert_float(plain.fire_interval).is_equal(0.28)
	assert_bool(plain.has_element()).is_false()
	assert_float(plain.splash_damage).is_equal(0.0)


func test_a_weapon_that_is_re_cut_is_worth_more_by_its_new_numbers() -> void:
	# What a bot or the simulator reads: the sustained damage of the re-cut definition.
	var health := RulesFixture.round_health(15)
	for id in [&"pistol", &"smg", &"shotgun", &"rifle"]:
		var plain := WeaponCatalog.get_def(id)
		(
			assert_float(WeaponWorth.of(plain.upgraded(_spec), health))
			. override_failure_message(String(id))
			. is_greater(WeaponWorth.of(plain, health))
		)


func test_the_fire_of_the_pump_re_cut_is_worth_what_it_finishes_and_nothing_else_is_worth_more(
) -> void:
	# The bots and the simulator rate the re-cut pump with its burn: the fire finishes what a shell
	# leaves standing, so against a round-15 zombie (282) one pull and its 90 of burn kill where the
	# shell alone (231) leaves 51 standing.
	var health := RulesFixture.round_health(15)
	var pump := WeaponCatalog.get_def(&"pump_870").upgraded(_spec)
	var bare := pump.duplicate() as WeaponDef
	bare.element = null
	assert_float(WeaponWorth.burn_total(pump)).is_equal(90.0)
	assert_float(WeaponWorth.of(pump, health)).is_greater(WeaponWorth.of(bare, health) * 1.5)
	# Without a health (the sustained damage at point blank) the burn counts only for the seconds
	# before the next pull restarts it: 30 a second for the 0.65 s between pulls.
	var extra := WeaponWorth.of(pump) - WeaponWorth.of(bare)
	var cycle := float(pump.magazine_size) * pump.fire_interval + pump.reload_time
	assert_float(extra).is_equal_approx(
		30.0 * pump.fire_interval * pump.magazine_size / cycle, 0.01
	)
	# No other weapon is rated for a burn it does not have.
	for id in [&"pistol", &"dual_pistols", &"flare_gun", &"freeze_gun"]:
		var other := WeaponCatalog.get_def(id).upgraded(_spec)
		assert_float(WeaponWorth.burn_total(other)).override_failure_message(String(id)).is_zero()
		assert_float(WeaponWorth.burn_between_pulls(other)).is_zero()
