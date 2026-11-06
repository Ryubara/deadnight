extends GdUnitTestSuite
## The balance simulator's shoppers pay for a crane play by the rule the hosted bots do (#1331): the
## share of the draw they would take is at least `crane_min_odds`, and a prize left on the glass
## ends their plays for the round while the weapons they carry stay the same. The rule is
## `CraneOdds`; `test_bot_crane_choice.gd` holds the bots' side of it.

const PISTOL := &"house_pistol"
const RIFLE := &"rifle"
const SHOTGUN := &"shotgun"
const SMG := &"smg"


## A one-player night at `round_number` whose player carries `carried`, nothing played.
func _night(round_number: int, carried: Array[StringName]) -> NightSim:
	var sim := NightSim.new(RulesFixture.tuning(), SimSkill.named(SimSkill.AVERAGE), 1, 7, 0.25)
	sim.rules.round_number = round_number
	var player: NightSim.SimPlayer = sim._players[1]
	player.arms.clear()
	for id in carried:
		player.arms[id] = NightSim.SimArm.of(id)
	var owned: Array[StringName] = []
	for prize in sim.rules.tuning.economy.item(&"crane_play").pool:
		if carried.has(WeaponCatalog.catalog_id(prize)):
			owned.append(prize)
	sim.rules.players[1].weapons.assign(owned)
	return sim


func _bots_share(sim: NightSim, carried: Array[StringName]) -> float:
	var view := BotEconomy.View.new()
	view.zombie_health = sim._health()
	for id in carried:
		view.arms[id] = [1, 1, 0]
	return BotEconomy.crane_odds(view, sim.rules.tuning.economy.item(&"crane_play"))


func test_the_shoppers_share_of_the_draw_is_the_bots() -> void:
	var hands: Array = [[PISTOL], [PISTOL, RIFLE], [RIFLE, SHOTGUN], [SMG, RIFLE], [PISTOL, SMG]]
	for round_number in [1, 3, 5, 8, 12, 16]:
		for hand: Array in hands:
			var carried: Array[StringName] = []
			carried.assign(hand)
			var sim := _night(round_number, carried)
			(
				assert_float(sim._crane_share(sim._players[1]))
				. override_failure_message("round %d, %s" % [round_number, hand])
				. is_equal(_bots_share(sim, carried))
			)


func test_a_play_is_not_paid_for_at_a_slim_chance_of_a_prize_worth_taking() -> void:
	# Against round 12's dead a rifle and a shotgun are beaten by a few of the prizes only.
	var carried: Array[StringName] = [RIFLE, SHOTGUN]
	var sim := _night(12, carried)
	var player: NightSim.SimPlayer = sim._players[1]
	var odds := sim._crane_share(player)
	assert_float(odds).is_greater(0.0)
	assert_float(odds).is_less(sim.skill.crane_min_odds)
	assert_bool(sim._crane_can_pay_off(player)).is_false()
	# A player who plays for any chance (the rule before #1331) pays.
	sim.skill.crane_min_odds = 0.0
	assert_bool(sim._crane_can_pay_off(player)).is_true()


func test_a_play_is_paid_for_when_a_fair_share_of_the_draw_beats_the_hands() -> void:
	var carried: Array[StringName] = [PISTOL]
	var sim := _night(3, carried)
	assert_float(sim._crane_share(sim._players[1])).is_greater_equal(sim.skill.crane_min_odds)
	assert_bool(sim._crane_can_pay_off(sim._players[1])).is_true()


func test_a_prize_let_go_ends_the_plays_of_the_round_with_the_same_hands() -> void:
	var carried: Array[StringName] = [PISTOL]
	var sim := _night(3, carried)
	var player: NightSim.SimPlayer = sim._players[1]
	assert_bool(sim._crane_can_pay_off(player)).is_true()
	player.crane_pass.note(sim.rules.round_number, player.arms)
	assert_bool(sim._crane_can_pay_off(player)).is_false()
	# The next round, or other hands, and the lock is off.
	sim.rules.round_number = 4
	assert_bool(sim._crane_can_pay_off(player)).is_true()
	sim.rules.round_number = 3
	player.arms[SMG] = NightSim.SimArm.of(SMG)
	assert_bool(sim._crane_can_pay_off(player)).is_true()


func test_a_shopper_who_is_dealt_a_prize_they_leave_remembers_the_round() -> void:
	# A weak shopper with a big purse plays the crane in the break and is dealt prizes that do not
	# beat the hands: over a few nights at least one lets a prize go and notes the round.
	var noted := 0
	for seed_value in range(1, 11):
		var tuning := RulesFixture.tuning()
		tuning.economy.start_points = 100000
		var sim := NightSim.new(tuning, SimSkill.named(SimSkill.WEAK), 1, seed_value, 0.25)
		sim.run(8)
		var player: NightSim.SimPlayer = sim._players[1]
		noted += 1 if player.crane_pass.round_number > 0 else 0
	assert_int(noted).is_greater(0)
