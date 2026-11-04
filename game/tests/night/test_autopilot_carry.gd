# The autopilot plays the two-weapon carry (#410): with both hands full it takes a weapon only when
# that is worth `WeaponWorth.REPLACE_GAIN` times the one in hand (which the weapon replaces), and
# plays the crane only when some prize would be. Without the margin it buys in circles.
extends GdUnitTestSuite

const POINTS := 5000

var _state: ClientState
var _pilot: Autopilot


func before_test() -> void:
	_state = ClientState.new()
	_pilot = Autopilot.new(_state, RID())
	_pilot.wanted.assign([&"weapon_shotgun", &"weapon_rifle", &"crane_play"])
	_pilot.crane_pool.assign([&"weapon_shotgun", &"weapon_rifle", &"weapon_smg"])


func _carry(held: StringName, arms: Array[StringName]) -> void:
	var counts := {}
	for id in arms:
		counts[id] = [10, 30]
	_state.frame = {
		"players": {1: {"weapon": held, "arms": counts, "points": POINTS}},
		"crane": {},
	}


func _wall(weapon: StringName) -> Dictionary:
	return {"kind": &"weapon", "id": StringName("weapon_%s" % weapon), "price": 900}


func test_a_free_hand_takes_any_weapon() -> void:
	_carry(&"house_pistol", [&"house_pistol"])
	assert_bool(_pilot._wants(_wall(&"shotgun"))).is_true()


func test_full_hands_take_a_weapon_worth_one_and_a_half_times_the_one_in_hand() -> void:
	_carry(&"house_pistol", [&"house_pistol", &"crowbar"])
	assert_bool(_pilot._wants(_wall(&"shotgun"))).is_true()


func test_full_hands_do_not_swap_a_weapon_for_one_of_much_the_same_worth() -> void:
	# The shotgun and the rifle are worth about the same: buying one for the other is a circle.
	_carry(&"shotgun", [&"shotgun", &"crowbar"])
	assert_bool(_pilot._wants(_wall(&"rifle"))).is_false()


func test_a_weapon_already_carried_is_not_taken() -> void:
	_carry(&"house_pistol", [&"house_pistol", &"shotgun"])
	assert_bool(_pilot._wants(_wall(&"shotgun"))).is_false()


func test_it_plays_the_crane_only_when_some_prize_beats_the_weapon_in_hand() -> void:
	_carry(&"house_pistol", [&"house_pistol", &"crowbar"])
	assert_bool(_pilot._wants({"kind": &"crane", "id": &"crane_play", "price": 550})).is_true()
	# Holding the best of the pool, nothing in it is worth the play.
	_pilot.crane_pool.assign([&"weapon_house_pistol", &"weapon_crowbar"])
	assert_bool(_pilot._wants({"kind": &"crane", "id": &"crane_play", "price": 550})).is_false()


func test_it_leaves_a_prize_that_is_worse_than_the_weapon_it_would_replace() -> void:
	_carry(&"shotgun", [&"shotgun", &"crowbar"])
	assert_bool(_pilot._worth_taking(&"house_pistol")).is_false()
	assert_bool(_pilot._worth_taking(&"smg")).is_false()
