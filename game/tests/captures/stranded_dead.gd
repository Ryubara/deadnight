extends Node3D
## Top-down picture of where the dead stand 40 s after the concession door is bought in a night
## stepped by hand with no physics frame between its ticks (what the shopping soak did; #591): the
## navigation map still has the door shut. Not part of the game. Arguments after `--`:
##   `--out=<folder>`  where to save the picture.
## Red are the dead, white the player; the door's room is the concession (z -4 to 8).

const SEED := 7
const TICKS := 2400

var _night: Night
var _out := ""


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.substr(6)
	var tuning: RulesTuning = load(GameRules.DEFAULT_TUNING_PATH).duplicate(true)
	tuning.rounds.count_base = 30.0
	tuning.rounds.count_linear = 0.0
	tuning.rounds.count_quadratic = 0.0
	tuning.rounds.alive_cap_start = 30.0
	tuning.rounds.alive_cap_max = 30.0
	tuning.rounds.spawn_interval_start = 1.0
	tuning.rounds.spawn_interval_min = 1.0
	tuning.health.max_health *= 100.0
	_night = await NightFixture.start(self, Night.Mode.MANUAL, tuning, SEED)
	NightFixture.run(_night, 30)
	var door := &"door_concession"
	_night.server.rules.apply(RulesAction.grant_points(1, 20000))
	_night.player().teleport(_night.world.door_points(door)[0] + Vector3(0.0, 0.1, -2.0))
	NightFixture.run(_night, 6)
	var command := NightCommand.new()
	command.use = true
	NightFixture.run(_night, 1, command)
	# Away from the door, on the field, where the dead go for it.
	_night.player().teleport(Vector3(6.0, 0.1, -22.0))
	_night.server.rules.apply(RulesAction.skip_break())
	# No physics frame in this loop: the navigation server never takes the door's mesh in.
	NightFixture.run(_night, TICKS)
	_show()


func _show() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 56.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 80, -6), Vector3(0, 0, -6), Vector3(0, 0, -1))
	camera.current = true
	for node in _night.world.greybox.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if box.global_position.y - box.size.y * 0.5 > 3.0:
			box.visible = false
	var count := 0
	var at_wall := 0
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		_dot(zombie.position, Color(1, 0.1, 0.1), 0.7)
		count += 1
		if zombie.position.z > -4.0 and zombie.position.z < 8.0:
			at_wall += 1
	_dot(_night.server.body_of(1).global_position, Color.WHITE, 1.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(24, 16)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)
	label.text = (
		(
			"%d dead 40 s after the concession door is bought, %d of them inside it\n"
			+ "(a night stepped with no physics frame: the map never takes the door in)"
		)
		% [count, at_wall]
	)
	layer.add_child(label)
	print("DEAD %d inside the concession %d" % [count, at_wall])
	for zombie: ZombieBody in _night.server.sim.zombies.values():
		print("  Z%d %s mode %d" % [zombie.id, zombie.position, zombie.mode])
	for _i in 6:
		await get_tree().process_frame
	if _out != "":
		get_viewport().get_texture().get_image().save_png("%s/dead.png" % _out)
	_night.queue_free()
	await get_tree().physics_frame
	get_tree().quit()


func _dot(at: Vector3, color: Color, radius: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.material_override = material
	instance.position = Vector3(at.x, 3.0, at.z)
	add_child(instance)
