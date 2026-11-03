# A bot on the second map walks to its machines: with the links open and the points to pay, it buys
# the hearty tonic at the soda fountain, the re-cut at the bench on the upper floor and a second
# perk at a cooler, with real use presses at the real stands (`bot_shopping` of the map's overlay,
# the spots of `ShopSpots`). #811.
extends GdUnitTestSuite

## Game seconds a bot is given in the break to walk to all of them.
const SECONDS := 240.0
const FRAME_EVERY := 30

var _seated: SeatedNight
var _buys: Dictionary = {}


func after_test() -> void:
	if _seated != null:
		_seated.dispose()
		_seated = null


func _on_event(event: Dictionary) -> void:
	if event["type"] == &"purchase_made":
		_buys[event["item_id"]] = int(_buys.get(event["item_id"], 0)) + 1


## One regular bot in the break of a night with every link open and `points` to spend.
func _play(points: int, seconds: float) -> void:
	_buys.clear()
	_seated = await SmallMapNight.seat(self, 1, null, 3)
	_seated.seat(1, BotProfile.regular(), 401)
	for item in _seated.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			_seated.open_door(item.id)
	_seated.server.rules.apply(RulesAction.grant_points(1, points))
	await _seated.settle(10)
	_seated.on_event = _on_event
	for tick in int(seconds * 60.0):
		_seated.tick()
		if tick % FRAME_EVERY == 0:
			await get_tree().physics_frame


func test_a_rich_bot_buys_the_tonic_and_the_re_cut_and_a_perk() -> void:
	await _play(30000, SECONDS)
	(
		assert_int(int(_buys.get(&"tonic_hearty", 0)))
		. override_failure_message("bought %s" % [_buys])
		. is_greater_equal(1)
	)
	(
		assert_int(int(_buys.get(&"upgrade_weapon", 0)))
		. override_failure_message("bought %s" % [_buys])
		. is_greater_equal(1)
	)
	var perks := 0
	for id: StringName in [&"tonic_swift_rescue", &"tonic_quick_load"]:
		perks += int(_buys.get(id, 0))
	assert_int(perks).override_failure_message("bought %s" % [_buys]).is_greater_equal(1)


func test_the_map_lists_the_machines_the_bots_buy_from() -> void:
	var overlay := load("res://world/smallmap/smallmap_tuning.tres") as MapTuning
	for id: StringName in [&"tonic_hearty", &"upgrade_weapon", &"tonic_swift_rescue"]:
		assert_array(overlay.bot_shopping).contains([id])
	# The machines come after the three links, so a bot saving for a tonic never holds a door back.
	var last_door := 0
	for door: StringName in overlay.link_ids():
		last_door = maxi(last_door, overlay.bot_shopping.find(door))
	assert_int(overlay.bot_shopping.find(&"tonic_hearty")).is_greater(last_door)


func test_a_bot_with_every_link_open_buys_a_weapon_at_once_and_does_not_pace_the_landing() -> void:
	# The shotgun is sold in the side room and upstairs; the flat nearest of the two flipped on the
	# stair landing and the bot never arrived (#811, #821). Both weapons in the first 20 seconds.
	await _play(3000, 20.0)
	(
		assert_int(int(_buys.get(&"weapon_shotgun", 0)))
		. override_failure_message("bought %s" % [_buys])
		. is_equal(1)
	)
