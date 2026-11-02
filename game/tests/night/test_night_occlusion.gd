# A wall hides a sound and a car does not: the lot's walls and fences are on the occluder layer, the
# night's sounds read it through `Audio.occluder_mask`, and the service lowers and dulls what is
# behind one. (The listener here is a node of the test, as the camera is in the night.)
extends GdUnitTestSuite

const HEIGHT := 1.4
const REACH := 3.0

var _ears: Node3D


func before_test() -> void:
	Audio.stop_all()
	Audio.seed_random(3)
	_ears = auto_free(Node3D.new())
	add_child(_ears)
	Audio.listener = _ears


func after_test() -> void:
	Audio.listener = null
	Audio.stop_all()


func _start() -> Night:
	var night := await NightFixture.start(self, Night.Mode.MANUAL)
	NightFixture.run(night, 5)
	await get_tree().physics_frame
	return night


## A wall piece of the stand's front wall: a point `REACH` metres out on each side of its middle.
func _across(night: Night) -> Array[Vector3]:
	var piece := night.world.greybox.get_node("Concession/WallN0") as CSGBox3D
	var middle := piece.global_position
	var out: Array[Vector3] = [
		Vector3(middle.x, HEIGHT, middle.z - REACH), Vector3(middle.x, HEIGHT, middle.z + REACH)
	]
	return out


func test_the_night_reads_the_walls_layer() -> void:
	var night := await _start()
	assert_int(Audio.occluder_mask).is_equal(NightSounds.OCCLUDER_MASK)
	night.queue_free()


func test_a_wall_blocks_the_path_and_open_ground_does_not() -> void:
	var night := await _start()
	var across := _across(night)
	assert_float(Audio.occlusion_between(across[0], across[1])).is_equal(1.0)
	var along := across[0] + Vector3(2.0, 0.0, 0.0)
	assert_float(Audio.occlusion_between(across[0], along)).is_equal(0.0)
	night.queue_free()


func test_a_car_does_not_hide_a_sound() -> void:
	var night := await _start()
	var cars := night.world.greybox.find_children("Car*", "Node3D", true, false)
	assert_array(cars).is_not_empty()
	var middle := (cars[0] as Node3D).global_position
	var from := Vector3(middle.x - 4.0, 1.0, middle.z)
	var to := Vector3(middle.x + 4.0, 1.0, middle.z)
	assert_float(Audio.occlusion_between(from, to)).is_equal(0.0)
	night.queue_free()


func test_a_shot_behind_a_wall_is_quieter_and_duller_than_one_in_the_open() -> void:
	var night := await _start()
	var across := _across(night)
	_ears.global_position = across[0]
	var hidden := Audio.play(&"shot_rifle", across[1]) as AudioStreamPlayer3D
	var open := (
		Audio.play(&"shot_rifle", across[0] + Vector3(2.0 * REACH, 0.0, 0.0)) as AudioStreamPlayer3D
	)
	assert_object(hidden).is_not_null()
	assert_object(open).is_not_null()
	assert_float(hidden.volume_db).is_less(open.volume_db - 5.0)
	assert_float(hidden.attenuation_filter_cutoff_hz).is_less(open.attenuation_filter_cutoff_hz)
	night.queue_free()


func test_the_walls_are_still_solid_for_the_player() -> void:
	var night := await _start()
	var piece := night.world.greybox.get_node("Concession/WallN0") as CSGBox3D
	assert_int(piece.collision_layer & 1).is_equal(1)
	assert_int(piece.collision_layer & 2).is_equal(2)
	night.queue_free()


func test_leaving_the_night_lets_go_of_the_mask() -> void:
	var night := await _start()
	night.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(Audio.occluder_mask).is_equal(0)
