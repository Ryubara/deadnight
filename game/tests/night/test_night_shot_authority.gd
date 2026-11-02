# What the server trusts of a fire command (#113): the muzzle is the server's own (from the body it
# holds, never the client's), and the aim origin may not stray further from the head than the
# slack allows. A client that lies gets the shot of a client that does not.
extends GdUnitTestSuite

const FAR := 50.0
## Ticks for the shot's events to reach the client.
const SETTLE := 5
## How far a shot's end may sit off a straight line (m): the pistol's spread, and a little.
const SPREAD_ALLOWANCE := 2.0

var _night: Night
var _shots: Array[Dictionary] = []


func before_test() -> void:
	_shots = []
	_night = await NightFixture.start(self, Night.Mode.MANUAL)
	_night.state.event_received.connect(_hear)
	NightFixture.run(_night, 30)


func after_test() -> void:
	_night.state.event_received.disconnect(_hear)
	_night.queue_free()
	await get_tree().physics_frame


func _hear(event: Dictionary) -> void:
	if event["type"] == &"shot_fired":
		_shots.append(event)


func _fire(origin: Vector3, muzzle: Vector3) -> void:
	var command := NightCommand.new()
	command.origin = origin
	command.muzzle = muzzle
	# Straight up, with the view kept on the way the body faces: a shot turns the body to its
	# view, and a view elsewhere would move the muzzle these tests measure.
	command.dir = Vector3.UP
	command.motion.yaw = _night.server.body_of(1).state.facing
	command.motion.pitch = PI / 2.0
	command.fire = true
	NightFixture.run(_night, 1, command)
	NightFixture.run(_night, SETTLE)


func test_a_muzzle_the_client_claims_is_ignored_for_the_one_the_body_has() -> void:
	var body := _night.server.body_of(1)
	var head := body.global_position + Vector3(0.0, _night.server.tuning.eye_height, 0.0)
	_fire(head, body.global_position + Vector3(FAR, FAR, FAR))
	assert_int(_shots.size()).is_equal(1)
	var expected := (
		body.global_position
		+ Basis(Vector3.UP, body.state.facing) * _night.server.tuning.muzzle_offset
	)
	assert_float((_shots[0]["muzzle"] as Vector3).distance_to(expected)).is_less(0.01)


func test_an_aim_origin_far_from_the_head_is_pulled_back_to_the_slack() -> void:
	var body := _night.server.body_of(1)
	var head := body.global_position + Vector3(0.0, _night.server.tuning.eye_height, 0.0)
	_fire(head + Vector3(FAR, 0.0, 0.0), Vector3.ZERO)
	assert_int(_shots.size()).is_equal(1)
	# Straight up from the origin: the end's horizontal place is the origin's.
	var end: Vector3 = _shots[0]["ends"][0]
	var reach := Vector2(end.x - head.x, end.z - head.z).length()
	assert_float(reach).is_less(_night.server.tuning.origin_slack + SPREAD_ALLOWANCE)


func test_an_aim_origin_within_the_slack_is_kept() -> void:
	var body := _night.server.body_of(1)
	var head := body.global_position + Vector3(0.0, _night.server.tuning.eye_height, 0.0)
	var inside := _night.server.tuning.origin_slack * 0.5
	_fire(head + Vector3(inside, 0.0, 0.0), Vector3.ZERO)
	var end: Vector3 = _shots[0]["ends"][0]
	assert_float(absf(end.x - head.x - inside)).is_less(SPREAD_ALLOWANCE)
