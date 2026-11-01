# The centre reticle: present, centred, small, scaled with the HUD, hidden when it should be, and
# tunable from the editor.
extends GdUnitTestSuite

const CANVAS := Vector2(1920.0, 1080.0)

var _host: Control
var _fixture: HudFixture


func before_test() -> void:
	_host = auto_free(Control.new()) as Control
	_host.size = CANVAS
	add_child(_host)
	_fixture = HudFixture.make(_host)
	_fixture.hud.size = CANVAS
	await get_tree().process_frame


func _reticle() -> HudReticle:
	return _fixture.hud.reticle


func test_the_hud_has_a_reticle_that_fills_the_screen_under_the_hit_markers() -> void:
	var reticle := _reticle()
	assert_object(reticle.get_parent()).is_same(_fixture.hud)
	assert_str(String(reticle.name)).is_equal("Reticle")
	assert_vector(reticle.size).is_equal_approx(CANVAS, Vector2(1.0, 1.0))
	assert_bool(reticle.visible).is_true()
	# Drawn before the hit marker layer, so a hit's ticks sit over it.
	assert_int(reticle.get_index()).is_less(_fixture.hud.crosshair.get_index())
	assert_int(reticle.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_the_reticle_is_centred_and_symmetric() -> void:
	var centre := CANVAS * 0.5
	var shapes := _reticle().shapes(centre)
	assert_int(shapes.size()).is_equal(5)  # four ticks and the dot
	var total := Vector2.ZERO
	for rect in shapes:
		total += rect.get_center() - centre
	assert_vector(total).is_equal_approx(Vector2.ZERO, Vector2(0.001, 0.001))
	# The four ticks are equally far from the centre, and the dot is on it.
	var distances: Array[float] = []
	for rect in shapes.slice(0, 4):
		distances.append(rect.get_center().distance_to(centre))
	for d in distances:
		assert_float(d).is_equal_approx(distances[0], 0.001)
	assert_vector(shapes[4].get_center()).is_equal_approx(centre, Vector2(0.001, 0.001))
	# There is a gap: no tick touches the centre.
	for rect in shapes.slice(0, 4):
		assert_bool(rect.grow(-0.01).has_point(centre)).is_false()


func test_the_reticle_is_small_static_and_edged_for_dark_and_lit_ground() -> void:
	var style := _reticle().style
	assert_float(style.radius() * 2.0).is_less(CANVAS.y * 0.04)
	assert_float(style.thickness).is_greater_equal(2.0)
	assert_float(style.outline).is_greater(0.0)
	# Static: nothing is drawn from the player's state, and no process step moves it.
	assert_bool(_reticle().is_processing()).is_false()
	var before := _reticle().shapes(CANVAS * 0.5)
	_fixture.advance(2.0)
	assert_array(_reticle().shapes(CANVAS * 0.5)).is_equal(before)


func test_the_reticle_scales_with_the_hud() -> void:
	# The HUD is laid out in canvas units that the viewport stretches to the window: a reticle
	# drawn in those units is 2/3 as big on screen at 720p as at 1080p, and follows the UI scale.
	var radius := _reticle().style.radius()
	var at_1080 := _on_screen_radius(Vector2i(1920, 1080), 1.0, radius)
	var at_720 := _on_screen_radius(Vector2i(1280, 720), 1.0, radius)
	var scaled_ui := _on_screen_radius(Vector2i(1280, 720), 1.25, radius)
	assert_float(at_1080).is_equal_approx(radius, 0.01)
	assert_float(at_720).is_equal_approx(radius * 2.0 / 3.0, 0.01)
	assert_float(scaled_ui).is_equal_approx(at_720 * 1.25, 0.01)


## The radius in window pixels of something `radius` canvas units big, in a window of `window`
## pixels over the project's 1920 x 1080 canvas, with the UI scale `ui_scale`.
func _on_screen_radius(window: Vector2i, ui_scale: float, radius: float) -> float:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = window
	viewport.size_2d_override = Vector2i(CANVAS / ui_scale)
	viewport.size_2d_override_stretch = true
	add_child(viewport)
	return radius * viewport.get_final_transform().get_scale().x


func test_the_style_is_editable_in_the_editor() -> void:
	var exported: Array[String] = []
	for property in _reticle().style.get_property_list():
		if (
			property["usage"] & PROPERTY_USAGE_EDITOR
			and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE
		):
			exported.append(property["name"])
	for name_wanted in ["arm_length", "gap", "thickness", "outline", "dot", "tint", "opacity"]:
		assert_array(exported).contains([name_wanted])
	# The HUD node exposes the style, so it is set on the scene's root in the inspector.
	var on_hud: Array[String] = []
	for property in _fixture.hud.get_property_list():
		if (
			property["usage"] & PROPERTY_USAGE_EDITOR
			and property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE
		):
			on_hud.append(property["name"])
	assert_array(on_hud).contains(["reticle_style"])
	assert_str(_fixture.hud.reticle_style.resource_path).is_not_empty()


func test_a_changed_style_changes_the_shapes() -> void:
	var style := _reticle().style
	var wide := style.duplicate() as ReticleStyle
	wide.gap = 20.0
	wide.dot = 0.0
	_reticle().style = wide
	var shapes := _reticle().shapes(CANVAS * 0.5)
	assert_int(shapes.size()).is_equal(4)
	assert_float(shapes[0].get_center().distance_to(CANVAS * 0.5)).is_equal_approx(
		20.0 + wide.arm_length * 0.5, 0.001
	)


func test_the_screen_hides_it_for_a_menu_and_shows_it_again() -> void:
	_reticle().set_shown(false)
	assert_bool(_reticle().visible).is_false()
	_reticle().set_shown(true)
	assert_bool(_reticle().visible).is_true()


func test_a_downed_player_has_no_reticle_until_revived() -> void:
	_fixture.into_round_one()
	_fixture.act(RulesAction.set_downed(1, true))
	assert_bool(_reticle().visible).is_false()
	_fixture.act(RulesAction.set_downed(1, false))
	assert_bool(_reticle().visible).is_true()
	# A menu keeps it hidden even when the player is up.
	_reticle().set_shown(false)
	_fixture.act(RulesAction.set_downed(1, true))
	_fixture.act(RulesAction.set_downed(1, false))
	assert_bool(_reticle().visible).is_false()
