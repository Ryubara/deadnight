extends GdUnitTestSuite
## The prize crane as the player sees it (`CraneView`, `PrizeCrane`): it stands at the spot the
## rules name, shows the weapons cycling during the spin and the chosen one in the grab window,
## the dud on a breakdown, and moves to the next spot when the rules do; the case holds a tiny
## model of every prize, and the prize comes out where the player can see it. Driven by hand ticks.

const SPIN_TICKS := 300
const GRAB_TICKS := 750
## The case's tiny weapons stay under the plush pile they replaced (6,912 triangles).
const PILE_TRIANGLE_BUDGET := 6912
## The prize on the board, out, seen from the marker: at least this share of the screen's width,
## and at most this share of it behind the Soldier.
const MIN_PRIZE_WIDTH := 0.1
const MAX_PRIZE_HIDDEN := 0.1
const SCREEN := Vector2(1920.0, 1080.0)
## The Soldier from behind (see `_body_corners`).
const BODY_HALF_WIDTH := 0.35
const HAIR_OVER_HEAD := 0.36


func _start(breaks: bool = false) -> Night:
	var tuning := RulesFixture.tuning()
	if breaks:
		tuning.crane.safe_plays = 0
		tuning.crane.leave_chances = PackedFloat32Array([1.0])
	var night := await NightFixture.start(self, Night.Mode.MANUAL, tuning)
	NightFixture.run(night, 5)
	night.server.rules.apply(RulesAction.grant_points(1, 5000))
	night.server.rules.doors_open.assign([&"door_concession", &"door_yard"])
	NightFixture.run(night, 3)
	return night


func _marker(night: Night, index: int) -> Dictionary:
	for spot in night.world.shop_spots():
		if spot["kind"] == &"crane" and spot["crane_spot"] == index:
			return spot
	return {}


func test_the_crane_stands_set_back_from_the_marker_of_its_spot_with_its_beam_on() -> void:
	var night := await _start()
	var prop := night.view.crane.crane
	assert_bool(prop.visible).is_true()
	var marker := _marker(night, 0)
	var apart := Vector2(
		prop.global_position.x - marker["position"].x, prop.global_position.z - marker["position"].z
	)
	assert_float(apart.length()).is_equal_approx(CraneView.SET_BACK, 0.01)
	assert_bool(prop.beam_visible()).is_true()
	night.queue_free()


func test_the_weapons_cycle_while_it_spins_and_the_chosen_one_floats() -> void:
	var night := await _start()
	night.server.buy(1, &"crane_play")
	var seen: Dictionary = {}
	for _i in SPIN_TICKS - 20:
		NightFixture.run(night, 1)
		seen[night.view.crane.crane.shown_weapon()] = true
	assert_int(seen.size()).is_greater(2)
	NightFixture.run(night, 40)
	var prize: StringName = night.server.rules.crane.weapon
	assert_str(prize).is_not_empty()
	assert_str(night.view.crane.crane.shown_weapon()).is_equal(prize)
	assert_bool(night.view.crane.crane.dud_visible()).is_false()
	night.queue_free()


func test_the_cycling_slows_down() -> void:
	var night := await _start()
	night.server.buy(1, &"crane_play")
	var changes: Array[int] = []
	var last := &"?"
	for tick in SPIN_TICKS - 40:
		NightFixture.run(night, 1)
		var shown := night.view.crane.crane.shown_weapon()
		if shown != last:
			changes.append(tick)
			last = shown
	assert_int(changes.size()).is_greater(8)
	var early := changes[2] - changes[1]
	var late := changes[changes.size() - 1] - changes[changes.size() - 2]
	assert_int(late).is_greater(early)
	night.queue_free()


func test_a_breakdown_shows_the_dud_then_the_crane_moves_to_its_next_spot() -> void:
	var night := await _start(true)
	night.server.buy(1, &"crane_play")
	NightFixture.run(night, SPIN_TICKS + 30)
	var prop := night.view.crane.crane
	assert_bool(prop.dud_visible()).is_true()
	assert_str(prop.shown_weapon()).is_empty()
	NightFixture.run(night, 300)
	var spot: int = night.server.rules.crane.spot
	assert_int(spot).is_not_equal(0)
	NightFixture.run(night, 90)
	var marker := _marker(night, spot)
	var apart := Vector2(
		prop.global_position.x - marker["position"].x, prop.global_position.z - marker["position"].z
	)
	assert_float(apart.length()).is_equal_approx(CraneView.SET_BACK, 0.05)
	assert_bool(prop.dud_visible()).is_false()
	night.queue_free()


func test_the_cabinet_is_a_wall_in_the_world_and_moves_with_the_crane() -> void:
	var night := await _start(true)
	var block := night.world.crane_block
	assert_int(block.spot()).is_equal(0)
	var marker := _marker(night, 0)
	var apart := Vector2(
		block.global_position.x - marker["position"].x,
		block.global_position.z - marker["position"].z
	)
	assert_float(apart.length()).is_equal_approx(CraneView.SET_BACK, 0.01)
	# The drawing is not the wall: the prop has no collision of its own to differ between machines.
	assert_array(night.view.crane.crane.find_children("*", "CollisionObject3D")).is_empty()
	night.server.buy(1, &"crane_play")
	NightFixture.run(night, SPIN_TICKS + 330)
	var spot: int = night.server.rules.crane.spot
	assert_int(spot).is_not_equal(0)
	assert_int(block.spot()).is_equal(spot)
	night.queue_free()


