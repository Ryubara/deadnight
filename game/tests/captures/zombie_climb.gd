extends Node
## A pack of the dead climbing the booth's ramp to a person on the roost (Deadnight #681), drawn by
## the real zombie views in the real night. Not part of the game. Arguments after `--`:
##   `--view=side`   (default) from the booth floor, looking at the ramp from its open side;
##   `--view=roost`  from the roost, looking down the ramp's top;
##   `--flat=1`      the dead walk with their heights left out, the way they did before the fix;
##   `--pack=N`      how many (default 8).
## Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/zombie_climb.tscn --fixed-fps 10
##  --write-movie out.png --quit-after 300 -- --view=side`.

const ROOST := Vector3(2.5, 3.95, 27.0)
const SPEED := 2.4
const FIRST_ID := 5000
const DOORS: Array[StringName] = [&"door_concession", &"door_booth"]

var _night: Night
var _pack: Array[int] = []
var _label: Label
var _view := "side"
var _flat := false
var _count := 8
var _clock := 0.0


## The navigation with the heights left out: what the zombies walked before.
class FlatPathing:
	extends NavmeshPathing

	func ground_offset() -> float:
		return NAN


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_view = _arg("view", "side")
	_flat = _arg("flat", "0") == "1"
	_count = int(_arg("pack", "8"))
	var tuning := SeatedNight.one_a_round()
	tuning.rounds.first_spawn_delay = 600.0
	_night = Night.new()
	_night.shoulder_camera = false
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 681, tuning)
	_night.server.rules.apply(RulesAction.grant_points(Night.PLAYER_ID, 100000))
	for door in DOORS:
		RulesFixture.buy(_night.server.rules, Night.PLAYER_ID, door)
	for _i in 30:
		await get_tree().physics_frame
	await NightFixture.settle_bake(_night)
	_night.server.body_of(Night.PLAYER_ID).teleport(ROOST)
	if _flat:
		_night.server.sim.pathing = FlatPathing.new(_night.world.map())
	_night.server.sim.zombies.clear()
	for i in _count:
		var at := Vector3(-4.8 + (float(i % 2) - 0.5), 0.0, 22.6 - float(i / 2) * 1.3)
		var zombie := _night.server.sim.spawn(FIRST_ID + i, SPEED, at)
		zombie.enter(ZombieBody.Mode.CHASE)
		_pack.append(zombie.id)
	_make_camera()
	_make_label()
	_night.ticked.connect(_on_tick)


func _make_camera() -> void:
	var camera := Camera3D.new()
	camera.fov = 70.0
	_night.add_child(camera)
	if _view == "roost":
		camera.look_at_from_position(Vector3(1.5, 5.3, 25.5), Vector3(-4.6, 3.4, 30.0))
	else:
		camera.look_at_from_position(Vector3(3.2, 2.1, 24.0), Vector3(-4.8, 1.9, 27.4))
	camera.make_current()
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
	var top := 0
	var highest := 0.0
	for id in _pack:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null:
			highest = maxf(highest, zombie.position.y)
			if zombie.position.y >= 3.5:
				top += 1
	_label.text = (
		"%s\n%.1f s   %d of %d on the roost   highest %.1f m"
		% [
			"BEFORE: heights left out" if _flat else "AFTER: the dead follow the floor",
			_clock,
			top,
			_pack.size(),
			highest
		]
	)


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback
