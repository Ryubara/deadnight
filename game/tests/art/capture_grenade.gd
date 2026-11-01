## Capture of the grenade art in Godot (not a test; needs a window, not --headless): the Soldier
## plays each grenade clip with the grenade on his hand bone (`HOLD_GRENADE` on `Index1.R`),
## the pin hidden after `pin_out`, the spoon after `spoon_off`, the grenade after `release`; the
## last row is the grenade, its far level, and the pin and spoon pulled off their nodes.
##
##     godot --path game -s res://tests/art/capture_grenade.gd -- --out <scratch>/godot-grenade.png
extends SceneTree

const CLIPS_GLB := "res://assets/characters/soldier/grenade/soldier_grenade.glb"
const SPEC := "res://assets/characters/soldier/grenade/clips.json"
const GRENADE := "res://assets/weapons/grenade/grenade.glb"
const GRENADE_FAR := "res://assets/weapons/grenade/grenade_far.glb"
## The gun hold (docs/design/animation.md, HOLD_GUN) turned 90 degrees about the weapon's X
## (`HOLD_GUN * Basis(Vector3.RIGHT, PI / 2)`): the grenade stands fuze up in the fist, the spoon
## against the palm. Chosen from eight turns rendered on the cooked hold.
const HOLD_GRENADE := Transform3D(
	Basis(
		Vector3(-0.062527, -0.997926, -0.015303),
		Vector3(-0.990971, 0.060254, 0.119776),
		Vector3(-0.118606, 0.022655, -0.992683)
	),
	Vector3(-0.039563, 0.197228, -0.070351)
)
const TILE := Vector2i(320, 400)
const GONE_AFTER := {"pin_out": "Pin", "spoon_off": "Spoon"}

var _out := "user://godot-grenade.png"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		_out = args[i + 1]
	_run.call_deferred()


func _frame(vp: SubViewport) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var vp := SubViewport.new()
	vp.size = TILE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.8, 0.8, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.0
	vp.add_child(cam)
	# The Soldier faces +Z; the camera is in front, to his right, a little above the chest.
	var target := Vector3(0, 1.0, 0)
	cam.look_at_from_position(target + Vector3(-0.55, 0.25, 1.0).normalized() * 10, target)

	var soldier: Node3D = (load(CLIPS_GLB) as PackedScene).instantiate()
	vp.add_child(soldier)
	var player: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	var sk: Skeleton3D = soldier.find_child("Skeleton3D", true, false)
	var hand := BoneAttachment3D.new()
	hand.bone_name = "Index1.R"
	sk.add_child(hand)
	var grenade: Node3D = (load(GRENADE) as PackedScene).instantiate()
	grenade.transform = HOLD_GRENADE
	hand.add_child(grenade)

	var rows: Array = []
	for clip: String in spec.clips:
		var info: Dictionary = spec.clips[clip]
		var frames: Array = [0]
		for e: String in info.events:
			frames.append(int(info.events[e]))
		frames.append(int(info.frames))
		frames = _six(frames)
		var row: Array[Image] = []
		player.play(clip)
		for f: int in frames:
			player.seek(f / float(spec.fps), true)
			grenade.visible = not (info.events.has("release") and f > int(info.events.release))
			for e: String in GONE_AFTER:
				var part := grenade.find_child(GONE_AFTER[e], true, false) as Node3D
				part.visible = not (info.events.has(e) and f >= int(info.events[e]))
			row.append(await _frame(vp))
			print("TILE ", clip, " ", f)
		rows.append(row)

	# The model on its own: held level, far level, then the pin and spoon pulled out on their nodes.
	soldier.visible = false
	cam.size = 1.0
	cam.look_at_from_position(Vector3(0.6, 0.35, 1.0).normalized() * 10, Vector3.ZERO)
	var models: Array[Image] = []
	for path: String in [GRENADE, GRENADE_FAR]:
		var g: Node3D = (load(path) as PackedScene).instantiate()
		vp.add_child(g)
		models.append(await _frame(vp))
		var pin := g.find_child("Pin", true, false) as Node3D
		var spoon := g.find_child("Spoon", true, false) as Node3D
		pin.position += Vector3(0, 0, 0.18)  # glTF +Z is Blender -Y: the pull direction
		spoon.rotate_object_local(Vector3.FORWARD, -0.9)
		models.append(await _frame(vp))
		g.queue_free()
	while models.size() < rows[0].size():
		models.append(models[0])
	rows.append(models.slice(0, rows[0].size()))

	var sheet := Image.create(
		TILE.x * rows[0].size(), TILE.y * rows.size(), false, Image.FORMAT_RGBA8
	)
	for r in rows.size():
		for c in rows[r].size():
			var img: Image = rows[r][c]
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(c * TILE.x, r * TILE.y))
	var err := sheet.save_png(_out)
	print("SHEET ", _out, " ", err)
	quit(0 if err == OK else 1)


func _six(frames: Array) -> Array:
	var fs: Array = []
	for f in frames:
		if not fs.has(f):
			fs.append(f)
	fs.sort()
	while fs.size() < 6:
		var gap := 0
		for i in fs.size() - 1:
			if fs[i + 1] - fs[i] > fs[gap + 1] - fs[gap]:
				gap = i
		fs.insert(gap + 1, (fs[gap] + fs[gap + 1]) / 2)
	while fs.size() > 6:
		fs.remove_at(fs.size() - 2)
	return fs
