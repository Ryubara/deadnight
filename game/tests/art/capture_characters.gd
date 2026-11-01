extends Node3D
## Movie Maker capture of the committed characters (not a test): the player in the test room, and a
## row of the seven zombie variants, each playing a different clip, near LOD then far LOD.
## godot --path game --write-movie <dir>/frame.png --fixed-fps 15 --quit-after 120
##   res://tests/art/capture_characters.tscn

const ZOMBIE_DIR := "res://assets/characters/zombies/"
const ZOMBIE_SCALE := 1.3  # game scale (docs/design/style.md); each variant's height rides on top
const FAR_LOD_FROM := 18.0  # metres (docs/design/zombies.md, proposal)
# [variant, clip]
const ROW := [
	["walker", "Walk"],
	["greaser", "Idle"],
	["usher", "Idle_Attack"],
	["farmhand", "Run_Attack"],
	["runner", "Run"],
	["brute", "Punch"],
	["crawler", "Crawl"],
]
const ROW_Z := -3.0
const ROW_SPACING := 1.25
const PLAYER_AT := Vector3(4.0, 0.05, 14.0)
# [seconds, action, pressed]
const TIMELINE := [
	[0.8, "aim", true],
	[1.3, "Fire", true],
	[1.9, "Fire", true],
	[2.4, "Melee", true],
	[2.6, "aim", false],
	[3.0, "move_right", true],
	[3.7, "move_right", false],
	[3.9, "move_left", true],
	[4.6, "move_left", false],
	[8.0, "end", true],
]
# [from seconds, eye, target, fov]: the player close, the row close, then the row from past the
# far-LOD distance through a long lens (the far meshes, not the near ones, fill the frame).
const SHOTS := [
	[0.0, Vector3(9.0, 1.7, 16.5), Vector3(4.5, 1.0, 13.5), 50.0],
	[4.8, Vector3(0.0, 1.9, 2.2), Vector3(0.0, 0.8, ROW_Z), 60.0],
	[6.4, Vector3(-1.0, 3.0, 19.6), Vector3(0.0, 1.0, ROW_Z), 18.0],
]

var _ticks := 0
var _next := 0
var _camera: Camera3D
var _shot := -1
var _animation: PlayerAnimation


func _ready() -> void:
	var room: Node = load("res://world/test_room.tscn").instantiate()
	add_child(room)
	var player := room.get_node("Player") as Player
	player.capture_mouse = false
	player.teleport(PLAYER_AT)
	_animation = player.get_node("AnimationTree") as PlayerAnimation
	for pillar in ["PillarA", "PillarB", "PillarC"]:  # they stand between the far camera and the row
		room.get_node("Geometry/" + pillar).queue_free()
	for i in ROW.size():
		var zombie := (load(ZOMBIE_DIR + "zombie_%s.glb" % ROW[i][0]) as PackedScene).instantiate()
		zombie.name = ROW[i][0]
		zombie.scale = Vector3.ONE * ZOMBIE_SCALE
		zombie.position = Vector3((i - (ROW.size() - 1) * 0.5) * ROW_SPACING, 0.0, ROW_Z)
		add_child(zombie)
		var near := zombie.find_child("Zombie_Mesh", true, false) as GeometryInstance3D
		var far := zombie.find_child("Zombie_Far", true, false) as GeometryInstance3D
		near.visibility_range_end = FAR_LOD_FROM
		far.visibility_range_begin = FAR_LOD_FROM
		var anim := zombie.find_child("AnimationPlayer", true, false) as AnimationPlayer
		anim.get_animation(ROW[i][1]).loop_mode = Animation.LOOP_LINEAR
		anim.play(ROW[i][1])
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.make_current()


func _physics_process(_delta: float) -> void:
	_ticks += 1
	var now := _ticks / float(Engine.physics_ticks_per_second)
	while _shot + 1 < SHOTS.size() and SHOTS[_shot + 1][0] <= now:
		_shot += 1
		_camera.look_at_from_position(SHOTS[_shot][1], SHOTS[_shot][2])
		_camera.fov = SHOTS[_shot][3]
	while _next < TIMELINE.size() and TIMELINE[_next][0] <= now:
		var entry: Array = TIMELINE[_next]
		_next += 1
		if entry[1] == "end":
			get_tree().quit()
			return
		if entry[1] == "Fire":
			_animation.play_action(&"Fire")
			continue
		if entry[1] == "Melee":
			_animation.equip(&"Melee")
			continue
		if entry[2]:
			Input.action_press(entry[1])
		else:
			Input.action_release(entry[1])
