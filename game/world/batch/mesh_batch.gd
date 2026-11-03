class_name MeshBatch
extends RefCounted
## Many small meshes drawn as few (#728). A phone's processor pays for every mesh surface the
## renderer has to cull, sort and submit, whatever its size: the lot stands 1 100 of them. A batch
## takes the pieces it is given (a mesh surface, where it stands, the material it wears), sorts
## them into square cells of the ground and, inside a cell, by the material, and builds one mesh
## for each cell: one draw for every material in it. The pieces keep their places and their
## material, so the picture is the same.
##
## A cell is culled as a whole when it is out of the picture, and the renderer lights a mesh with at
## most a few lights by its box (`LightReach`): a cell the lights of a whole street reach is split
## until it is not. Group a piece by `group` to keep a kind apart (the small props, which a camera
## can stop drawing from far).


## What one piece of a batch is.
class Piece:
	extends RefCounted
	var mesh: Mesh
	var surface: int
	var xform: Transform3D
	var material: Material
	var bounds: AABB
	var group: StringName


## The pieces of one cell.
class Cell:
	extends RefCounted
	var group: StringName
	var pieces: Array[Piece] = []
	var bounds := AABB()

	func add(piece: Piece) -> void:
		bounds = piece.bounds if pieces.is_empty() else bounds.merge(piece.bounds)
		pieces.append(piece)


## The size of a cell in metres, along x and z.
const DEFAULT_CELL := 12.0
## The meta of a built mesh that names its group.
const GROUP_META := &"batch_group"
## The meta of a built mesh that counts the pieces it was made of.
const PIECES_META := &"batch_pieces"

## Shaders whose picture does not depend on where the mesh's own origin is, so the same surface
## drawn from a mesh with another origin looks the same: they read the world position
## (`MODEL_MATRIX * VERTEX`) and nothing else of the node.
const WORLD_SPACE_SHADERS: PackedStringArray = ["res://assets/lot/lot_surface.gdshader"]

var _cell_size: float
var _lights: Array[Light3D]
var _budget: int
## `group|cx|cz` to the pieces whose middle is in that cell.
var _cells: Dictionary[String, Cell] = {}
## The cells after the ones too many lights reach were split (`_settle`).
var _settled: Array[Cell] = []
var _is_settled := false
## Material signatures, by the material, so each material is read once.
var _signatures: Dictionary[Material, String] = {}


## `cell_size` is a cell's side in metres. A cell that more than `light_budget` of `lights` reach is
## split
## in four, again and again, until it is under (a lone piece is never split): the renderer lights a
## mesh
## with at most a few lights, by its box (`LightReach`), and a mesh the lights of a street reach
## drops
## some. A budget of 0 splits nothing.
func _init(cell_size: float = DEFAULT_CELL, lights: Array[Light3D] = [], light_budget := 0) -> void:
	_cell_size = cell_size
	_lights = lights
	_budget = light_budget


## Whether `material` is one a batch can share: opaque or cut-out, one pass, and either a plain
## material or one of the world-space shaders.
static func can_batch(material: Material) -> bool:
	if material == null or material.next_pass != null:
		return false
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return shader != null and WORLD_SPACE_SHADERS.has(shader.resource_path)
	if not (material is BaseMaterial3D):
		return false
	var base := material as BaseMaterial3D
	return (
		base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		or base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	)


## Adds one surface of `mesh`, placed by `xform` (in the space the batch is built in). False when
## the surface cannot be batched (a mirrored transform turns its faces inside out; a material that
## blends).
func add(
	mesh: Mesh, surface: int, xform: Transform3D, material: Material, group: StringName = &""
) -> bool:
	if xform.basis.determinant() <= 0.0 or not can_batch(material):
		return false
	var piece := Piece.new()
	piece.mesh = mesh
	piece.surface = surface
	piece.xform = xform
	piece.material = material
	piece.group = group
	piece.bounds = xform * mesh.get_aabb()
	var centre := piece.bounds.get_center()
	var cell := Vector2i(floori(centre.x / _cell_size), floori(centre.z / _cell_size))
	var cell_key := "%s|%d|%d" % [group, cell.x, cell.y]
	if not _cells.has(cell_key):
		var fresh := Cell.new()
		fresh.group = group
		_cells[cell_key] = fresh
	_cells[cell_key].add(piece)
	_is_settled = false
	return true


## How many cells hold something.
func cell_count() -> int:
	return _settle().size()


## How many surfaces the batch would draw: one for each material of each cell.
func surface_count() -> int:
	var total := 0
	for cell in _settle():
		total += _by_material(cell).size()
	return total


