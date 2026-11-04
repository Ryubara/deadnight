extends Node
## The dead tearing a window's boards (#997), drawn by the real zombie views in the real night,
## from the eye of a person standing at the repair spot inside. Not part of the game. Arguments
## after `--`:
##   `--map=lot|small`   (default small);
##   `--id=start_1`      the entry (default: the map's first);
##   `--before`          the dead may tear from anywhere in front of the gap (the old rule);
##   `--crowd=6`         how many dead come, spread over 4.8 m along the wall (default 6);
##   `--boards=2`        boards kept up across it (default 2: the dead are seen through the gaps);
##   `--stand=0.4`       metres along the wall the person stands, 1.4 m in (default 0.4).
## Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/window_tear.tscn --fixed-fps 10
##  --write-movie out.png --quit-after 120 -- --map=small --id=start_1`.

const SCENES := {
	"small": "res://world/smallmap/smallmap_greybox.tscn",
	"lot": "res://world/drive_in_greybox.tscn",
}
const FIRST_ID := 6000
const SPEED := 1.6
const OUT_START := 5.0
const EYE_HEIGHT := 1.55

var _night: Night
var _id: StringName
var _pack: Array[int] = []
var _label: Label
var _clock := 0.0
var _barricade: Barricade
var _boards := 2


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tuning := SeatedNight.one_a_round()
	tuning.rounds.first_spawn_delay = 600.0
	_night = Night.new()
	_night.shoulder_camera = false
	_night.scene = load(SCENES[_arg("map", "small")]) as PackedScene
	add_child(_night)
	await _night.start(Night.Mode.MANUAL, 997, tuning)
	_id = StringName(_arg("id", String(_night.world.barricade_ids()[0])))
	_barricade = _night.world.barricade(_id)
	_boards = int(_arg("boards", "2"))
	for id in _night.world.barricade_ids():
		_night.world.barricade(id).set_boards(_boards, false)
		_night.server.rules.barricades.boards[id] = _boards
	if has_flag("before"):
		for gate: ZombieGate in _night.server.sim.gates.values():
			gate.clear_half = INF
	for _i in 30:
		await get_tree().physics_frame
	var inward := _barricade.inward()
	var sideways := inward.cross(Vector3.UP)
	var stand := (
		_barricade.standing_point(NightWorld.REPAIR_SPOT) + sideways * float(_arg("stand", "0.4"))
	)
	_night.server.body_of(Night.PLAYER_ID).teleport(stand + Vector3.UP * 0.05)
	_night.server.sim.zombies.clear()
	var crowd := int(_arg("crowd", "6"))
	for i in crowd:
		var along := 4.8 * (float(i) / float(crowd - 1) - 0.5)
		var at := _barricade.global_position - inward * OUT_START + sideways * along
		var zombie := _night.server.sim.spawn(FIRST_ID + i, SPEED, at, 0.0, null, _id)
		zombie.enter(ZombieBody.Mode.CHASE)
		_pack.append(zombie.id)
	_make_camera(stand)
	_make_label()
	_night.ticked.connect(_on_tick)


func has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has("--%s" % name)


func _make_camera(stand: Vector3) -> void:
	var camera := Camera3D.new()
	camera.fov = 70.0
	_night.add_child(camera)
	var eye := stand + Vector3.UP * EYE_HEIGHT
	camera.look_at_from_position(eye, _barricade.global_position + Vector3.UP * 1.1)
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
	# The boards are kept up so the dead go on tearing at the same spot.
	_night.server.rules.barricades.boards[_id] = _boards
	_barricade.set_boards(_boards, false)
	var sideways := _barricade.inward().cross(Vector3.UP)
	var text := "%s  %.1f s  opening +-%.2f m" % [_id, _clock, _barricade.clear_half]
	for id in _pack:
		var zombie: ZombieBody = _night.server.sim.zombies.get(id)
		if zombie != null:
			var along := (zombie.position - _barricade.centre()).dot(sideways)
			text += "\n%s at %+.2f m%s" % [id, along, "  TEARING" if zombie.tearing else ""]
	_label.text = text


func _arg(name: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.substr(name.length() + 3)
	return fallback
