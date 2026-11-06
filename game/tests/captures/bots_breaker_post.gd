extends Node
## A Roam bot walking from the west of the lot to the east midway's barricade stand, past the
## booth's breaker post (Deadnight #1325), filmed from the north-west of the booth's corner. The
## bot's body is not drawn in a hand-ticked night, so a capsule follows it; the post is outlined and
## the place it walks to is a yellow post. The text says what the bot's legs are doing.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/bots_breaker_post.tscn --fixed-fps 10
## --write-movie out.png --quit-after 250 -- --seed=9 --label="after the fix"`.
## Arguments after `--`: `--seed=N` (the bot's own stream, the ladder's jitter is drawn from it),
## `--label=TEXT` (the first line of the overlay).

const WEST := Vector3(-3.8, 0.1, 20.6)
const STAND := Vector3(12.5, 0.4, 31.6)
const POST := Vector3(5.6, 0.75, 21.5)
const POST_SIZE := Vector3(0.8, 1.5, 0.5)
## Ticks of the night run for every drawn frame (10 drawn frames a second).
const TICKS_PER_FRAME := 6
const LONG_BREAK := 3000.0

var _night: SeatedNight
var _bot: BotClient
var _marker: MeshInstance3D
var _label: Label
var _head := ""
var _ticks := 0
var _still := 0


func _ready() -> void:
	var args := _parse_args()
	_head = String(args.get("label", ""))
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	_night = await SeatedNight.start(self, 1, tuning, 8)
	_night.open_door(&"door_concession")
	_night.open_door(&"door_booth")
	await _night.settle(60)
	await _night.settle_doors()
	_bot = _night.seat(1, BotProfile.regular(), int(args.get("seed", 9)))
	_night.server.body_of(1).teleport(WEST)
	_night.run(2)
	(_bot.brain as BotFightBrain)._roam.spot = STAND
	_dress()


func _process(_delta: float) -> void:
	if _night == null or _bot == null:
		return
	_night.run(TICKS_PER_FRAME)
	_ticks += TICKS_PER_FRAME
	var body := _night.server.body_of(1)
	_marker.global_position = body.global_position + Vector3(0.0, 0.9, 0.0)
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	_still = _still + TICKS_PER_FRAME if speed < SoakWatch.STANDING else 0
	_label.text = (
		(
			"%s\nt = %4.1f s   note %-10s speed %.1f m/s   standing %.1f s\n"
			+ "ladder rung %d   path %s   goal %s"
		)
		% [
			_head,
			float(_ticks) / 60.0,
			_bot.intent.note,
			speed,
			float(_still) / 60.0,
			_bot.legs.stuck.rung,
			BotPath.Status.keys()[_bot.legs.path.last_status],
			_bot.intent.goal.snappedf(0.1)
		]
	)


func _dress() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(5.0, 9.0, 18.0)
	light.omni_range = 40.0
	light.light_energy = 6.0
	add_child(light)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-1.5, 4.5, 14.5)
	camera.look_at(Vector3(5.0, 0.5, 21.5))
	camera.fov = 50.0
	camera.make_current()
	_marker = _mesh(CapsuleMesh.new(), Color(0.2, 0.8, 1.0, 1.0))
	(_marker.mesh as CapsuleMesh).radius = 0.35
	(_marker.mesh as CapsuleMesh).height = 1.8
	var post := BoxMesh.new()
	post.size = POST_SIZE * 1.04
	_mesh(post, Color(1.0, 0.45, 0.1, 0.55)).global_position = POST
	var stand := CylinderMesh.new()
	stand.top_radius = 0.15
	stand.bottom_radius = 0.15
	stand.height = 6.0
	_mesh(stand, Color(1.0, 0.9, 0.1, 1.0)).global_position = STAND + Vector3(0.0, 3.0, 0.0)
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
