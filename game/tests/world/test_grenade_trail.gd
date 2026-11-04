# The grenade's trail of fading dots is a pool: one multimesh over one shared low-poly mesh and one
# shared material, so a flight makes no node, mesh, material or tween per dot (Deadnight #936).
extends GdUnitTestSuite

const STEP := 1.0 / 60.0
## A 3 s flight is 180 steps.
const FLIGHT_STEPS := 180
const THROWS := 12
## The old dot: a default sphere of 64 x 32 segments.
const OLD_DOT_TRIANGLES := 4224


func _flying_view() -> GrenadeView:
	var view := auto_free(GrenadeView.new()) as GrenadeView
	view.trail = true
	view.state = GrenadeState.new(
		1,
		1,
		GrenadesFixture.def(),
		Vector3(0.0, 1.5, 0.0),
		Vector3(7.5, 6.0, 0.0),
		GrenadesFixture.def().fuse
	)
	add_child(view)
	view.follow(0.0)
	return view


## Flies `view` for `steps` steps over a flat floor.
func _fly(view: GrenadeView, steps: int) -> void:
	var cast := GrenadesFixture.world_cast()
	for _i in steps:
		view.state.step(STEP, cast)
		view.follow(STEP)


## How many drawn things the view has that are shown.
func _draw_calls(view: Node) -> int:
	var calls := 0
	for node in view.find_children("*", "GeometryInstance3D", true, false):
		if (node as GeometryInstance3D).is_visible_in_tree():
			calls += 1
	return calls


func _trail_of(view: Node) -> GrenadeTrail:
	return view.find_children("*", "GrenadeTrail", true, false)[0] as GrenadeTrail


func test_a_dot_is_a_low_poly_sphere_not_the_default_one() -> void:
	var triangles := GrenadeTrail.shared_mesh().get_faces().size() / 3
	assert_int(triangles).is_less_equal(200)
	assert_int(OLD_DOT_TRIANGLES / triangles).is_greater(20)


func test_every_trail_shares_one_mesh_and_one_material() -> void:
	var first := _flying_view()
	var second := _flying_view()
	_fly(first, 6)
	_fly(second, 6)
	var a := _trail_of(first)
	var b := _trail_of(second)
	assert_bool(a.multimesh.mesh == b.multimesh.mesh).is_true()
	assert_bool(a.multimesh.mesh == GrenadeTrail.shared_mesh()).is_true()
	assert_bool(GrenadeTrail.shared_mesh().material == GrenadeTrail.shared_material()).is_true()
	assert_bool(GrenadeTrail.shared_material().vertex_color_use_as_albedo).is_true()


func test_a_three_second_flight_adds_no_node_after_the_first_dot() -> void:
	var view := _flying_view()
	_fly(view, 2)
	var nodes := view.find_children("*", "", true, false).size()
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var peak_calls := 0
	var most_nodes := nodes
	var cast := GrenadesFixture.world_cast()
	for _i in FLIGHT_STEPS:
		view.state.step(STEP, cast)
		view.follow(STEP)
		peak_calls = maxi(peak_calls, _draw_calls(view))
		most_nodes = maxi(most_nodes, view.find_children("*", "", true, false).size())
	# Read before any assertion: an assertion is an object of its own.
	var objects_after := Performance.get_monitor(Performance.OBJECT_COUNT)
	assert_int(most_nodes).is_equal(nodes)
	assert_float(objects_after).is_less_equal(objects)
	# The lamp's bulb is a draw of its own, and the shell: the trail adds one.
	assert_int(peak_calls).is_less_equal(_draw_calls(view) + 1)


func test_the_trail_is_one_draw_call_while_dots_are_alive() -> void:
	var view := _flying_view()
	_fly(view, 60)
	var trail := _trail_of(view)
	assert_int(trail.live_count()).is_between(20, GrenadeTrail.CAP)
	assert_bool(trail.visible).is_true()
	assert_int(view.find_children("*", "MultiMeshInstance3D", true, false).size()).is_equal(1)
	# No dot is a node of its own.
	for node in view.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		assert_bool(instance.top_level and instance.mesh is SphereMesh).is_false()


func test_objects_and_nodes_are_flat_after_many_throws() -> void:
	# A first throw makes the shared mesh and material; the ones after it make nothing that stays.
	var warm := _flying_view()
	_fly(warm, FLIGHT_STEPS)
	warm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var resources := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	for _i in THROWS:
		var view := _flying_view()
		_fly(view, FLIGHT_STEPS)
		view.queue_free()
		await get_tree().process_frame
	await get_tree().process_frame
	# Read before any assertion: an assertion is an object of its own.
	var objects_now := Performance.get_monitor(Performance.OBJECT_COUNT)
	var resources_now := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	var nodes_now := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans_now := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	# Growth only: an earlier suite's object freed during the throws lowers a count and is not a leak.
	assert_float(objects_now).is_less_equal(objects)
	assert_float(resources_now).is_less_equal(resources)
	assert_float(nodes_now).is_less_equal(nodes)
	assert_float(orphans_now).is_less_equal(orphans)


func test_a_dot_fades_to_nothing_in_its_time_and_leaves_no_draw() -> void:
	var trail := auto_free(GrenadeTrail.new()) as GrenadeTrail
	add_child(trail)
	assert_bool(trail.visible).is_false()
	trail.drop(Vector3.ZERO)
	assert_bool(trail.visible).is_true()
	trail.advance(GrenadeTrail.SECONDS * 0.5)
	assert_float(trail.alphas()[0]).is_equal_approx(0.5, 0.001)
	trail.advance(GrenadeTrail.SECONDS * 0.5 + 0.001)
	assert_int(trail.live_count()).is_equal(0)
	assert_bool(trail.visible).is_false()


func test_a_full_ring_takes_over_the_oldest_dot() -> void:
	var trail := auto_free(GrenadeTrail.new()) as GrenadeTrail
	add_child(trail)
	for i in GrenadeTrail.CAP * 3:
		trail.drop(Vector3(i, 0.0, 0.0))
		trail.advance(0.001)
		assert_int(trail.live_count()).is_less_equal(GrenadeTrail.CAP)
	assert_int(trail.live_count()).is_equal(GrenadeTrail.CAP)
	assert_int(trail.multimesh.instance_count).is_equal(GrenadeTrail.CAP)


func test_the_trail_follows_the_fixed_step_so_a_run_fades_the_same_way_each_time() -> void:
	var one := _flying_view()
	var two := _flying_view()
	_fly(one, 70)
	_fly(two, 70)
	assert_array(_trail_of(one).alphas()).is_equal(_trail_of(two).alphas())


func test_a_view_without_a_trail_makes_none() -> void:
	var view := auto_free(GrenadeView.new()) as GrenadeView
	view.state = GrenadeState.new(
		1, 1, GrenadesFixture.def(), Vector3(0.0, 1.5, 0.0), Vector3.ZERO, 3.0
	)
	add_child(view)
	_fly(view, 20)
	assert_array(view.find_children("*", "GrenadeTrail", true, false)).is_empty()