func test_every_prize_the_crane_can_give_has_a_model_and_a_far_level_of_its_own() -> void:
	var item := RulesFixture.tuning().economy.item(&"crane_play")
	assert_array(item.pool).is_not_empty()
	for prize: StringName in item.pool:
		var near := PrizeCrane.model_of(prize)
		assert_str(near).override_failure_message("%s has no model" % prize).is_not_empty()
		assert_bool(load(near) is PackedScene).is_true()
		var far := PrizeCrane.far_model_of(prize)
		assert_str(far).override_failure_message("%s has no far level" % prize).is_not_empty()
		assert_bool(load(far) is PackedScene).is_true()


func test_the_crane_reads_the_holds_where_the_animation_does() -> void:
	assert_str(PrizeCrane.HOLDS_DIR).is_equal(PlayerAnimation.HOLDS_DIR)


## The case: a tiny model of every prize, from its far level, merged into one mesh, and no plush.
func test_the_case_holds_a_tiny_far_model_of_every_prize_and_no_plush() -> void:
	var tuning := RulesFixture.tuning()
	var pool: Array[StringName] = tuning.economy.item(&"crane_play").pool
	var crane: PrizeCrane = auto_free(PrizeCrane.new())
	add_child(crane)
	crane.configure(tuning.crane, pool)
	for prize in pool:
		(
			assert_bool(crane.pile_weapons().has(prize))
			. override_failure_message("no tiny %s in the case" % prize)
			. is_true()
		)
	assert_array(crane.find_children("Plush*", "", true, false)).is_empty()
	var mesh := crane.pile_mesh()
	assert_int(mesh.get_surface_count()).is_equal(1)
	# The triangles are the far levels' (not the near models'): one far model per tiny weapon.
	var expected := 0
	for prize in crane.pile_weapons():
		expected += _triangles(load(PrizeCrane.far_model_of(prize)) as PackedScene)
	var triangles := (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_int(triangles).is_equal(expected)
	# The plush pile it replaced was 48 spheres of 144 triangles (6,912) and 48 draw calls.
	assert_int(triangles).is_less(PILE_TRIANGLE_BUDGET)


## Every weapon model with a hold file is ready for the pool before it is a prize (the models of
## #822 landed before their catalogue entries): a pool of all of them puts a tiny far model of
## each in the case, every one at least once, still one draw call and under the plush's triangles.
## The grenade is thrown, not won, and `melee` is the bat's second hold.
func test_a_pool_of_every_modelled_weapon_fills_the_case_within_the_budget() -> void:
	var pool: Array[StringName] = []
	for file in DirAccess.get_files_at(PrizeCrane.HOLDS_DIR):
		var id := file.trim_suffix(".remap").get_basename()
		if file.ends_with(".tres") or file.ends_with(".tres.remap"):
			if id not in ["grenade", "melee"] and not pool.has(StringName("weapon_" + id)):
				pool.append(StringName("weapon_" + id))
	for id in ["weapon_mp5", "weapon_ppsh", "weapon_m4a1", "weapon_dual_pistols"]:
		assert_array(pool).contains([StringName(id)])
	var crane: PrizeCrane = auto_free(PrizeCrane.new())
	add_child(crane)
	crane.configure(RulesFixture.tuning().crane, pool)
	var expected := 0
	for prize in pool:
		var far := PrizeCrane.far_model_of(prize)
		assert_str(far).override_failure_message("%s has no far level" % prize).is_not_empty()
		(
			assert_bool(crane.pile_weapons().has(prize))
			. override_failure_message("no tiny %s in the case" % prize)
			. is_true()
		)
	for prize in crane.pile_weapons():
		expected += _triangles(load(PrizeCrane.far_model_of(prize)) as PackedScene)
	var mesh := crane.pile_mesh()
	assert_int(mesh.get_surface_count()).is_equal(1)
	var triangles := (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_int(triangles).is_equal(expected)
	assert_int(triangles).is_less(PILE_TRIANGLE_BUDGET)


## A prize added to the pool before its model has a stand-in in the case and on the board, and
## the crane needs no edit for it.
func test_a_prize_with_no_model_yet_still_lies_in_the_case() -> void:
	var tuning := RulesFixture.tuning()
	var pool: Array[StringName] = [&"weapon_shotgun", &"weapon_not_modelled_yet"]
	var crane: PrizeCrane = auto_free(PrizeCrane.new())
	add_child(crane)
	crane.configure(tuning.crane, pool)
	assert_bool(crane.pile_weapons().has(&"weapon_not_modelled_yet")).is_true()
	assert_str(PrizeCrane.model_of(&"weapon_not_modelled_yet")).is_empty()
	crane.show_state(
		{"stage": CraneState.Stage.GRAB, "left": 8.0, "weapon": "weapon_not_modelled_yet"}, 0.1
	)
	assert_str(crane.shown_weapon()).is_equal(&"weapon_not_modelled_yet")


## What "readable" means, measured on a 1920 x 1080 screen of the player's own shoulder camera as
## it rests, standing on the crane's marker looking level at the machine: once the board is out,
## every prize is whole on the screen, wide enough to tell apart, and over the Soldier's head, not
## behind it. A board at grab height (1.35 m) fails it: the head covers the prize.
func test_every_prize_comes_out_where_the_player_on_the_marker_can_see_it() -> void:
	var night := await _start()
	var crane := night.view.crane.crane
	var player := night.player()
	var standing: Vector3 = _marker(night, 0)["position"]
	var look := crane.global_position - standing
	var command := NightCommand.new()
	command.motion.yaw = atan2(-look.x, -look.z)
	player.teleport(standing)
	night.server.buy(1, &"crane_play")
	NightFixture.run(night, SPIN_TICKS + 5, command)
	var rules := night.server.rules
	assert_int(rules.crane.stage).is_equal(CraneState.Stage.GRAB)
	var lens := _measuring_lens()
	for prize: StringName in rules.tuning.economy.item(&"crane_play").pool:
		rules.crane.weapon = prize
		rules.crane.left = rules.tuning.crane.grab_seconds - 1.5
		player.teleport(standing)
		player.camera_rig.yaw = command.motion.yaw
		player.camera_rig.pitch = 0.0
		NightFixture.run(night, 2, command)
		# Twice: the first placement after a turn of the rig still reads the old lens.
		player.camera_rig.snap_to(player.global_position)
		player.camera_rig.snap_to(player.global_position)
		lens.global_transform = player.camera_rig.camera().global_transform
		lens.fov = player.camera_rig.camera().fov
		assert_float(crane.prize_out()).is_greater(0.95)
		assert_str(crane.shown_weapon()).is_equal(prize)
		var seen := _on_screen(lens, _mesh_corners(crane.prize_node().get_node(String(prize))))
		var body := _on_screen(lens, _body_corners(player))
		var name := String(prize)
		var width := seen.size.x / SCREEN.x
		var hidden := seen.intersection(body).get_area() / maxf(seen.get_area(), 1.0)
		print("PRIZE ON SCREEN %s %s width %.3f behind the body %.2f" % [name, seen, width, hidden])
		(
			assert_bool(Rect2(Vector2.ZERO, SCREEN).encloses(seen))
			. override_failure_message("%s leaves the screen: %s" % [name, seen])
			. is_true()
		)
		(
			assert_float(width)
			. override_failure_message("%s is %.3f of the screen wide" % [name, width])
			. is_greater(MIN_PRIZE_WIDTH)
		)
		(
			assert_float(hidden)
			. override_failure_message(
				"%s is %.2f behind the body (%s, body %s)" % [name, hidden, seen, body]
			)
			. is_less(MAX_PRIZE_HIDDEN)
		)
	night.queue_free()


## A camera in a 1920 x 1080 view of the same world, to project points as the player's screen does.
func _measuring_lens() -> Camera3D:
	var view: SubViewport = auto_free(SubViewport.new())
	view.size = Vector2i(SCREEN)
	view.disable_3d = false
	add_child(view)
	var lens := Camera3D.new()
	view.add_child(lens)
	return lens


## The corners of every shown mesh's box under `node`, in the world.
func _mesh_corners(node: Node) -> PackedVector3Array:
	var corners := PackedVector3Array()
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree():
			var box := mesh.global_transform * mesh.get_aabb()
			for i in 8:
				corners.append(box.get_endpoint(i))
	return corners


## The Soldier as the camera sees it from behind: a box round the spine and the head, as wide as
## the shoulders and the hair, from the feet to the top of the hair (measured on a capture: the
## hair's top is 0.36 m over the `Head` bone, the hair and shoulders 0.7 m across). The test's
## body is not animated, so the arms (straight out at rest) are left out.
func _body_corners(player: Player) -> PackedVector3Array:
	var skeleton := player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var head := (
		skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	)
	var feet := player.global_position
	var box := AABB(
		Vector3(head.x - BODY_HALF_WIDTH, feet.y, head.z - BODY_HALF_WIDTH),
		Vector3(BODY_HALF_WIDTH * 2.0, head.y + HAIR_OVER_HEAD - feet.y, BODY_HALF_WIDTH * 2.0)
	)
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(box.get_endpoint(i))
	return corners


func _on_screen(lens: Camera3D, corners: PackedVector3Array) -> Rect2:
	if corners.is_empty():
		return Rect2()
	var rect := Rect2(lens.unproject_position(corners[0]), Vector2.ZERO)
	for corner in corners:
		rect = rect.expand(lens.unproject_position(corner))
	return rect


func _triangles(scene: PackedScene) -> int:
	var model := scene.instantiate() as Node3D
	var count := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays[Mesh.ARRAY_INDEX] != null:
				count += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			else:
				count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	model.free()
	return count
