extends SceneTree
## The pieces of a map's walking mesh, as a review reads them (#1051): one line a door set, a line a
## piece of the mesh with every door open, and a picture from above. From the repository root:
##
##   godot --headless --path game -s res://tools/world/walking_pieces.gd -- --png=<file> \
##     [--scene=<res path> --meshes=<res path>] [--cut-only] [--view=x,z,width,height]
##
## `--cut-only` looks at the mesh with only the barricades' lines cut out of it (`NavmeshSplit`'s
## `least` at 0): the walking mesh as it was before #1051. In the picture the map's ground is grey,
## other pieces of the walking mesh green, the dead's polygons blue, and a piece the cut or the bake
## left under `NavmeshSplit.LEAST_PIECE` red. `test_walking_mesh_pieces.gd` holds what this shows.

const LOT := "res://world/drive_in_greybox.tscn"
const GROUND := Color(0.72, 0.72, 0.72)
const OTHER := Color(0.45, 0.7, 0.45)
const GAP := Color(0.2, 0.45, 0.95)
const SCRAP := Color(0.95, 0.15, 0.1)
const PAPER := Color(1.0, 1.0, 1.0)

var _scene := LOT
var _meshes := LotNavmeshes.PATH
var _png := ""
var _least := NavmeshSplit.LEAST_PIECE
var _view := Rect2(-72.0, -62.0, 144.0, 122.0)
var _scale := 8.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene = argument.trim_prefix("--scene=")
		elif argument.begins_with("--meshes="):
			_meshes = argument.trim_prefix("--meshes=")
		elif argument.begins_with("--png="):
			_png = argument.trim_prefix("--png=")
		elif argument == "--cut-only":
			_least = 0.0
		elif argument.begins_with("--view="):
			var parts := argument.trim_prefix("--view=").split_floats(",")
			_view = Rect2(parts[0], parts[1], parts[2], parts[3])
			_scale = 960.0 / maxf(_view.size.x, _view.size.y)
	_run()


func _run() -> void:
	await process_frame
	var saved := load(_meshes) as LotNavmeshes
	var lot := (load(_scene) as PackedScene).instantiate() as Node3D
	root.add_child(lot)
	for _i in NightWorld.SETTLE_FRAMES:
		await physics_frame
	var strips := NavmeshSplit.strips_of(lot, Transform3D.IDENTITY)
	for key: String in saved.meshes:
		var mesh: NavigationMesh = saved.meshes[key]
		var halves := NavmeshSplit.split(mesh, strips, _least)
		print(
			(
				"%d polygons: %d pieces baked, %d walking, %d polygons the dead's alone"
				% [
					mesh.get_polygon_count(),
					NavmeshPieces.of(mesh).size(),
					NavmeshPieces.of(halves[0]).size(),
					halves[1].get_polygon_count()
				]
			)
		)
	var doors := lot.get_node("Doors") as LotDoors
	var sets := LotNavmeshes.door_sets(doors)
	for id: StringName in sets[sets.size() - 1]:
		doors.open(id)
	var whole := saved.mesh_for(lot)
	var parts := NavmeshSplit.split(whole, strips, _least)
	var pieces := NavmeshPieces.of(parts[0])
	for piece in pieces:
		print(_line(piece))
	if not _png.is_empty():
		_draw(parts[0], parts[1], pieces, _area_ground(pieces))
	quit(0)


## The piece that is the map's ground: the largest at floor height.
func _area_ground(pieces: Array[NavmeshPieces.Piece]) -> NavmeshPieces.Piece:
	for piece in pieces:
		if piece.low > 0.0:
			return piece
	return pieces[0]


func _line(piece: NavmeshPieces.Piece) -> String:
	return (
		"%4d polygons %9.2f m2  x %.2f to %.2f  z %.2f to %.2f  y %.2f to %.2f"
		% [
			piece.polygons.size(),
			piece.area,
			piece.box.position.x,
			piece.box.end.x,
			piece.box.position.y,
			piece.box.end.y,
			piece.low,
			piece.high
		]
	)


func _draw(
	walking: NavigationMesh,
	gaps: NavigationMesh,
	pieces: Array[NavmeshPieces.Piece],
	ground: NavmeshPieces.Piece
) -> void:
	var image := Image.create(
		ceili(_view.size.x * _scale), ceili(_view.size.y * _scale), false, Image.FORMAT_RGB8
	)
	image.fill(PAPER)
	for piece in pieces:
		var colour := OTHER
		if piece == ground:
			colour = GROUND
		elif piece.area < NavmeshSplit.LEAST_PIECE:
			colour = SCRAP
		for index in piece.polygons:
			_fill(image, walking, index, colour)
	for index in gaps.get_polygon_count():
		_fill(image, gaps, index, GAP)
	var error := image.save_png(_png)
	if error != OK:
		push_error("cannot save %s: %s" % [_png, error_string(error)])


func _fill(image: Image, mesh: NavigationMesh, index: int, colour: Color) -> void:
	var vertices := mesh.get_vertices()
	var outline := PackedVector2Array()
	var box := Rect2()
	for i in mesh.get_polygon(index):
		var at := (Vector2(vertices[i].x, vertices[i].z) - _view.position) * _scale
		box = Rect2(at, Vector2.ZERO) if outline.is_empty() else box.expand(at)
		outline.append(at)
	var area := box.intersection(Rect2(Vector2.ZERO, Vector2(image.get_size())))
	for y in range(floori(area.position.y), ceili(area.end.y)):
		for x in range(floori(area.position.x), ceili(area.end.x)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), outline):
				image.set_pixel(x, y, colour)
