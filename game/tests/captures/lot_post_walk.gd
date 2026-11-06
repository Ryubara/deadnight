extends Node
## A body walking from the west of the booth to the east midway's barricade stand, past the booth's
## breaker post (Deadnight #1334), filmed from above. The walking mesh's edges are drawn in green,
## the post in orange, the path in white and the body (a capsule: a hand-ticked night draws none) in
## cyan. The text says how long the body has made no headway.
##
## Not part of the game. Run with Movie Maker through the kit's `gds godot`:
## `gds godot -- --path game res://tests/captures/lot_post_walk.tscn --fixed-fps 10
## --write-movie out.png --quit-after 110 -- --label="after: the post is in the mesh"`.

## Arguments after `--`: `--label=TEXT` (the first line of the overlay), `--from=x,y,z` and
## `--to=x,y,z` (the walk, the soak's by default), `--frame=x,z,width,depth` (the part of the lot
## drawn),
## `--scene=res://...` (another map's greybox: no door is bought and the booth is left alone).
const WEST := Vector3(-3.8, 0.1, 20.6)
const STAND := Vector3(12.5, 0.4, 31.6)
## The part of the lot drawn: x from, x to, z from, z to.
const FRAME := Rect2(-6.0, 14.0, 22.0, 20.0)
const TICKS_PER_FRAME := 6
const LONG_BREAK := 1.0e6

var _night: SeatedNight
var _walker: HumanWalker
var _marker: MeshInstance3D
var _label: Label
var _head := ""
var _ticks := 0
var _scene: PackedScene
var _from := WEST
var _to := STAND
var _frame := FRAME


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_head = argument.trim_prefix("--label=")
		elif argument.begins_with("--scene="):
			_scene = load(argument.trim_prefix("--scene=")) as PackedScene
		elif argument.begins_with("--from="):
			_from = _vector(argument.trim_prefix("--from="))
		elif argument.begins_with("--to="):
			_to = _vector(argument.trim_prefix("--to="))
		elif argument.begins_with("--frame="):
			var box := argument.trim_prefix("--frame=").split_floats(",")
			_frame = Rect2(box[0], box[1], box[2], box[3])
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = LONG_BREAK
	tuning.rounds.break_seconds = LONG_BREAK
	_night = await SeatedNight.start(self, 1, tuning, 8, false, _scene)
	if _scene == null:
		_night.open_door(&"door_concession")
		_night.open_door(&"door_booth")
	await _night.settle(60)
	await _night.settle_doors()
	_walker = _night.human(1)
	_night.server.body_of(1).teleport(_from)
	_night.run(2)
	_walker.goto(_to)
	_dress()


func _process(_delta: float) -> void:
	if _walker == null:
		return
	for _i in TICKS_PER_FRAME:
		_walker.tick()
		_night.tick()
	_ticks += TICKS_PER_FRAME
	var body := _night.server.body_of(1)
	_marker.global_position = body.global_position + Vector3(0.0, 0.9, 0.0)
	_label.text = (
		"%s\nt = %4.1f s   no headway for %.1f s   at (%.1f, %.1f)"
		% [
			_head,
			float(_ticks) / 60.0,
			_walker.stalled,
			body.global_position.x,
			body.global_position.z
		]
	)


func _dress() -> void:
	# The booth's upper storey hides its north wall from above; hiding it moves nothing the body feels.
	var parts := [
		"Roof", "UpperFloor", "Landing", "WallNUpper0", "WallNUpper1", "WallNUpper2", "WallNUpper3"
	]
	if _scene == null:
		for part in parts:
			var node := _night.world.greybox.get_node_or_null("ProjectionBooth/" + part) as Node3D
			if node != null:
				node.visible = false
	else:
		# Another map: hide whatever is drawn above head height, so the floor shows from above.
		for box in _night.world.greybox.find_children("*", "CSGBox3D", true, false):
			if (box as CSGBox3D).global_position.y - (box as CSGBox3D).size.y * 0.5 > 2.0:
				(box as CSGBox3D).visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(_frame.get_center().x, 30.0, _frame.get_center().y)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.fov = 38.0
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70.0, 20.0, 0.0)
	add_child(light)
	_marker = _mesh(CapsuleMesh.new(), Color(0.2, 0.8, 1.0, 1.0))
	(_marker.mesh as CapsuleMesh).radius = 0.35
	(_marker.mesh as CapsuleMesh).height = 1.8
	var post := BoxMesh.new()
	post.size = Vector3(0.8, 1.5, 0.5)
	if _frame.has_point(Vector2(5.6, 21.5)):
		_mesh(post, Color(1.0, 0.45, 0.1, 1.0)).global_position = Vector3(5.6, 0.75, 21.5)
	var stand := CylinderMesh.new()
	stand.top_radius = 0.15
	stand.bottom_radius = 0.15
	stand.height = 3.0
	_mesh(stand, Color(1.0, 0.9, 0.1, 1.0)).global_position = _to + Vector3(0.0, 1.5, 0.0)
	_lines(_mesh_edges(), Color(0.2, 1.0, 0.3, 1.0))
	_lines(_path_lines(), Color(1.0, 1.0, 1.0, 1.0))
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16.0, 12.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


## Pairs of points: every edge of the saved mesh's polygons inside the frame.
func _mesh_edges() -> PackedVector3Array:
	var navmesh := _night.world.layout.navmeshes().mesh_for(_night.world.greybox)
	var lines := PackedVector3Array()
	if navmesh == null:
		return lines
	var vertices := navmesh.get_vertices()
	for p in navmesh.get_polygon_count():
		var polygon := navmesh.get_polygon(p)
		for i in polygon.size():
			var a := vertices[polygon[i]]
			var b := vertices[polygon[(i + 1) % polygon.size()]]
			if _frame.grow(1.0).has_point(Vector2(a.x, a.z)):
				lines.append(a + Vector3(0.0, 0.05, 0.0))
				lines.append(b + Vector3(0.0, 0.05, 0.0))
	return lines


func _path_lines() -> PackedVector3Array:
	var way := NavigationServer3D.map_get_path(_night.world.map(), _from, _to, true, NavLayers.WALK)
	var lines := PackedVector3Array()
	for i in way.size() - 1:
		lines.append(way[i] + Vector3(0.0, 0.1, 0.0))
		lines.append(way[i + 1] + Vector3(0.0, 0.1, 0.0))
	return lines


func _lines(points: PackedVector3Array, colour: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in points:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_mesh(mesh, colour)


func _mesh(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material
	add_child(node)
	return node


static func _vector(text: String) -> Vector3:
	var parts := text.split_floats(",")
	return Vector3(parts[0], parts[1], parts[2])
