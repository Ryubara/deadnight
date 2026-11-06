extends Node
## A person walks at a Roam bot that looks about at the stand of the west midway's barricade, and
## the bot gives way (Deadnight #1339). On `main` it is walked west at a run onto the scrap of the
## walking mesh that only the dead walk (red) and into the corner of the fence and the pocket's
## wall, and stands there; with the fix it steps aside to ground it can walk. Filmed from the
## south-east of the corner. The bodies are not drawn in a hand-ticked night, so capsules follow
## them (the bot cyan, the person green), and the text says what the bot's legs are doing.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/bots_west_corner.tscn --fixed-fps 10
## --write-movie out.png --quit-after 200 -- --seed=9 --label="after the fix"`.
## Arguments after `--`: `--seed=N` (the bot's own stream), `--label=TEXT` (the overlay's first
## line).

const STAND := Vector3(-12.3, 0.1, 32.3)
const PERSON_FROM := Vector3(-6.0, 0.1, 32.3)
## The scrap the cut of `mid_w`'s boards leaves (x -15.25 to -13.75, z 31.0 to 32.25).
const SCRAP_CENTRE := Vector3(-14.5, 0.05, 31.625)
const SCRAP_SIZE := Vector3(1.5, 0.1, 1.25)
const CORNER_BOX := Rect2(-15.9, 31.4, 1.3, 1.5)
const DOORS: Array[StringName] = [
	&"door_concession", &"door_booth", &"door_back_lot", &"door_yard", &"door_road"
]
## Ticks of the night run for every drawn frame (10 drawn frames a second).
const TICKS_PER_FRAME := 6
const LONG_BREAK := 3000.0

var _night: SeatedNight
var _bot: BotClient
var _person: HumanWalker
var _marker: MeshInstance3D
var _other: MeshInstance3D
var _label: Label
var _head := ""
var _ticks := 0
var _still := 0
var _in_corner := 0


func _ready() -> void:
	var args := _parse_args()
	_head = String(args.get("label", ""))
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	_night = await SeatedNight.start(self, 2, tuning, 8)
	for door in DOORS:
		_night.open_door(door)
	await _night.settle(60)
	await _night.settle_doors()
	_bot = _night.seat(1, BotProfile.regular(), int(args.get("seed", 9)))
	_person = _night.human(2)
	_night.server.body_of(1).teleport(STAND)
	_night.server.body_of(2).teleport(PERSON_FROM)
	_night.run(2)
	(_bot.brain as BotFightBrain)._roam.spot = STAND
	_person.goto(STAND + Vector3(0.0, 0.0, 0.2))
	_dress()


func _process(_delta: float) -> void:
	if _night == null or _bot == null:
		return
	for _i in TICKS_PER_FRAME:
		_person.tick()
		_night.tick()
		if _person.arrived():
			_person.stop()
	_ticks += TICKS_PER_FRAME
	var body := _night.server.body_of(1)
	_marker.global_position = body.global_position + Vector3(0.0, 0.9, 0.0)
	_other.global_position = _night.server.body_of(2).global_position + Vector3(0.0, 0.9, 0.0)
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	_still = _still + TICKS_PER_FRAME if speed < SoakWatch.STANDING else 0
	if CORNER_BOX.has_point(Vector2(body.global_position.x, body.global_position.z)):
		_in_corner += TICKS_PER_FRAME
	_label.text = (
		(
			"%s\nt = %4.1f s   note %-10s speed %.1f m/s   standing %.1f s   in the corner %.1f s\n"
			+ "ladder rung %d   path %s   at (%.1f, %.1f)"
		)
		% [
			_head,
			float(_ticks) / 60.0,
			_bot.intent.note,
			speed,
			float(_still) / 60.0,
			float(_in_corner) / 60.0,
			_bot.legs.stuck.rung,
			BotPath.Status.keys()[_bot.legs.path.last_status],
			body.global_position.x,
			body.global_position.z
		]
	)


func _dress() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(-10.0, 9.0, 26.0)
	light.omni_range = 40.0
	light.light_energy = 6.0
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-9.5, 7.5, 25.5)
	camera.look_at(Vector3(-12.5, 0.0, 32.0))
	camera.fov = 50.0
	camera.make_current()
	_marker = _mesh(CapsuleMesh.new(), Color(0.2, 0.8, 1.0, 1.0))
	(_marker.mesh as CapsuleMesh).radius = 0.35
	(_marker.mesh as CapsuleMesh).height = 1.8
	_other = _mesh(CapsuleMesh.new(), Color(0.3, 0.9, 0.3, 1.0))
	(_other.mesh as CapsuleMesh).radius = 0.35
	(_other.mesh as CapsuleMesh).height = 1.8
	var scrap := BoxMesh.new()
	scrap.size = SCRAP_SIZE
	_mesh(scrap, Color(1.0, 0.15, 0.1, 0.6)).global_position = SCRAP_CENTRE
	var stand := CylinderMesh.new()
	stand.top_radius = 0.1
	stand.bottom_radius = 0.1
	stand.height = 5.0
	_mesh(stand, Color(1.0, 0.9, 0.1, 1.0)).global_position = STAND + Vector3(0.0, 2.5, 0.0)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _mesh(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = material
	add_child(node)
	return node


func _parse_args() -> Dictionary:
	var found := {}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts := argument.substr(2).split("=", true, 1)
			found[parts[0]] = parts[1]
	return found
