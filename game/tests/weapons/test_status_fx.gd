extends GdUnitTestSuite
## What the wonder weapons draw (#788): the ice pieces of a shattered zombie, the ray gun's
## burst and its bolt in its own colours (the freeze gun's too). All of it is pooled: made once
## ahead of the night, lent and taken back, so a kill or a burst in the middle of a night makes no
## mesh and no shader.

const FRAME := 1.0 / 60.0


func _effects() -> ShotEffects:
	var effects := ShotEffects.new()
	add_child(effects)
	auto_free(effects)
	effects.prewarm()
	return effects


func _run(effects: ShotEffects, seconds: float) -> void:
	for _i in ceili(seconds / FRAME):
		effects.shards._process(FRAME)
		effects.bolt_bursts._process(FRAME)


func test_a_shattered_zombie_bursts_into_pieces_that_fly_and_fade() -> void:
	var effects := _effects()
	assert_int(effects.shards.nodes_made()).is_equal(IceShatter.POOL)
	effects.shatter(Vector3(2, 0, 3), 1.0, 11)
	assert_int(effects.shards.live_count()).is_equal(IceShatter.PIECES)
	var starts: Array[Vector3] = []
	for node in effects.shards.live_nodes():
		assert_bool(node.visible).is_true()
		starts.append(node.position)
		# They begin inside the zombie's body: its height and a little round its axis.
		assert_float(node.position.y).is_between(0.0, IceShatter.BODY_HEIGHT)
		assert_float(Vector2(node.position.x - 2.0, node.position.z - 3.0).length()).is_less(
			IceShatter.START_RADIUS + 0.01
		)
	_run(effects, 0.3)
	var moved := 0
	var nodes := effects.shards.live_nodes()
	for i in nodes.size():
		if nodes[i].position.distance_to(starts[i]) > 0.3:
			moved += 1
	assert_int(moved).is_greater(IceShatter.PIECES / 2)
	# They end on the ground and are gone after their life, with no mesh made on the way.
	_run(effects, IceShatter.LIFE_SECONDS)
	assert_int(effects.shards.live_count()).is_equal(0)
	assert_int(effects.shards.nodes_made()).is_equal(IceShatter.POOL)


func test_the_pieces_land_on_the_ground_the_zombie_stood_on() -> void:
	var effects := _effects()
	effects.shatter(Vector3(0, 3.4, 0), 1.0, 5)
	_run(effects, IceShatter.LIFE_SECONDS * 0.6)
	for node in effects.shards.live_nodes():
		assert_float(node.position.y).is_greater_equal(3.4 - 0.001)


func test_the_same_zombie_breaks_the_same_way_on_every_client() -> void:
	var a := _effects()
	var b := _effects()
	a.shatter(Vector3(1, 0, 1), 1.0, 42)
	b.shatter(Vector3(1, 0, 1), 1.0, 42)
	var from_a := a.shards.live_nodes()
	var from_b := b.shards.live_nodes()
	for i in from_a.size():
		assert_vector(from_a[i].position).is_equal(from_b[i].position)
	var c := _effects()
	c.shatter(Vector3(1, 0, 1), 1.0, 43)
	assert_bool(c.shards.live_nodes()[0].position == from_a[0].position).is_false()


func test_a_few_kills_at_once_take_the_oldest_pieces_over_and_make_nothing_new() -> void:
	var effects := _effects()
	for i in 6:
		effects.shatter(Vector3(i, 0, 0), 1.0, i)
	assert_int(effects.shards.live_count()).is_equal(IceShatter.POOL)
	assert_int(effects.shards.nodes_made()).is_equal(IceShatter.POOL)


func test_the_ray_guns_burst_swells_to_the_splash_radius_in_its_colours_and_fades() -> void:
	var effects := _effects()
	var def := WeaponCatalog.get_def(&"ray_gun")
	effects.bolt_burst(Vector3(0, 1, 0), def)
	assert_int(effects.bolt_bursts.live_count()).is_equal(1)
	var slot := effects.bolt_bursts._live[0] as BoltBurst.Slot
	assert_float(slot.radius).is_equal(def.splash_radius)
	assert_bool(slot.shell_colour == def.bolt_halo_colour).is_true()
	_run(effects, BoltBurst.SECONDS * 0.8)
	assert_float(slot.shell.scale.x).is_greater(def.splash_radius * 0.7)
	assert_float(slot.shell.scale.x).is_less_equal(def.splash_radius)
	_run(effects, BoltBurst.SECONDS)
	assert_int(effects.bolt_bursts.live_count()).is_equal(0)
	assert_int(effects.bolt_bursts.nodes_made()).is_equal(BoltBurst.POOL)


func test_the_burst_is_blue_and_makes_no_light() -> void:
	var def := WeaponCatalog.get_def(&"ray_gun")
	for colour in [def.bolt_core_colour, def.bolt_halo_colour]:
		assert_float(colour.b).is_greater(colour.r)
	var effects := _effects()
	assert_array(effects.find_children("*", "Light3D", true, false)).is_empty()


func test_the_freeze_guns_burst_is_its_bloom_in_icy_colours() -> void:
	var effects := _effects()
	var def := WeaponCatalog.get_def(&"freeze_gun")
	effects.bolt_burst(Vector3.ZERO, def)
	var slot := effects.bolt_bursts._live[0] as BoltBurst.Slot
	assert_float(slot.radius).is_equal(def.splash_radius)
	assert_float(slot.shell_colour.b).is_greater(slot.shell_colour.r)


func test_the_bolt_is_drawn_in_the_weapons_colours_and_the_flare_in_its_own() -> void:
	var ray := ProjectileView.new()
	ray.state = ProjectileState.new(
		1, 1, WeaponCatalog.get_def(&"ray_gun"), Vector3.ZERO, Vector3.FORWARD
	)
	add_child(ray)
	auto_free(ray)
	var flare := ProjectileView.new()
	flare.state = ProjectileState.new(
		2, 1, WeaponCatalog.get_def(&"flare_gun"), Vector3.ZERO, Vector3.FORWARD
	)
	add_child(flare)
	auto_free(flare)
	var ray_core := _core_colour(ray)
	var flare_core := _core_colour(flare)
	assert_float(ray_core.b).is_greater(ray_core.r)
	assert_float(flare_core.r).is_greater(flare_core.b)
	var ray_halo := _halo_colour(ray)
	assert_float(ray_halo.b).is_greater(ray_halo.r)


func _core_colour(view: ProjectileView) -> Color:
	return _ball_colour(view.get_child(0) as MeshInstance3D)


func _halo_colour(view: ProjectileView) -> Color:
	return _ball_colour(view.get_child(1) as MeshInstance3D)


func _ball_colour(ball: MeshInstance3D) -> Color:
	return ((ball.mesh as SphereMesh).material as StandardMaterial3D).albedo_color
