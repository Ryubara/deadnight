# A damage number that has a world point is drawn over it as the camera has it this frame.
extends GdUnitTestSuite

var _host: Control
var _hud: Hud


func before_test() -> void:
	_host = auto_free(Control.new())
	_host.size = Vector2(1920, 1080)
	add_child(_host)
	_hud = HudFixture.make(_host, 1).hud


func test_a_number_follows_the_projector_and_hides_when_out_of_view() -> void:
	var crosshair := _hud.crosshair
	var share := [Vector2(0.25, 0.5)]
	crosshair.projector = func(_point: Vector3) -> Vector2: return share[0]
	var hit := {"type": &"zombie_damaged", "player_id": 1, "zone": &"body", "damage": 12.0}
	hit["world"] = Vector3(1.0, 2.0, 3.0)
	_hud.state.apply_event(hit)
	var number: Dictionary = crosshair.numbers[0]
	var nudge: float = number["nudge"]
	var at := crosshair.number_at(number)
	assert_vector(at).is_equal_approx(
		share[0] * crosshair.size + Vector2(nudge, 0.0), Vector2(0.01, 0.01)
	)
	share[0] = Vector2(0.75, 0.4)
	assert_vector(crosshair.number_at(number)).is_equal_approx(
		share[0] * crosshair.size + Vector2(nudge, 0.0), Vector2(0.01, 0.01)
	)
	share[0] = Vector2.INF
	assert_bool(crosshair.number_at(number).is_finite()).is_false()
	# One with no world point stays where it began.
	_hud.state.apply_event(
		{"type": &"zombie_damaged", "player_id": 1, "zone": &"body", "damage": 5.0}
	)
	var plain: Dictionary = crosshair.numbers.back()
	assert_vector(crosshair.number_at(plain)).is_equal(plain["at"])