## Builds one `MeshInstance3D` for each cell and adds them to `parent` (the space the pieces were
## given in). Each stands at the middle of its cell's pieces, so a range of sight is measured from
## where it is.
func build(parent: Node3D) -> Array[MeshInstance3D]:
	var made: Array[MeshInstance3D] = []
	for cell in _settle():
		var origin := cell.bounds.get_center()
		var mesh := ArrayMesh.new()
		var by_material := _by_material(cell)
		var keys := by_material.keys()
		keys.sort()
		for key: String in keys:
			var pieces: Array = by_material[key]
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for piece: Piece in pieces:
				var local := Transform3D(piece.xform.basis, piece.xform.origin - origin)
				tool.append_from(piece.mesh, piece.surface, local)
			tool.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, (pieces[0] as Piece).material)
		var instance := MeshInstance3D.new()
		instance.name = "Batch_%s_%d" % [cell.group, made.size()]
		instance.mesh = mesh
		instance.position = origin
		instance.set_meta(GROUP_META, cell.group)
		instance.set_meta(PIECES_META, cell.pieces.size())
		parent.add_child(instance)
		made.append(instance)
	return made


## The cells in a fixed order, the over-lit ones split.
func _settle() -> Array[Cell]:
	if _is_settled:
		return _settled
	_settled = []
	var keys := _cells.keys()
	keys.sort()
	for key: String in keys:
		_fit(_cells[key], _settled)
	_is_settled = true
	return _settled


func _fit(cell: Cell, into: Array[Cell]) -> void:
	if _budget <= 0 or cell.pieces.size() <= 1 or LightReach.count(_lights, cell.bounds) <= _budget:
		into.append(cell)
		return
	var middle := cell.bounds.get_center()
	var quarters: Array[Cell] = [Cell.new(), Cell.new(), Cell.new(), Cell.new()]
	for piece in cell.pieces:
		var at := piece.bounds.get_center()
		var quarter := quarters[(1 if at.x >= middle.x else 0) + (2 if at.z >= middle.z else 0)]
		quarter.group = cell.group
		quarter.add(piece)
	var used := quarters.filter(func(quarter: Cell) -> bool: return not quarter.pieces.is_empty())
	if used.size() == 1:
		_pack(cell, into)
		return
	for quarter: Cell in used:
		_fit(quarter, into)


## Pieces that stand in one place (a floor and the ceiling over it) cannot be told apart by where
## they are: each goes into the first cell it fits with under the budget, or into one of its own.
func _pack(cell: Cell, into: Array[Cell]) -> void:
	var open: Array[Cell] = []
	for piece in cell.pieces:
		var home: Cell = null
		for candidate in open:
			var union := candidate.bounds.merge(piece.bounds)
			if LightReach.count(_lights, union) <= _budget:
				home = candidate
				break
		if home == null:
			home = Cell.new()
			home.group = cell.group
			open.append(home)
		home.add(piece)
	into.append_array(open)


## A cell's pieces by what they are made of: `signature|format` to the pieces.
func _by_material(cell: Cell) -> Dictionary:
	var found := {}
	for piece in cell.pieces:
		var key := "%s|%d" % [signature(piece.material), _format(piece)]
		if not found.has(key):
			found[key] = []
		found[key].append(piece)
	return found


## The arrays a surface has (a primitive mesh has the same four every time).
func _format(piece: Piece) -> int:
	return (
		(piece.mesh as ArrayMesh).surface_get_format(piece.surface)
		if piece.mesh is ArrayMesh
		else -1
	)


## What two materials must share to be drawn as one: every stored property, with a resource named by
## its path (or, with none, by what it is). Two imported models that wear one palette have two
## material resources that read the same.
func signature(material: Material) -> String:
	if _signatures.has(material):
		return _signatures[material]
	# A material that glows may be dimmed by a script (a machine's breathing board): two of them
	# that read the same are two, so that each keeps being its own.
	if material is BaseMaterial3D and (material as BaseMaterial3D).emission_enabled:
		_signatures[material] = "glow%d" % material.get_instance_id()
		return _signatures[material]
	var parts := PackedStringArray([material.get_class()])
	for info in material.get_property_list():
		if not (info["usage"] & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = info["name"]
		if name in ["resource_name", "resource_path", "script", "resource_local_to_scene"]:
			continue
		parts.append("%s=%s" % [name, _text(material.get(name))])
	var text := "\n".join(parts)
	_signatures[material] = text.sha1_text()
	return _signatures[material]


func _text(value: Variant) -> String:
	if value is Resource:
		var resource := value as Resource
		if resource.resource_path != "":
			return resource.resource_path
		if resource is Texture2D:
			return (
				"tex%dx%d:%d"
				% [
					(resource as Texture2D).get_width(),
					(resource as Texture2D).get_height(),
					resource.get_instance_id(),
				]
			)
		return str(resource.get_instance_id())
	return var_to_str(value)
