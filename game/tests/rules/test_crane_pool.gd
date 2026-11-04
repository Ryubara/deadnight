extends GdUnitTestSuite
## What the prize crane can give, and how it first rolls (#685). #461 put every weapon in the pool
## and tested the draws from consecutive seeds (0, 1, 2 ...), but a solo night always started from
## `Night.SEED`, so a person's crane rolled the same prizes in the same order every night: the
## shotgun first, always, and the bat, the axe and the crowbar never in the first plays.

## Weapons of the catalogue the crane does not give, each with the reason. Empty: every weapon is a
## prize, the revolver too (the crane skips it only for a buyer who carries it). A weapon added to
## `WeaponCatalog.IDS` is in the crane's pool, or is listed here with why not.
const NOT_PRIZES := {}
## First rolls drawn, each with its own fresh seed.
const FIRST_ROLLS := 10000
## How far a prize's share of the first rolls may be from its weight's share. The largest share
## (a third) has a standard deviation of 0.0047 over 10,000 rolls, so this is 5 of them: a fair
## draw stays inside it for ten million runs in a row.
const TOLERANCE := 0.025


func _pool(tuning: RulesTuning) -> ShopItem:
	return tuning.economy.item(&"crane_play")


func test_every_weapon_but_the_listed_ones_is_in_the_pool() -> void:
	var item := _pool(RulesFixture.tuning())
	var in_pool: Array[StringName] = []
	for prize in item.pool:
		in_pool.append(WeaponCatalog.catalog_id(prize))
	for id in WeaponCatalog.IDS:
		if NOT_PRIZES.has(id):
			continue
		(
			assert_bool(id in in_pool)
			. override_failure_message(
				(
					"%s is a weapon but not in the crane's pool; add it, or list it in NOT_PRIZES with a reason"
					% id
				)
			)
			. is_true()
		)


func test_the_listed_exceptions_are_weapons_with_a_reason() -> void:
	var item := _pool(RulesFixture.tuning())
	for id: StringName in NOT_PRIZES:
		(
			assert_bool(id in WeaponCatalog.IDS)
			. override_failure_message("%s is listed as no prize but is not a weapon" % id)
			. is_true()
		)
		assert_str(NOT_PRIZES[id]).is_not_empty()
		(
			assert_bool(item.pool.has(StringName(WeaponCatalog.SHOP_PREFIX + id)))
			. override_failure_message("%s is listed as no prize but is in the pool" % id)
			. is_false()
		)


func test_the_pool_has_only_weapons_once_each_with_a_weight() -> void:
	var item := _pool(RulesFixture.tuning())
	assert_int(item.weights().size()).is_equal(item.pool.size())
	var seen := {}
	for i in item.pool.size():
		var id := WeaponCatalog.catalog_id(item.pool[i])
		(
			assert_bool(id in WeaponCatalog.IDS)
			. override_failure_message("%s is in the pool but not in the catalogue" % item.pool[i])
			. is_true()
		)
		(
			assert_bool(seen.has(id))
			. override_failure_message("%s is in the pool twice" % id)
			. is_false()
		)
		seen[id] = true
		assert_float(item.weights()[i]).is_greater(0.0)


func test_solo_nights_start_from_a_fresh_seed_each() -> void:
	var seeds := {}
	for _i in 1000:
		seeds[NightScreen.solo_seed()] = true
	# A fixed seed would give one entry; a fresh draw of 32 bits gives 1000 (1 in 10^4 to repeat).
	assert_int(seeds.size()).is_greater(990)
	assert_bool(seeds.has(Night.SEED)).is_false()


func test_a_bench_can_ask_for_one_seed() -> void:
	NightScreen.start_seed = 77
	var first := NightScreen.solo_seed()
	var second := NightScreen.solo_seed()
	NightScreen.start_seed = -1
	assert_int(first).is_equal(77)
	assert_int(second).is_equal(77)


func test_the_first_roll_of_a_solo_night_follows_the_weights() -> void:
	# A person's first play: they carry the start weapons (the revolver), the seed is the one a solo
	# night would take, and the crane does not break down (the odds of that are another test).
	var tuning := RulesFixture.steady_crane_tuning()
	var item := _pool(tuning)
	var held: Array[StringName] = tuning.economy.start_weapons
	var offered := item.pool_without(held)
	var total := 0.0
	for prize in offered:
		total += item.weight_of(prize)
	var counts := {}
	for _i in FIRST_ROLLS:
		var rules := RulesFixture.make_rules(1, NightScreen.solo_seed(), tuning)
		rules.apply(RulesAction.start())
		rules.apply(RulesAction.grant_points(1, 5000))
		rules.apply(RulesAction.buy(1, &"crane_play"))
		# Whole seconds (the longest tick the rules take) past the spin: the prize is chosen then.
		var caused := RulesFixture.advance(
			rules, tuning.crane.spin_seconds + 0.5, RulesAction.MAX_TICK
		)
		var ready := RulesFixture.first(caused, &"crane_prize_ready")
		assert_bool(ready.is_empty()).override_failure_message("no prize after the spin").is_false()
		counts[ready["weapon"]] = counts.get(ready["weapon"], 0) + 1
	for prize in offered:
		var want: float = item.weight_of(prize) / total
		var share: float = counts.get(prize, 0) / float(FIRST_ROLLS)
		(
			assert_float(share)
			. override_failure_message(
				(
					"%s: %.3f of %d first rolls, its weight says %.3f"
					% [prize, share, FIRST_ROLLS, want]
				)
			)
			. is_equal_approx(want, TOLERANCE)
		)
	for prize in counts:
		(
			assert_bool(offered.has(prize))
			. override_failure_message("%s was not on offer" % prize)
			. is_true()
		)
