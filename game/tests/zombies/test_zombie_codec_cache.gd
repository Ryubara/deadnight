extends GdUnitTestSuite
## One tick's snapshot is read by every client in the process (the person, each bot, the horde), and
## decoded once: a night with three bots decoded 100 dead five times a tick (#906).


func _bytes(count: int, shift: float) -> PackedByteArray:
	var sim := ZombieFixture.sim()
	for id in count:
		ZombieFixture.standing(sim, id + 1, Vector3(float(id) + shift, 0.0, 3.0))
	return ZombieCodec.encode(sim.zombies)


func test_the_same_bytes_give_the_same_list_without_decoding_again() -> void:
	var bytes := _bytes(12, 0.0)
	var first := ZombieCodec.decode(bytes)
	var again := ZombieCodec.decode(bytes.duplicate())
	assert_int(first.size()).is_equal(12)
	# The same list: nothing was built the second time.
	assert_bool(is_same(first, again)).is_true()


func test_new_bytes_give_a_new_list_with_their_own_values() -> void:
	var first := ZombieCodec.decode(_bytes(12, 0.0))
	var next := ZombieCodec.decode(_bytes(12, 5.0))
	assert_bool(is_same(first, next)).is_false()
	assert_float((next[0]["position"] as Vector3).x).is_equal_approx(5.0, 0.011)
	assert_float((first[0]["position"] as Vector3).x).is_equal_approx(0.0, 0.011)


func test_a_short_packet_is_still_dropped_and_an_empty_one_is_empty() -> void:
	var bytes := _bytes(5, 0.0)
	ZombieCodec.decode(bytes)
	var cut := bytes.slice(0, bytes.size() - 3)
	assert_int(ZombieCodec.decode(cut).size()).is_equal(0)
	assert_int(ZombieCodec.decode(PackedByteArray()).size()).is_equal(0)
	assert_int(ZombieCodec.decode(_bytes(0, 0.0)).size()).is_equal(0)
