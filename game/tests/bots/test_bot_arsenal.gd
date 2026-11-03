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


func test_an_empty_gun_is_swapped_for_one_with_rounds_in_reserve_only() -> void:
	# The soak found a bot in a boss fight with an empty shotgun and 24 rifle rounds in reserve.
	var arms := {&"shotgun": [0, 0], &"rifle": [0, 24]}
	var plan := _plan(_me(&"shotgun", arms), 20.0, 20.0)
	assert_bool(plan.swap).is_true()
	assert_bool(plan.reload).is_false()
	# In hand, the rifle is reloaded; nothing left to swap to.
	plan = _plan(_me(&"rifle", {&"shotgun": [0, 0], &"rifle": [0, 24]}), 20.0, 20.0)
	assert_bool(plan.reload).is_true()
	assert_bool(plan.swap).is_false()
	# Both empty to the last round: nothing to swap to.
	var dry := {&"shotgun": [0, 0], &"rifle": [0, 0]}
	assert_bool(_plan(_me(&"shotgun", dry), 20.0, 20.0).swap).is_false()


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


func test_the_flare_gun_in_hand_is_put_away_for_a_loaded_gun_and_is_never_swapped_to() -> void:
	var arms := {&"pistol": [6, 20], &"flare_gun": [1, 6]}
	var plan := _plan(_me(&"flare_gun", arms))
	assert_bool(plan.swap).is_true()
	assert_bool(plan.reload).is_false()
	# A bot with a pistol in hand does not take the flare gun in the fight, loaded or not.
	assert_bool(_plan(_me(&"pistol", arms), 6.0, 6.0).swap).is_false()
	assert_bool(_plan(_me(&"pistol", arms), INF, 20.0).swap).is_false()


func test_the_flare_gun_is_no_firearm_for_the_fight_so_a_bot_with_only_it_is_dry() -> void:
	var spent := {&"pistol": [0, 0], &"flare_gun": [0, 6]}
	var plan := _plan(_me(&"flare_gun", spent))
	# Its round is spent and nothing else shoots: it reloads the flare (the one thing it can do)
	# and counts as dry, so the quick melee is its fight.
	assert_bool(plan.reload).is_true()
	assert_bool(plan.swap).is_false()
	assert_bool(plan.dry).is_true()
	var loaded := {&"pistol": [0, 0], &"flare_gun": [1, 6]}
	assert_bool(_plan(_me(&"flare_gun", loaded)).dry).is_true()


# --- A gun with nothing left at all (#695) ---


func test_an_empty_gun_with_no_reserve_is_swapped_for_a_gun_that_has_only_reserve() -> void:
	# The shotgun has no round anywhere and the Tommy gun an empty magazine with 158 in reserve:
	# neither is loaded, so the old plan held the empty shotgun for good (no reload, no swap, and
	# `dry` false because rounds exist, so no quick melee either).
	var arms := {&"shotgun": [0, 0], &"smg": [0, 158]}
	for threat: float in [INF, 20.0, 8.0, 3.0]:
		var plan := _plan(_me(&"shotgun", arms), threat, threat)
		assert_bool(plan.swap).override_failure_message("no swap at %s" % threat).is_true()
		assert_bool(plan.reload).is_false()


func test_the_gun_taken_up_for_its_reserve_is_reloaded_not_swapped_back() -> void:
	var arms := {&"shotgun": [0, 0], &"smg": [0, 158]}
	for threat: float in [INF, 20.0, 3.0]:
		var plan := _plan(_me(&"smg", arms), threat, threat)
		assert_bool(plan.reload).is_true()
		assert_bool(plan.swap).is_false()


func test_a_bot_with_nothing_loaded_may_strike_with_the_quick_melee_while_the_reload_comes(
) -> void:
	var arms := {&"shotgun": [0, 0], &"smg": [0, 158]}
	var plan := _plan(_me(&"smg", arms), 2.0, 2.0)
	assert_bool(plan.dry).is_false()
	assert_bool(plan.unloaded).is_true()
	(
		assert_bool(_plan(_me(&"smg", {&"shotgun": [4, 10], &"smg": [0, 158]}), 2.0, 2.0).unloaded)
		. is_false()
	)
	(
		assert_bool(_plan(_me(&"smg", {&"shotgun": [0, 0], &"smg": [3, 158]}), 2.0, 2.0).unloaded)
		. is_false()
	)


func test_every_state_of_two_guns_asks_for_something_when_the_gun_in_hand_is_empty() -> void:
	# The whole product: the gun in hand and the other gun each with a magazine or none and a
	# reserve or none, near and far. An empty hand with rounds anywhere reloads or swaps; with no
	# round anywhere the bot is dry (the quick melee is all it has).
	var counts := [0, 7]
	for held_reserve: int in counts:
		for other_magazine: int in counts:
			for other_reserve: int in counts:
				for threat: float in [INF, 20.0, 8.0, 3.0]:
					var arms := {
						&"shotgun": [0, held_reserve], &"smg": [other_magazine, other_reserve]
					}
					var plan := _plan(_me(&"shotgun", arms), threat, threat)
					var name := (
						"held 0/%d, other %d/%d, threat %s"
						% [held_reserve, other_magazine, other_reserve, threat]
					)
					if held_reserve + other_magazine + other_reserve > 0:
						(
							assert_bool(plan.reload or plan.swap)
							. override_failure_message(name)
							. is_true()
						)
						assert_bool(plan.dry).override_failure_message(name).is_false()
					else:
						assert_bool(plan.dry).override_failure_message(name).is_true()


func test_a_blade_with_no_gun_loaded_strikes_when_the_dead_are_near_else_goes_back_to_reload(
) -> void:
	# The axe in hand, the shotgun with 54 in reserve and an empty magazine: with a train at its
	# heels the bot held the axe it was not allowed to swing into a pack and never took the gun
	# back (#695).
	var arms := {&"shotgun": [0, 54], &"fire_axe": [0, 0]}
	var close := _plan(_me(&"fire_axe", arms), 1.0, 1.0)
	assert_bool(close.cornered).is_true()
	assert_bool(close.swap).is_false()
	var near := _plan(_me(&"fire_axe", arms), 5.0, 5.0)
	assert_bool(near.cornered).is_true()
	assert_bool(near.swap).is_false()
	var far := _plan(_me(&"fire_axe", arms), 9.0, 9.0)
	assert_bool(far.cornered).is_false()
	assert_bool(far.swap).is_true()


func test_a_blade_with_a_loaded_gun_to_take_is_not_cornered_and_a_gun_in_hand_never_is() -> void:
	var loaded := {&"shotgun": [4, 10], &"fire_axe": [0, 0]}
	var plan := _plan(_me(&"fire_axe", loaded), 1.0, 1.0)
	assert_bool(plan.cornered).is_false()
	assert_bool(plan.swap).is_true()
	var empty_gun := {&"shotgun": [0, 54], &"fire_axe": [0, 0]}
	assert_bool(_plan(_me(&"shotgun", empty_gun), 1.0, 1.0).cornered).is_false()
