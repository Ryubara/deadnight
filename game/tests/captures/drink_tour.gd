## Capture of the perk drink (#912) in the game (not a test; needs a window: run it through
## `gds godot`): the real Player in the test room drinks a perk, through the real
## `PlayerAnimation.drink`, seen from the player's own shoulder camera (`--view player`), from where
## a teammate stands ahead of him and to his right (`--view teammate`) or from his right
## (`--view side`); or the six bottles side by side in their perks' colours (`--view bottles`).
## Writes a sheet of nine moments of the first drink to `<out>/drink-<view>.png`; with
## `--write-movie <abs>/f.png --fixed-fps 30` the run is also a clip of three drinks.
##
##     gds godot -- --path game -s res://tests/captures/drink_tour.gd -- --view player --out <dir>
extends SceneTree

const ROOM := "res://world/test_room.tscn"
const SECONDS := 2.5
const TILE := Vector2i(480, 360)
## The moments of each drink on the sheet (seconds into it).
const MOMENTS: Array[float] = [0.15, 0.4, 0.62, 0.85, 1.05, 1.3, 1.6, 1.95, 2.4]
const PERKS: Array[StringName] = [&"tonic_double_shot", &"tonic_quick_load", &"tonic_hearty"]

var _out := "user://"
var _view := "player"
## Seconds the game has run (each frame's own step, so a movie at a fixed rate is timed right).
var _clock := 0.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		elif args[i] == "--view" and i + 1 < args.size():
			_view = args[i + 1]
	_run.call_deferred()


func _process(delta: float) -> bool:
	_clock += delta
	return false


func _run() -> void:
	root.size = TILE * 2
	var room := (load(ROOM) as PackedScene).instantiate()
	root.add_child(room)
	var player := room.find_child("Player", true, false) as Player
	player.capture_mouse = false
	for _i in 30:
		await process_frame
	var animation := player.get_node("AnimationTree") as PlayerAnimation
	if _view == "bottles":
		await _bottles(room, player)
		return
	var cam: Camera3D = null
	if _view != "player":
		cam = Camera3D.new()
		cam.fov = 50.0
		room.add_child(cam)
		cam.current = true
	var tiles: Array[Image] = []
	for perk in PERKS:
		animation.drink(perk, SECONDS)
		var began := _clock
		var next := 0
		while _clock - began < SECONDS + 0.6:
			if cam != null:
				_place(cam, player)
			await process_frame
			var t := _clock - began
			if perk == PERKS[0] and next < MOMENTS.size() and t >= MOMENTS[next]:
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.resize(TILE.x, TILE.y)
				tiles.append(img)
				next += 1
	var sheet := Image.create(TILE.x * 3, TILE.y * 3, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		var img := tiles[i]
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(i % 3 * TILE.x, i / 3 * TILE.y))
	var path := _out.path_join("drink-%s.png" % _view)
	var err := sheet.save_png(path)
	print("SHEET ", path, " ", err)
	quit(0 if err == OK else 1)


## The camera of the view: ahead of him and to his right at a teammate's eye height, or square off
## his right side, looking at his chest.
func _place(cam: Camera3D, player: Player) -> void:
	var basis := player.global_basis.orthonormalized()
	var ahead := -basis.z
	var right := basis.x
	var at := player.global_position + Vector3(0.0, 1.0, 0.0)
	var from := at
	if _view == "teammate":
		from = player.global_position + ahead * 3.2 + right * 1.6 + Vector3(0.0, 1.35, 0.0)
	else:
		from = player.global_position + right * 2.6 + ahead * 0.4 + Vector3(0.0, 1.2, 0.0)
	cam.look_at_from_position(from, at)


## The six perks' bottles in a row on the floor beside the player, full and capped, each in its
## machine's colours, seen from in front at a third of a metre's height.
func _bottles(room: Node, player: Player) -> void:
	player.visible = false
	var ids: Array[StringName] = [&"tonic_hearty"]
	for look: Dictionary in PerkMachine.LOOKS.values():
		ids.append(look["item"])
	var at := player.global_position + Vector3(0.0, 0.0, -1.5)
	for i in ids.size():
		var bottle := PerkBottle.new()
		room.add_child(bottle)
		bottle.fill(ids[i])
		bottle.visible = true
		var hold := load(PerkBottle.HOLD) as WeaponHold
		bottle.global_transform = Transform3D(
			Basis().scaled(Vector3.ONE * hold.model_scale * 0.8),
			at + Vector3((float(i) - 2.5) * 0.3, -hold.butt.y * hold.model_scale * 0.8, 0.0)
		)
	var cam := Camera3D.new()
	cam.fov = 40.0
	room.add_child(cam)
	cam.current = true
	cam.look_at_from_position(at + Vector3(0.0, 0.45, 2.4), at + Vector3(0.0, 0.2, 0.0))
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join("drink-bottles.png")
	var err := root.get_texture().get_image().save_png(path)
	print("SHEET ", path, " ", err)
	quit(0 if err == OK else 1)
