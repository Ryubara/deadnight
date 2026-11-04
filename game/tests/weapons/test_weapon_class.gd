extends GdUnitTestSuite
## What a weapon is and where it can be had, on its definition (#972): the class, the wall tier and
## the crane's weight moved off three tables (`WallTier.TIERS`, the two tunings' `pool_weights`)
## onto `defs/<id>.tres`, with no number changed. The literals below are the old tables, kept so the
## move is checked against what it replaced.

## (The crowbar, the bat and the axe were tier 1 here; since #910 they are box only: no wall
## sells a melee weapon.)
const OLD_WALL_TIERS := {
	&"house_pistol": 1,
	&"pistol": 1,
	&"flare_gun": 1,
	&"shotgun": 2,
	&"smg": 2,
	&"rifle": 2,
}
## The crane's pool as it was shipped: the weapons in the order of the draw, each with its weight.
const OLD_CRANE := [
	[&"weapon_shotgun", 4.0],
	[&"weapon_rifle", 3.0],
	[&"weapon_smg", 2.0],
	[&"weapon_flare_gun", 1.0],
	[&"weapon_baseball_bat", 0.5],
	[&"weapon_fire_axe", 0.5],
	[&"weapon_pistol", 1.0],
	[&"weapon_crowbar", 1.0],
	[&"weapon_pump_870", 2.0],
	[&"weapon_mp5", 2.0],
	[&"weapon_m4a1", 1.5],
	[&"weapon_ppsh", 2.0],
	[&"weapon_m249", 1.5],
	[&"weapon_fifty_cal", 1.5],
	[&"weapon_dual_pistols", 0.5],
	[&"weapon_ray_gun", 1.5],
	[&"weapon_freeze_gun", 1.5],
]
const SMALLMAP_TUNING := "res://world/smallmap/smallmap_tuning.tres"


func test_every_weapon_has_a_class_and_the_melee_class_is_the_melee_kind() -> void:
	var ids: Array[StringName] = WeaponCatalog.IDS.duplicate()
	ids.append(WeaponCatalog.QUICK_MELEE)
	for id in ids:
		var def := WeaponCatalog.get_def(id)
		assert_bool(def.weapon_class in WeaponClass.all()).override_failure_message(id).is_true()
		(
			assert_bool(def.weapon_class == WeaponClass.Id.MELEE)
			. override_failure_message("%s: the melee class is the melee kind, and only it" % id)
			. is_equal(def.is_melee())
		)


func test_every_class_has_a_weapon_and_a_name() -> void:
	for class_id in WeaponClass.all():
		assert_str(WeaponClass.title(class_id)).is_not_empty()
		assert_int(WeaponClass.from_key(WeaponClass.key(class_id))).is_equal(class_id)
		var members := WeaponCatalog.all().filter(
			func(def: WeaponDef) -> bool: return def.weapon_class == class_id
		)
		(
			assert_bool(members.size() > 0)
			. override_failure_message("no weapon is of the class %s" % WeaponClass.title(class_id))
			. is_true()
		)


func test_the_wall_tiers_are_the_old_table_and_the_rest_are_the_box() -> void:
	for id in WeaponCatalog.IDS:
		var want: int = OLD_WALL_TIERS.get(id, WallTier.BOX)
		assert_int(WallTier.tier_of(id)).override_failure_message(id).is_equal(want)
		assert_int(WallTier.tier_of(StringName("weapon_" + id))).is_equal(want)
	assert_int(WallTier.tier_of(&"no_such_weapon")).is_equal(WallTier.BOX)


func test_the_crane_draws_by_the_old_weights_on_both_maps() -> void:
	var small := (load(SMALLMAP_TUNING) as MapTuning).apply(RulesFixture.tuning())
	for tuning: RulesTuning in [RulesFixture.tuning(), small]:
		var item := tuning.economy.item(&"crane_play")
		assert_array(item.pool_weights).is_empty()
		assert_int(item.pool.size()).is_equal(OLD_CRANE.size())
		for i in OLD_CRANE.size():
			assert_str(String(item.pool[i])).is_equal(String(OLD_CRANE[i][0]))
			assert_float(item.weights()[i]).override_failure_message(item.pool[i]).is_equal(
				OLD_CRANE[i][1]
			)


func test_a_pool_with_its_own_weights_keeps_them() -> void:
	var item := ShopItem.new()
	item.pool = [&"weapon_rifle", &"weapon_smg"]
	item.pool_weights = PackedFloat32Array([7.0, 9.0])
	assert_float(item.weight_of(&"weapon_rifle")).is_equal(7.0)
	assert_float(item.weight_of(&"weapon_smg")).is_equal(9.0)
	item.pool_weights = PackedFloat32Array()
	assert_float(item.weight_of(&"weapon_rifle")).is_equal(3.0)
	assert_float(item.weight_of(&"weapon_not_a_gun")).is_equal(1.0)
