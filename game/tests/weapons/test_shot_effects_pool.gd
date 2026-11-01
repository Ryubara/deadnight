extends GdUnitTestSuite
## Shots and damage numbers make and free nothing while a night is played. Each one used to build
## a light or a mesh, a material and a tween and free them a moment later, which cost the frame of
## every shot and kill in the browser and made the renderer build the same shader again (a shader
## goes with the last material that uses it). Now the effects are lent from pools: the flash and
## the impacts (`MuzzleFlash`, `ImpactFx`), the streaks and the damage numbers (`ShotEffects`).

const MUZZLE := Vector3(0.0, 1.5, 4.0)
const END := Vector3(0.0, 1.0, -2.0)
## Frames a fight is played to fill the pools, and frames it is then measured over.
const WARM_FRAMES := 90
const FIGHT_FRAMES := 240
## Resources and objects a frame of the fight may hold above where it began (the test's own
## bookkeeping; a shot that made its own mesh and material would hold dozens).
const SLACK := 4

var _effects: ShotEffects
var _added := 0


func before_test() -> void:
	_effects = auto_free(ShotEffects.new())
	add_child(_effects)
	get_tree().node_added.connect(_on_node_added)


func after_test() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(_node: Node) -> void:
	_added += 1


## One frame of a hard fight: a shot that hits (flash, spark, puff), and a damage number.
func _fight_frame(index: int) -> void:
	_effects.shot(WeaponCatalog.get_def(&"pistol"), MUZZLE, [END])
	_effects.number(END, str(20 + index % 80), index % 5 == 0)
	await get_tree().process_frame


func test_a_long_fight_adds_no_node_and_holds_no_more_resources() -> void:
	for i in WARM_FRAMES:
		await _fight_frame(i)
	var nodes_before := _added
	var resources := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var peak_resources := resources
	var peak_objects := objects
	for i in FIGHT_FRAMES:
		await _fight_frame(i)
		peak_resources = maxi(
			peak_resources, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
		)
		peak_objects = maxi(peak_objects, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	assert_int(_added - nodes_before).override_failure_message("nodes made in the fight").is_equal(
		0
	)
	assert_int(peak_resources - resources).override_failure_message("resources").is_less_equal(
		SLACK
	)
	assert_int(peak_objects - objects).override_failure_message("objects").is_less_equal(SLACK)


func test_effects_are_hidden_when_they_end_and_come_back_with_their_own_look() -> void:
	_effects.number(END, "42", true)
	assert_int(_effects.live_count()).is_equal(1)
	var label := _effects.find_children("*", "Label3D", true, false)[0] as Label3D
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("42")
	await get_tree().create_timer(ShotEffects.NUMBER_SECONDS + 0.3).timeout
	assert_int(_effects.live_count()).is_equal(0)
	assert_bool(label.visible).is_false()
	_effects.number(END, "7", false)
	assert_bool(label.visible).is_true()
	assert_str(label.text).is_equal("7")
	assert_object(label.modulate).is_equal(ShotEffects.BODY_COLOUR)


func _is_streak(node: Node) -> bool:
	return (node as MeshInstance3D).mesh is CylinderMesh


func test_a_number_rises_and_a_streak_is_stretched_to_its_length() -> void:
	_effects.number(END, "9", false)
	var label := _effects.find_children("*", "Label3D", true, false)[0] as Label3D
	var start_y := label.position.y
	await get_tree().create_timer(0.2).timeout
	assert_float(label.position.y).is_greater(start_y)
	_effects.tracer(MUZZLE, END)
	var streaks := _effects.find_children("*", "MeshInstance3D", true, false)
	var streak := streaks.filter(_is_streak)[0] as MeshInstance3D
	assert_float(streak.scale.y).is_equal_approx(MUZZLE.distance_to(END), 0.001)
	assert_int(_effects.tracers_drawn).is_equal(1)


func test_more_effects_than_the_pool_holds_take_over_the_oldest_and_make_no_more_nodes() -> void:
	for i in ShotEffects.NUMBER_POOL * 3:
		_effects.number(END, str(i), false)
	assert_int(_effects.live_of(ShotEffects.Kind.NUMBER)).is_equal(ShotEffects.NUMBER_POOL)
	assert_int(_effects.nodes_made()).is_equal(ShotEffects.NUMBER_POOL)
