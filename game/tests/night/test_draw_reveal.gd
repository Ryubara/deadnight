# DrawReveal: what the lot's first draw is cut into, so no frame meets many shaders at once.
extends GdUnitTestSuite


func _mesh(kind: String, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	# Each kind is its own shader (the ledger keys a standard material by settings like these).
	material.specular_mode = (
		BaseMaterial3D.SPECULAR_DISABLED
		if kind.begins_with("a")
		else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	)
	material.emission_enabled = kind.begins_with("b")
	node.material_override = material
	parent.add_child(node)
	return node


func test_a_plan_brings_every_piece_in_exactly_once() -> void:
	var keys: Array[Array] = [["A"], ["A"], ["B"], ["A", "B"], ["C"], []]
	var steps := DrawReveal.plan(keys)
	var seen: Array[int] = []
	for step in steps:
		seen.append_array(step)
	seen.sort()
	assert_array(seen).is_equal([0, 1, 2, 3, 4, 5])


func test_a_plan_meets_the_most_used_kind_first_and_waits_for_the_last_kind_of_a_piece() -> void:
	var keys: Array[Array] = [["A"], ["A"], ["B"], ["A", "B"], ["C"], []]
	var steps := DrawReveal.plan(keys)
	# Nothing to build first, then A (three uses), then B (two; the piece with A and B waits for
	# it), then C.
	assert_array(steps).is_equal([[5], [0, 1], [2, 3], [4]])


func test_each_step_of_a_plan_meets_one_new_kind_when_pieces_have_one() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 11
	var keys: Array[Array] = []
	for _i in 200:
		keys.append(["k%d" % random.randi_range(0, 14)])
	var met: Dictionary = {}
	for step in DrawReveal.plan(keys):
		var fresh: Dictionary = {}
		for index: int in step:
			for key: String in keys[index]:
				if not met.has(key):
					fresh[key] = true
		assert_int(fresh.size()).is_less_equal(1)
		met.merge(fresh)


func test_a_plan_is_the_same_every_time() -> void:
	var keys: Array[Array] = [["B"], ["A"], ["C"], ["A"], ["B"]]
	assert_array(DrawReveal.plan(keys)).is_equal(DrawReveal.plan(keys))


func test_hiding_takes_every_showing_mesh_and_leaves_the_games_own_choices() -> void:
	var root := Node3D.new()
	add_child(root)
	_mesh("a", root)
	_mesh("b", root)
	var shy := _mesh("c", root)
	shy.visible = false  # the game's own: it must stay as it is
	var held := DrawReveal.new()
	assert_int(held.hide(root)).is_equal(2)
	assert_int(held.pending()).is_equal(2)
	assert_bool(shy.visible).is_false()
	root.queue_free()


func test_revealing_every_step_leaves_nothing_held_and_the_nodes_untouched() -> void:
	var root := Node3D.new()
	add_child(root)
	var nodes: Array[MeshInstance3D] = []
	for kind in ["a", "a", "b", "c", "c"]:
		nodes.append(_mesh(kind, root))
	var held := DrawReveal.new()
	held.hide(root)
	var steps := held.steps()
	assert_int(steps.size()).is_equal(3)  # three kinds of material, three steps
	var shown := 0
	for step in steps:
		shown += held.reveal(step).size()
	assert_int(shown).is_equal(5)
	assert_int(held.pending()).is_equal(0)
	for node in nodes:
		assert_bool(node.visible).is_true()
	root.queue_free()


func test_a_node_freed_while_held_is_skipped() -> void:
	var root := Node3D.new()
	add_child(root)
	var node := _mesh("a", root)
	var held := DrawReveal.new()
	held.hide(root)
	var steps := held.steps()
	node.free()
	assert_int(held.reveal(steps[0]).size()).is_equal(0)
	root.queue_free()
