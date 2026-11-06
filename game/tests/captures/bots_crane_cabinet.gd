extends Node
## The prize crane breaks down and lands on two dead that stand at its next spot (Deadnight #1352):
## filmed from the eye of a bot 2 m east of the cabinet. On `main` the dead stay inside the wall,
## which every sight line and shot ends on (the line to the dead stops at the cabinet's face), and
## the bot fires at a box for as long as the film runs; with the fix the dead are put on the side of
## the one they swing at, seen at once and shot. The hand-ticked night draws no bodies, so capsules
## stand for them (the dead red, the person green) and a translucent box for the cabinet.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/bots_crane_cabinet.tscn --fixed-fps 10
## --write-movie out.png --quit-after 120 -- --label="after the fix"`.
## Arguments after `--`: `--label=TEXT` (the overlay's first line).

const SEED := 8
const LONG_BREAK := 3000.0
const SPOT := 2
const DEAD_AT: Array[Vector3] = [Vector3(-23.44, -0.05, -12.52), Vector3(-24.05, -0.05, -11.99)]
const PERSON_AT := Vector3(-24.0, 0.1, -10.8)
const BOT_AT := Vector3(-21.8, 0.1, -11.0)
const PLAYER_HEALTH := 1.0e6
## Ticks of the night run for every drawn frame (10 drawn frames a second).
const TICKS_PER_FRAME := 6
## Frames before the person plays the crane, and seconds after the cabinet lands before the bot
## fires.
const PLAY_AT_FRAME := 8
const FIRE_AFTER := 1.5

var _night: SeatedNight
var _bot: BotClient
var _person: HumanWalker
var _pair: Array[int] = []
var _capsules: Dictionary[int, MeshInstance3D] = {}
var _person_mesh: MeshInstance3D
var _cabinet: MeshInstance3D
var _line: MeshInstance3D
var _camera: Camera3D
var _label: Label
var _head := ""
var _frame := 0
var _landed_at := -1.0
var _ticks := 0


func _ready() -> void:
	_head = String(_parse_args().get("label", ""))
	var tuning := RulesFixture.tuning()
	tuning.health.max_health = PLAYER_HEALTH
	tuning.rounds.count_base = 2.0
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	tuning.crane.spin_seconds = 1.0
	tuning.crane.breakdown_seconds = 1.0
	tuning.crane.leave_chances = PackedFloat32Array([1.0])
	tuning.crane.safe_plays = 0
	_night = await SeatedNight.start(self, 2, tuning, SEED)
	_night.stand_still = true
	_night.hold_fire = true
	await _night.settle(60)
	_bot = _night.seat(1, BotProfile.regular(), SEED + 1)
	_person = _night.human(2)
	_night.server.body_of(1).teleport(BOT_AT)
	_night.server.body_of(2).teleport(PERSON_AT)
	_night.run(10)
	_night.start_round()
	var guard := 0
	while _night.server.sim.zombies.size() < 2 and guard < 3600:
		_night.tick()
		guard += 1
	var ids: Array = _night.server.sim.zombies.keys()
	ids.sort()
	_pair.assign(ids.slice(0, 2))
	for at in 2:
		var zombie: ZombieBody = _night.server.sim.zombies[_pair[at]]
		zombie.position = DEAD_AT[at]
		zombie.enter(ZombieBody.Mode.ATTACK)
	_night.server.sim.touch()
	_dress()


func _process(_delta: float) -> void:
	if _night == null or _line == null:
		return
	for _i in TICKS_PER_FRAME:
		_person.tick()
		_night.tick()
	_ticks += TICKS_PER_FRAME
	var rules := _night.server.rules
	if _frame == PLAY_AT_FRAME:
		rules.apply(RulesAction.grant_points(2, 10000))
		rules.apply(RulesAction.buy(2, &"crane_play"))
	if _landed_at < 0.0 and rules.crane.spot == SPOT:
		_landed_at = float(_ticks) / 60.0
	if _landed_at >= 0.0 and float(_ticks) / 60.0 - _landed_at >= FIRE_AFTER:
		_night.hold_fire = false
	_frame += 1
	_draw()


