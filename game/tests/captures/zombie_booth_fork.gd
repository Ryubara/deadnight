extends Node
## A crawler beside the drive-in's west ticket booth, in the real night (#1347). Not part of the
## game. Arguments after `--`:
##   `--view=player` the player's own camera: the player stands in the plaza and looks at the
##     crawler where the soak's nights left it, (-8.5, 45.2). The crawler is held still for the
##     picture (a person near it would be its target and it would come), so this shows where it
##     stands and what a person sees from the plaza, not the stall.
##   `--view=top` a camera over the plaza: the crawler is set down there with the only person far
##     north in the field, as in the stalled nights, and each half second of its walk is a dot,
##     red at the start and green at the end. On the code before the fix the dots stay in a clump
##     at the booth's west face; with it they run north to the plaza's gate.
##   `--seconds=S` (default 40, top only).
## Movie Maker: `--write-movie <folder>/<name>.png --fixed-fps 10 --quit-after N`.

const SPOT := Vector3(-8.5, 0.0, 45.2)
const FAR_PERSON := Vector3(0.0, 0.1, -33.0)
const NEAR_PERSON := Vector3(-12.5, 0.1, 53.0)
const CRAWL_SPEED := 1.2
## Ticks the night is run between two drawn frames (60 Hz night, 10 frames a second).
const TICKS_PER_FRAME := 6
const SETTLE_FRAMES := 120
const DOT_EVERY_TICKS := 30

var _args := {}
var _night: Night
var _crawler: ZombieBody
var _dots: Array[MeshInstance3D] = []


func _ready() -> void:
	_args = _parse_args()
	var top := String(_args.get("view", "player")) == "top"
	var tuning := NightFixture.only_tuning(&"crawler")
	tuning.rounds.count_base = 1.0
	tuning.rounds.count_linear = 0.0
	tuning.rounds.count_quadratic = 0.0
	tuning.rounds.first_spawn_delay = 0.1
	tuning.health.max_health *= 100.0
	_night = Night.new()
	_night.shoulder_camera = true
	add_child(_night)
	await _night.start(Night.Mode.AUTOPILOT, 5, tuning)
	_night.mode = Night.Mode.MANUAL
	_night.server.rules.apply(RulesAction.grant_points(1, 100000))
	for item in _night.server.rules.tuning.economy.items:
		if item.kind == ShopItem.Kind.DOOR:
			RulesFixture.buy(_night.server.rules, 1, item.id)
	await NightFixture.settle_bake(_night)
	for _i in SETTLE_FRAMES:
		await get_tree().physics_frame
	_night.player().teleport(FAR_PERSON if top else NEAR_PERSON)
	var id := NightFixture.first_of_type(_night, &"crawler")
	_crawler = _night.server.sim.zombies[id]
	_crawler.position = SPOT
	_crawler.gate_id = &""
	_crawler.speed = CRAWL_SPEED
	_crawler.enter(ZombieBody.Mode.CHASE)
	_night.server.sim.touch()
	if top:
		await _film_from_above()
	else:
		await _film_from_the_player()
	get_tree().quit()


func _film_from_the_player() -> void:
	# Held where the soak left it; the view looks at it from the plaza's south-west.
	_night.server.sim.set_status(_crawler.id, 1, true, 1.0)
	var command := NightCommand.new()
	var to_spot := SPOT - NEAR_PERSON
	command.look_along(atan2(-to_spot.x, -to_spot.z), -0.12)
	for _i in 12:
		NightFixture.run(_night, TICKS_PER_FRAME, command)
		await get_tree().process_frame


func _film_from_above() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 34.0
	add_child(camera)
	camera.look_at_from_position(
		Vector3(-6.0, 80.0, 44.0), Vector3(-6.0, 0.0, 44.0), Vector3(0, 0, -1)
	)
	camera.current = true
	for node in _night.world.greybox.find_children("*", "CSGBox3D", true, false):
		var box := node as CSGBox3D
		if box.global_position.y - box.size.y * 0.5 > 3.0:
			box.visible = false
	var seconds := float(_args.get("seconds", 40.0))
	var ticks := 0
	var last_z := _crawler.position.z
	while float(ticks) / 60.0 < seconds:
		NightFixture.run(_night, TICKS_PER_FRAME)
		ticks += TICKS_PER_FRAME
		if ticks % DOT_EVERY_TICKS == 0:
			_dot(_crawler.position, float(ticks) / 60.0 / seconds)
		await get_tree().process_frame
		last_z = _crawler.position.z
	print("CRAWLER ended at ", _crawler.position, " after ", seconds, " s")
	for _i in 4:
		await get_tree().process_frame


func _dot(at: Vector3, along: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.1, 0.1).lerp(Color(0.1, 1.0, 0.2), along)
	var instance := MeshInstance3D.new()
	instance.mesh = sphere
	instance.material_override = material
	instance.position = Vector3(at.x, 3.0 + 0.01 * _dots.size(), at.z)
	add_child(instance)
	_dots.append(instance)


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
