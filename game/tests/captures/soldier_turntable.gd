extends Node3D
## Capture for #895: the dressed Soldier turned all the way round, one row per look, in one sheet.
## Each look is a preset (`10`) or a preset with parts and colours changed
## (`10:torso=jacket,neck=scarf/primary=5`). The pose is the menu's (`--pose=menu`: the idle with
## the showcase weapon in the hands, `MenuHero`, the night's hold) or a clip at a time
## (`--pose=Run_Gun@0.3`), and `--zoom` frames the whole body, the head and neck, or the hands.
## The camera looks a little down, as the menu's does. Not part of the game.
##
##     gds godot -- --path game res://tests/captures/soldier_turntable.tscn --resolution 1600x900
##         -- --out=<folder>/sheet.png --looks=10,0,3:torso=tank [--pose=menu] [--weapon=rifle]
##         [--turns=8] [--zoom=body|head|hands] [--cell=240] [--probe]
##
## `--weapon=none` stands the soldier in the pose with empty hands. `--probe` marks in red every
## place where the eye sees through the body (`BodyFit.see_through` all over it) and prints them.

const STEP := 1.0 / 30.0
## Frames of the pose before the first shot, and between two turns (the hand pose settles).
const SETTLE := 20
const TURN_FRAMES := 3
## What each zoom frames: the height looked at (metres, the game's scale) and the half height shown.
const ZOOMS := {
	"body": [0.78, 0.95],
	"head": [1.3, 0.42],
	"hands": [1.05, 0.42],
}
const ELEVATION := 0.12

var _out := "user://soldier_turntable.png"
var _looks: Array[String] = ["10"]
var _pose := "menu"
var _weapon := &"rifle"
var _turns := 8
var _zoom := "body"
var _cell := 240
var _probe := false
var _camera: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1) if arg.contains("=") else ""
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--looks="):
			_looks.assign(arg.substr(8).split(","))
		elif arg.begins_with("--pose="):
			_pose = value
		elif arg.begins_with("--weapon="):
			_weapon = StringName(value)
		elif arg.begins_with("--turns="):
			_turns = int(value)
		elif arg.begins_with("--zoom="):
			_zoom = value
		elif arg.begins_with("--cell="):
			_cell = int(value)
		elif arg == "--probe":
			_probe = true
	_stage()
	var sheet := Image.create(_cell * _turns, _cell * _looks.size(), false, Image.FORMAT_RGBA8)
	for row in _looks.size():
		var hero := MenuHero.new()
		add_child(hero)
		var look := parse_look(_looks[row])
		if _weapon == &"none":
			hero.look = look
			hero.model = CharacterAssembler.assemble(look, 0)
			hero.model.scale = Vector3.ONE * MenuHero.MODEL_SCALE
			hero.add_child(hero.model)
		else:
			hero.show_look(look, _weapon)
		var player := hero.model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clip := _pose.get_slice("@", 0)
		if _pose != "menu" and not player.has_animation(clip):
			ClipFit.add_player_clips(player)  # the sprint, strike, revive... clips of the player's files
		if _pose != "menu" and player.has_animation(clip):
			hero.model.find_child("Skeleton3D", true, false).reset_bone_poses()
			player.play(clip)
			player.seek(float(_pose.get_slice("@", 1)) if _pose.contains("@") else 0.0, true)
		for i in SETTLE:
			hero.advance(STEP if _pose == "menu" else 0.0)
			await get_tree().process_frame
		if _probe:
			await _mark_see_through(hero)
		for turn in _turns:
			hero.rotation.y = TAU * turn / _turns
			for i in TURN_FRAMES:
				hero.advance(0.0)
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var shot := get_viewport().get_texture().get_image()
			var side := mini(shot.get_width(), shot.get_height())
			var square := shot.get_region(
				Rect2i((shot.get_width() - side) / 2, (shot.get_height() - side) / 2, side, side)
			)
			square.resize(_cell, _cell, Image.INTERPOLATE_LANCZOS)
			square.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(square, Rect2i(0, 0, _cell, _cell), Vector2i(turn * _cell, row * _cell))
		print(
			"[turntable] ",
			_looks[row],
			" shown: ",
			SoldierLook.visible_meshes(hero.look.to_soldier_look())
		)
		remove_child(hero)
		hero.free()
	sheet.save_png(_out)
	print("[turntable] ", _out)
	get_tree().quit()


## Marks with red dots, drawn over everything, each place the eye sees through the body.
func _mark_see_through(hero: MenuHero) -> void:
	var skeleton := hero.model.find_child("Skeleton3D", true, false) as Skeleton3D
	var fit := BodyFit.new(self, skeleton)
	fit.read_pose()
	await fit.prepare(fit.triangles())
	var box := BodyFit.bounds_of(fit.triangles())
	var seen := fit.see_through(box.get_center(), box.size.length() / 2.0, 41, 16)
	fit.free_bodies()
	print("[turntable] see-through: ", seen.size(), " ", seen.slice(0, 12))
	var dot := SphereMesh.new()
	dot.radius = 0.02
	dot.height = 0.04
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.1, 0.1)
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.no_depth_test = true
	for p in seen:
		var mark := MeshInstance3D.new()
		mark.mesh = dot
		mark.material_override = red
		skeleton.add_child(mark)
		mark.global_position = p


## `10`, or `10:slot=part,slot=part/channel=index,...`: a preset, then parts and colours changed.
static func parse_look(spec: String) -> CharacterLook:
	var look := CharacterLook.from_preset(int(spec.get_slice(":", 0)))
	if not spec.contains(":"):
		return look
	var rest := spec.get_slice(":", 1)
	var groups := rest.split("/")
	for pair in groups[0].split(",", false):
		look.parts[StringName(pair.get_slice("=", 0))] = StringName(pair.get_slice("=", 1))
	if groups.size() > 1:
		for pair in groups[1].split(",", false):
			look.colours[StringName(pair.get_slice("=", 0))] = int(pair.get_slice("=", 1))
	return look


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.68)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	key.light_energy = 1.1
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	rim.light_energy = 0.4
	add_child(rim)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var zoom: Array = ZOOMS.get(_zoom, ZOOMS.body)
	_camera.size = 2.0 * float(zoom[1])
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var target := Vector3(0, float(zoom[0]), 0)
	# The soldier faces +Z; the camera stands in front of it, a little above.
	_camera.position = target + Vector3(0, sin(ELEVATION), cos(ELEVATION)) * 6.0
	add_child(_camera)
	_camera.look_at(target)
	_camera.make_current()
