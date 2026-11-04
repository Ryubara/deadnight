# The server's crowd lists are made once for each state of the dead, not once a tick (#931), and
# never differ from a list made fresh: the target list, the zombie bytes of the frame, and the shop
# spots every player's prompt reads. Played on the real lot with a crowd, a hit and a kill between
# the sim's steps.
extends GdUnitTestSuite

const STEP := Night.STEP
const SEED := 931
const TICKS := 420

var _night: SeatedNight


func after_test() -> void:
	PerfProbe.enabled = false
	PerfProbe.take()
	if _night != null:
		_night.dispose()
		_night = null


func _crowded() -> void:
	_night = await SeatedNight.start(self, 2, SeatedNight.brisk(), SEED)
	_night.start_round()


## The list as the server used to make it, on every tick.
func _fresh_list(server: NightServer) -> Array:
	var list: Array = []
	for zombie: ZombieBody in server.sim.zombies.values():
		if zombie.is_alive():
			list.append(zombie.hit_target())
	return list


func test_the_target_list_is_the_fresh_list_on_every_tick_and_made_once_a_step() -> void:
	await _crowded()
	var server := _night.server
	PerfProbe.enabled = true
	var built := 0
	var steps := 0
	var seen := 0
	for tick in TICKS:
		var revision_before := server.sim.revision
		_night.tick()
		if server.sim.revision != revision_before:
			steps += 1
		assert_array(server._target_list()).is_equal(_fresh_list(server))
		var counts: Dictionary = PerfProbe.take()["counts"]
		built += counts.get(&"server.targets_built", 0)
		seen = maxi(seen, server.sim.zombies.size())
	assert_int(seen).is_greater(3)
	# At most one build for each time the dead changed, and the grenades' second ask is free.
	assert_int(built).is_less_equal(steps + 2)
	assert_int(built).is_less(TICKS)


func test_a_kill_between_steps_is_in_the_next_list() -> void:
	await _crowded()
	var server := _night.server
	for _i in 600:
		_night.tick()
		if server.sim.standing_count() >= 2:
			break
	var ids: Array = server.sim.zombies.keys()
	var before := server._target_list().size()
	assert_int(before).is_greater(1)
	var id: int = ids[0]
	var result := server.director.take_hit(id, &"head", 100000.0, 1, false)
	assert_bool(result["killed"]).is_true()
	var after := server._target_list()
	assert_int(after.size()).is_equal(before - 1)
	assert_array(after).is_equal(_fresh_list(server))
	for target in after:
		assert_int(target["id"]).is_not_equal(id)


func test_the_frames_zombie_bytes_are_the_fresh_bytes_and_encoded_once_a_step() -> void:
	await _crowded()
	var server := _night.server
	PerfProbe.enabled = true
	var encoded := 0
	var steps := 0
	for _i in TICKS:
		var revision_before := server.sim.revision
		_night.tick()
		if server.sim.revision != revision_before:
			steps += 1
		assert_that(_night.frame["zombies"]).is_equal(ZombieCodec.encode(server.sim.zombies))
		encoded += PerfProbe.take()["counts"].get(&"server.zombies_encoded", 0)
	# One more than the steps: the first frame, before the first step, encodes too.
	assert_int(encoded).is_less_equal(steps + 1)
	assert_int(encoded).is_less(TICKS)


func test_the_shop_spots_are_read_once_and_are_the_markers() -> void:
	await _crowded()
	var world := _night.world
	var spots := world.shop_spots()
	assert_bool(is_same(spots, world.shop_spots())).is_true()
	assert_int(spots.size()).is_greater(5)
	var markers := world.greybox.get_node("ShopSpots").get_children()
	assert_int(spots.size()).is_equal(markers.size())
	for i in markers.size():
		var marker := markers[i] as Node3D
		assert_str(String(spots[i]["kind"])).is_equal(String(marker.get_meta("kind")))
		assert_str(String(spots[i]["shop_id"])).is_equal(String(marker.get_meta("shop_id")))
		assert_vector(spots[i]["position"]).is_equal(marker.global_position)
		assert_int(spots[i]["crane_spot"]).is_equal(int(marker.get_meta("crane_spot", 0)))
	assert_bool(spots.is_read_only()).is_true()
	assert_bool((spots[0] as Dictionary).is_read_only()).is_true()


func test_a_prompt_at_every_spot_offers_what_a_fresh_read_of_the_spots_would() -> void:
	await _crowded()
	var server := _night.server
	var body := server.body_of(1)
	var cached := server.world.shop_spots()
	var spot_count := cached.size()
	for i in spot_count:
		body.teleport(cached[i]["position"] + Vector3(0.0, 0.1, 0.5))
		var first := server.use_target(1)
		# The same place asked again, and by the other player, is the same offer.
		assert_dict(server.use_target(1)).is_equal(first)
		server.body_of(2).teleport(body.global_position)
		assert_str(String(server.use_target(2).get("kind", ""))).is_equal(
			String(first.get("kind", ""))
		)
