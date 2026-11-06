# The flat test that settles a body in the open (`UseSites`) never changes what `use_target` says.
# It is a bound: a body it calls far must be offered nothing, so the answer with it and the answer
# of the offers alone (`always_near`) must be the same at every point of both maps' floors, with the
# fuel, the doors, the breaches and the posts all there. The grid is the whole lot and the small
# map at a step finer than a reach, so a reach that is cut short anywhere shows as a difference.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SMALL := "res://world/smallmap/smallmap_greybox.tscn"
## Metres between the grid's points.
const STEP := 0.5
## Metres the grid reaches past the furthest site on every side.
const MARGIN := 6.0
## Height above the grid's floor a body is put at.
const FEET := 0.0

var _night: SeatedNight


func after_test() -> void:
	if _night != null:
		_night.dispose()
		_night = null


func test_the_lot_is_offered_the_same_with_or_without_the_test() -> void:
	await _compare(LOT)


func test_the_small_map_is_offered_the_same_with_or_without_the_test() -> void:
	await _compare(SMALL)


func test_a_body_in_the_open_is_far_and_one_at_a_wall_spot_is_near() -> void:
	_night = await NightFixture.seat(
		self, 1, RulesFixture.tuning(), 7, false, load(LOT) as PackedScene
	)
	var sites := UseSites.new(_night.world)
	var tuning := _night.server.tuning
	var spot: Vector3 = _night.world.shop_spots()[0]["position"]
	assert_bool(sites.near(spot, tuning)).is_true()
	assert_bool(sites.near(spot + Vector3(500.0, 0.0, 0.0), tuning)).is_false()


func _compare(scene_path: String) -> void:
	_night = await NightFixture.seat(
		self, 1, RulesFixture.tuning(), 7, false, load(scene_path) as PackedScene
	)
	var server := _night.server
	var body := server.body_of(1)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var floor_y := body.global_position.y
	for spot in _night.world.shop_spots():
		var at: Vector3 = spot["position"]
		lo = lo.min(Vector2(at.x, at.z))
		hi = hi.max(Vector2(at.x, at.z))
	for id in _night.world.barricade_ids():
		var at := _night.world.barricade(id).centre()
		lo = lo.min(Vector2(at.x, at.z))
		hi = hi.max(Vector2(at.x, at.z))
	lo -= Vector2(MARGIN, MARGIN)
	hi += Vector2(MARGIN, MARGIN)
	var offered := 0
	var checked := 0
	var x := lo.x
	while x <= hi.x:
		var z := lo.y
		while z <= hi.y:
			body.global_position = Vector3(x, floor_y + FEET, z)
			server.use_sites.always_near = false
			var fast := server.use_target(1)
			server.use_sites.always_near = true
			var slow := server.use_target(1)
			if fast != slow:
				assert_dict(fast).is_equal(slow)
				return
			checked += 1
			if not slow.is_empty():
				offered += 1
			z += STEP
		x += STEP
	server.use_sites.always_near = false
	# Teeth: the grid met offers (so a test that only ever saw `{}` fails), and many points.
	assert_int(offered).is_greater(20)
	assert_int(checked).is_greater(500)
