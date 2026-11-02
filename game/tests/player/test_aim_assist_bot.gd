extends GdUnitTestSuite
## The touch aim assist measured with a bot (#286): a modelled thumb (`ThumbBot`) turns toward a
## crowd that walks in, once with no help and once at each strength, and the share of ticks its
## crosshair spends on a zombie's hit zone says what the assist is worth. The balance simulator's
## number (`AimAssistTuning.accuracy_gain`) is this measurement, so a change to the assist that
## moves it fails here, not in a night of balance.

const SEEDS := 12
const TICKS := 3600

var _share := {}


func before() -> void:
	for strength in [0.0, 0.25, 0.5, 0.75, 1.0]:
		_share[strength] = _measure(strength)
	print(
		(
			"BOT hit share by strength: %s"
			% ", ".join(
				_share.keys().map(func(s: float) -> String: return "%.2f=%.3f" % [s, _share[s]])
			)
		)
	)


func _measure(strength: float) -> float:
	var total := 0.0
	for n in SEEDS:
		var bot := ThumbBot.new()
		bot.strength = strength
		bot.seed_value = 100 + n
		total += bot.hit_share(TICKS)
	return total / float(SEEDS)


## The share of the shots a thumb misses that the assist wins back at `strength`.
func _gain(strength: float) -> float:
	return (_share[strength] - _share[0.0]) / (1.0 - _share[0.0])


func test_the_unhelped_thumb_is_a_poor_shot() -> void:
	# Roughly the weak modelled player (SimSkill accuracy 0.45): without a number like this the
	# gain below would be measured on a thumb that needs no help.
	assert_float(_share[0.0]).is_between(0.3, 0.6)


func test_more_strength_puts_more_of_the_aim_on_a_zombie() -> void:
	var last: float = _share[0.0]
	for strength in [0.25, 0.5, 0.75, 1.0]:
		assert_float(_share[strength]).is_greater(last)
		last = _share[strength]


func test_the_assist_wins_back_what_the_simulator_assumes_at_every_strength() -> void:
	var tuning := AimAssistTuning.new()
	for strength in [0.25, 0.5, 0.75, 1.0]:
		assert_float(_gain(strength)).is_equal_approx(
			AimAssist.accuracy_gain(strength, tuning), 0.04
		)


func test_the_assist_does_not_aim_for_the_player() -> void:
	# Even at full strength a shaky thumb still misses a good part of the time: the assist is a
	# help, not a lock. A mouse player at "average" accuracy (0.65) keeps the edge.
	assert_float(_share[1.0]).is_less(0.75)


func test_the_default_strength_is_gentle() -> void:
	var default_gain := _gain(0.5)
	assert_float(default_gain).is_less(_gain(1.0))
	assert_float(default_gain).is_greater(0.05)
