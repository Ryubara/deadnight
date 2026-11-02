# What a bot does with the weapons it carries (bots plan, phase 3): which to hold, when to reload,
# when to put the gun away for the crowbar.
extends GdUnitTestSuite


## The frame's entry for a bot holding `held` with `arms`: `{id: [magazine, reserve]}`.
func _me(held: StringName, arms: Dictionary, reloading := false) -> Dictionary:
	var counts: Array = arms[held]
	return {
		"weapon": held,
		"ammo": counts[0],
		"reserve": counts[1],
		"reloading": reloading,
		"arms": arms,
	}


func _plan(me: Dictionary, distance := INF, threat := INF) -> BotArsenal.Plan:
	return BotArsenal.plan(me, WeaponCatalog.get_def(me["weapon"]), distance, threat)


func test_a_dry_magazine_with_reserve_is_reloaded_in_a_quiet_moment() -> void:
	var plan := _plan(_me(&"pistol", {&"pistol": [0, 30], &"crowbar": [0, 0]}), INF, 20.0)
	assert_bool(plan.reload).is_true()
	assert_bool(plan.swap).is_false()


func test_a_dry_magazine_with_a_zombie_close_is_swapped_for_the_other_gun_or_the_crowbar() -> void:
	var guns := {&"pistol": [0, 30], &"rifle": [8, 20]}
	var plan := _plan(_me(&"pistol", guns), 3.0, 3.0)
	assert_bool(plan.swap).is_true()
	assert_bool(plan.reload).is_false()
	var with_bar := {&"pistol": [0, 30], &"crowbar": [0, 0]}
	plan = _plan(_me(&"pistol", with_bar), 3.0, 3.0)
	assert_bool(plan.swap).is_true()


func test_a_gun_with_no_rounds_at_all_falls_back_to_the_crowbar() -> void:
	var plan := _plan(_me(&"pistol", {&"pistol": [0, 0], &"crowbar": [0, 0]}), 9.0, 9.0)
	assert_bool(plan.swap).is_true()
	assert_bool(plan.reload).is_false()
	assert_bool(plan.dry).is_true()


func test_the_crowbar_in_hand_is_put_down_when_a_gun_can_fire_and_not_when_none_can() -> void:
	var loaded := {&"pistol": [6, 20], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"crowbar", loaded)).swap).is_true()
	var empty := {&"pistol": [0, 0], &"crowbar": [0, 0]}
	var plan := _plan(_me(&"crowbar", empty))
	assert_bool(plan.swap).is_false()
	assert_bool(plan.dry).is_true()


func test_the_crowbar_goes_back_to_a_gun_that_needs_a_reload_only_when_nothing_is_near() -> void:
	var reserve_only := {&"pistol": [0, 20], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"crowbar", reserve_only), 5.0, 5.0).swap).is_false()
	assert_bool(_plan(_me(&"crowbar", reserve_only), INF, 20.0).swap).is_true()


func test_a_tactical_reload_waits_for_a_quiet_moment() -> void:
	var low := {&"pistol": [2, 20], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"pistol", low), 12.0, 6.0).reload).is_false()
	assert_bool(_plan(_me(&"pistol", low), 12.0, 12.0).reload).is_true()


func test_a_lull_tops_up_a_half_empty_magazine_and_a_fight_does_not() -> void:
	var half := {&"pistol": [5, 20], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"pistol", half), INF, INF).reload).is_true()
	assert_bool(_plan(_me(&"pistol", half), 12.0, 12.0).reload).is_false()
	var full := {&"pistol": [10, 20], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"pistol", full), INF, INF).reload).is_false()


func test_nothing_to_reload_with_and_nothing_while_reloading() -> void:
	var no_reserve := {&"pistol": [2, 0], &"crowbar": [0, 0]}
	assert_bool(_plan(_me(&"pistol", no_reserve), INF, INF).reload).is_false()
	var low := {&"pistol": [0, 20], &"crowbar": [0, 0]}
	var plan := _plan(_me(&"pistol", low, true), INF, INF)
	assert_bool(plan.reload).is_false()
	assert_bool(plan.swap).is_false()


func test_a_much_better_loaded_weapon_is_taken_and_not_taken_back() -> void:
	var rifle_worth := BotArsenal.worth_at(WeaponCatalog.get_def(&"rifle"), 5.0)
	var pistol_worth := BotArsenal.worth_at(WeaponCatalog.get_def(&"pistol"), 5.0)
	# The numbers this test stands on: the rifle is well over 1.4 times the pistol.
	assert_float(rifle_worth).is_greater(pistol_worth * BotArsenal.SWITCH_GAIN)
	var arms := {&"pistol": [10, 20], &"rifle": [8, 20]}
	assert_bool(_plan(_me(&"pistol", arms), 6.0, 6.0).swap).is_true()
	assert_bool(_plan(_me(&"rifle", arms), 6.0, 6.0).swap).is_false()


func test_the_weapons_are_ranked_by_the_range_of_the_fight() -> void:
	var shotgun := WeaponCatalog.get_def(&"shotgun")
	var rifle := WeaponCatalog.get_def(&"rifle")
	assert_float(BotArsenal.worth_at(shotgun, 3.0)).is_greater(BotArsenal.worth_at(shotgun, 25.0))
	# Close, the two are alike (the bot keeps what is in its hand); far away the rifle is far better.
	assert_float(BotArsenal.worth_at(shotgun, 40.0)).is_less(BotArsenal.worth_at(rifle, 40.0))
	var arms := {&"shotgun": [6, 20], &"rifle": [8, 20]}
	assert_bool(_plan(_me(&"rifle", arms), 3.0, 3.0).swap).is_false()
	assert_bool(_plan(_me(&"shotgun", arms), 3.0, 3.0).swap).is_false()
	assert_bool(_plan(_me(&"shotgun", arms), 40.0, 40.0).swap).is_true()
