extends Node
## The dead climbing in over a window's sill (#915), drawn by the real zombie views in the real
## night, from where a player stands inside. Not part of the game. Arguments after `--`:
##   `--map=lot|small`   (default lot);
##   `--id=nw`           the entry whose boards are down (default: the map's first);
##   `--pack=N`          how many dead (default 3);
##   `--view=front|side|outside` from inside facing the window (default), from beside it, or from
##                       outside behind the dead.
## Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/window_climb.tscn --fixed-fps 10
##  --write-movie out.png --quit-after 150 -- --map=lot --id=nw`.

const SCENES := {
	"small": "res://world/smallmap/smallmap_greybox.tscn",
	"lot": "res://world/drive_in_greybox.tscn",
}
const FIRST_ID := 6000
const SPEED := 1.6
const STAND := 3.4
const OUT_START := 5.0
const SPACING := 1.5

var _night: Night
var _id: StringName
var _pack: Array[int] = []
var _label: Label
var _clock := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var map := _arg("map", "lot")
	var tuning := SeatedNight.one_a_round()
	tuning.rounds.first_spawn_delay = 600.0
	_night = Night.new()
	_night.shoulder_camera = false
	_night.scene = load(SCENES[map]) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 915, tuning)
	_id = StringName(_arg("id", String(_night.world.barricade_ids()[0])))
	var barricade := _night.world.barricade(_id)
	_night.server.rules.barricades.boards[_id] = 0
	for id in _night.world.barricade_ids():
		_night.world.barricade(id).set_boards(0 if id == _id else 5, false)
	for _i in 30:
		await get_tree().physics_frame
	var inward := barricade.inward()
	var stand := barricade.standing_point(STAND)
	var player := _night.server.body_of(Night.PLAYER_ID)
	player.teleport(stand + Vector3.UP * 0.05)
	_night.server.sim.zombies.clear()
	var sideways := inward.cross(Vector3.UP)
	for i in int(_arg("pack", "3")):
		var offset := (float(i) - 1.0) * SPACING * 0.5
		var at := (
			barricade.global_position
			- inward * (OUT_START + float(i) * SPACING)
			+ sideways * offset
		)
		var zombie := _night.server.sim.spawn(FIRST_ID + i, SPEED, at, 0.0, null, _id)
		zombie.enter(ZombieBody.Mode.CHASE)
		_pack.append(zombie.id)
	_make_camera(barricade)
	_make_label()
	_night.ticked.connect(_on_tick)


func _make_camera(barricade: Barricade) -> void:
	var camera := Camera3D.new()
	camera.fov = 70.0
	_night.add_child(camera)
	var inward := barricade.inward()
	var sideways := inward.cross(Vector3.UP)
	var base := barricade.global_position
	var view := _arg("view", "front")
	if view == "side":
		camera.look_at_from_position(
			base + inward * 1.2 + sideways * 3.4 + Vector3.UP * 1.5, base + Vector3.UP * 1.0
		)
	elif view == "outside":
		camera.look_at_from_position(
			base - inward * 3.0 + sideways * 1.4 + Vector3.UP * 1.65, base + Vector3.UP * 1.0
		)
	else:
		camera.look_at_from_position(
			base + inward * 2.4 + Vector3.UP * 1.65, base - inward * 0.6 + Vector3.UP * 0.9
		)
	camera.make_current()
	# The throttle poses only the dead the camera it is given can see: with the night's own camera,
	# which looks elsewhere, every zombie here stayed frozen on its first pose.
	_night.view.horde.throttle.camera = camera
	# The night's own camera may take over for a frame; take it back once the first frames ran.
	get_tree().create_timer(0.5).timeout.connect(camera.make_current)


func _make_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 16)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _on_tick() -> void:
	_clock += Night.STEP
	var climbing := 0
	var highest := 0.0
	for id in _pack:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null:
			highest = maxf(highest, zombie.position.y)
			if zombie.climbing:
				climbing += 1
	_label.text = "%s  %.1f s   %d climbing   highest %.2f m" % [_id, _clock, climbing, highest]


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback
