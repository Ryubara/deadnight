# What the autopilot does with a gun that has run dry (#998): it does not swap between two empty
# guns, a flight from the dead bends toward the shop it has planned, it does not count a locker on
# the floor above as reached, and it does not stand at a door it cannot pay for.
extends GdUnitTestSuite

var _state: ClientState
var _pilot: Autopilot
var _map: RID


func before_test() -> void:
	_state = ClientState.new()
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	_pilot = Autopilot.new(_state, _map)


func after_test() -> void:
	NavigationServer3D.free_rid(_map)


func _carry(held: StringName, arms: Dictionary) -> void:
	_state.frame = {"players": {1: {"weapon": held, "arms": arms, "points": 500}}}


func test_an_empty_gun_next_to_another_empty_gun_is_not_swapped_away() -> void:
	_carry(&"pistol", {&"pistol": [0, 0, 0], &"shotgun": [0, 0, 0]})
	assert_bool(_pilot._wants_swap(_pilot._held())).is_false()


func test_an_empty_gun_is_swapped_for_a_gun_with_rounds_or_a_blade() -> void:
	_carry(&"pistol", {&"pistol": [0, 0, 0], &"shotgun": [2, 8, 0]})
	assert_bool(_pilot._wants_swap(_pilot._held())).is_true()
	_carry(&"pistol", {&"pistol": [0, 0, 0], &"crowbar": [1, 0, 0]})
	assert_bool(_pilot._wants_swap(_pilot._held())).is_true()


func test_an_empty_gun_goes_to_the_blade_only_with_the_dead_near() -> void:
	_carry(&"pistol", {&"pistol": [0, 0, 0], &"crowbar": [1, 0, 0]})
	assert_bool(_pilot._wants_swap(_pilot._held(), false)).is_false()
	assert_bool(_pilot._wants_swap(_pilot._held(), true)).is_true()


func test_the_gun_that_ran_dry_is_taken_up_again_to_buy_rounds_when_nothing_is_near() -> void:
	_pilot.ammo_prices = {&"pistol": 50}
	_carry(&"crowbar", {&"pistol": [0, 0, 0], &"crowbar": [1, 0, 0]})
	assert_bool(_pilot._wants_refill_gun(_pilot._held(), false)).is_true()
	assert_bool(_pilot._wants_refill_gun(_pilot._held(), true)).is_false()
	# Nothing to pay with, or a gun with rounds: no trip.
	_state.frame["players"][1]["points"] = 10
	assert_bool(_pilot._wants_refill_gun(_pilot._held(), false)).is_false()
	_carry(&"crowbar", {&"pistol": [10, 60, 0], &"crowbar": [1, 0, 0]})
	assert_bool(_pilot._wants_refill_gun(_pilot._held(), false)).is_false()


func test_a_flight_bends_toward_the_planned_shop_when_the_gun_is_nearly_out() -> void:
	var here := Vector3(0.0, 0.0, 0.0)
	var from := Vector3(-5.0, 0.0, 0.0)
	_pilot.ammo_prices = {&"pistol": 50}
	_carry(&"pistol", {&"pistol": [0, 0, 0]})
	var to_home := _pilot._flee(here, from)
	_pilot._shopping = {"kind": &"ammo", "position": Vector3(0.0, 0.0, 30.0)}
	var to_shop := _pilot._flee(here, from)
	# Home is at the back of the lot (negative z); the shop is the other way.
	assert_float(to_shop.z).is_greater(to_home.z)
	assert_float(to_shop.x).is_greater(0.0)
	_carry(&"pistol", {&"pistol": [10, 60, 0]})
	assert_vector(_pilot._flee(here, from)).is_equal_approx(to_home, Vector3.ONE * 0.001)


func test_a_locker_on_the_floor_above_is_not_arrived_at() -> void:
	var here := Vector3(12.0, 0.0, 4.0)
	assert_vector(_pilot._toward(here, Vector3(12.0, 3.4, 3.2))).is_not_equal(Vector3.ZERO)
	assert_vector(_pilot._toward(here, Vector3(12.0, 0.0, 3.2))).is_equal(Vector3.ZERO)


func test_it_holds_still_at_a_door_only_when_it_can_pay_for_it() -> void:
	_carry(&"pistol", {&"pistol": [10, 60, 0]})
	assert_bool(_pilot._buying_door(&"door", {"price": 400})).is_true()
	assert_bool(_pilot._buying_door(&"door", {"price": 900})).is_false()
	assert_bool(_pilot._buying_door(&"ammo", {"price": 50})).is_false()