func _draw() -> void:
	var block := _night.world.crane_block
	_cabinet.visible = block.spot() >= 0
	if _cabinet.visible:
		_cabinet.global_transform = block.global_transform.translated_local(
			Vector3(0.0, CraneBlock.HEIGHT * 0.5, 0.0)
		)
	_person_mesh.global_position = _night.server.body_of(2).global_position + Vector3(0.0, 0.9, 0.0)
	var eye := _night.server.body_of(1).global_position + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	var alive := 0
	var sight := ""
	var mesh := ImmediateMesh.new()
	# The line leaves a hand's height below the eye, to the right of the view, so it is seen.
	var muzzle := eye + _camera.global_basis.x * 0.35 + Vector3(0.0, -0.45, 0.0)
	for id in _pair:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		var capsule := _capsules[id]
		capsule.visible = zombie != null and zombie.is_alive()
		if not capsule.visible:
			continue
		alive += 1
		capsule.global_position = zombie.position + Vector3(0.0, 0.9, 0.0)
		var chest := zombie.position + Vector3(0.0, 1.1, 0.0)
		var hit := float(_night.level.sight.call(eye, chest))
		var stop := chest if hit < 0.0 else eye + (chest - eye).normalized() * hit
		var green := Color(0.2, 1.0, 0.2) if hit < 0.0 else Color(1.0, 0.85, 0.1)
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_set_color(green)
		mesh.surface_add_vertex(muzzle)
		mesh.surface_set_color(green)
		mesh.surface_add_vertex(stop)
		if hit >= 0.0:
			mesh.surface_set_color(Color(1.0, 0.1, 0.1))
			mesh.surface_add_vertex(stop)
			mesh.surface_set_color(Color(1.0, 0.1, 0.1))
			mesh.surface_add_vertex(chest)
		mesh.surface_end()
		sight += "  dead %d: %s" % [id, "CLEAR" if hit < 0.0 else "BLOCKED at %.1f m" % hit]
	_line.mesh = mesh
	_label.text = (
		"%s\nt = %4.1f s   crane at spot %d   the two dead alive: %d   bot's fire %s\n%s"
		% [
			_head,
			float(_ticks) / 60.0,
			_night.server.rules.crane.spot,
			alive,
			"HELD" if _night.hold_fire else "OPEN",
			"bot's line to " + sight if sight != "" else "both dead are down"
		]
	)


func _dress() -> void:
	var light := OmniLight3D.new()
	light.position = Vector3(-22.0, 6.0, -9.0)
	light.omni_range = 30.0
	light.light_energy = 5.0
	add_child(light)
	_camera = Camera3D.new()
	add_child(_camera)
	# The bot's eye, looking down its line at the middle of the two dead.
	_camera.position = BOT_AT + Vector3(0.0, BotLevel.EYE_HEIGHT, 0.0)
	_camera.look_at(Vector3(-23.7, 0.9, -12.0))
	_camera.fov = 100.0
	_camera.make_current()
	_cabinet = _mesh(BoxMesh.new(), Color(1.0, 0.45, 0.1, 0.45))
	(_cabinet.mesh as BoxMesh).size = Vector3(PrizeCrane.WIDTH, CraneBlock.HEIGHT, PrizeCrane.DEPTH)
	for id in _pair:
		var capsule := _mesh(CapsuleMesh.new(), Color(0.9, 0.1, 0.1, 1.0))
		(capsule.mesh as CapsuleMesh).radius = 0.3
		(capsule.mesh as CapsuleMesh).height = 1.7
		_capsules[id] = capsule
	_person_mesh = _mesh(CapsuleMesh.new(), Color(0.3, 0.9, 0.3, 1.0))
	(_person_mesh.mesh as CapsuleMesh).radius = 0.35
	(_person_mesh.mesh as CapsuleMesh).height = 1.8
	_line = MeshInstance3D.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	_line.material_override = line_material
	add_child(_line)
	var layer := CanvasLayer.new()
	add_child(layer)
	# A map from above beside the bot's view: the cabinet's footprint and where the dead stand.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.position = Vector2(1920.0 - 560.0, 1080.0 - 560.0)
	container.size = Vector2(540.0, 540.0)
	layer.add_child(container)
	var inset := SubViewport.new()
	inset.size = Vector2i(540, 540)
	container.add_child(inset)
	var above := Camera3D.new()
	above.projection = Camera3D.PROJECTION_ORTHOGONAL
	above.size = 7.0
	above.position = Vector3(-23.3, 12.0, -11.9)
	above.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	inset.add_child(above)
	var frame := ColorRect.new()
	frame.color = Color(0.0, 0.0, 0.0, 0.0)
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.substr(2).split("=", true, 1)
			found[parts[0]] = parts[1]
	return found
