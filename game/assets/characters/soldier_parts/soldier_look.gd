class_name SoldierLook
extends RefCounted
## Dresses the modular Soldier from a look: one part id per slot and one palette index per colour
## channel (docs/design/characters.md). The catalog, `parts.json`, is written by
## tools/blender/build_soldier_parts.py beside the model; nothing here hard-codes a part.
##
##     var model := SoldierLook.instantiate()
##     SoldierLook.apply(model, SoldierLook.preset(&"greaser"))

const DIR := "res://assets/characters/soldier_parts/"
const CATALOG := DIR + "parts.json"
const MODEL := DIR + "soldier_parts.glb"
const ATLAS := DIR + "soldier_parts_atlas.png"

static var _catalog: Dictionary = {}
static var _atlas: Image


## The parsed parts.json (loaded once).
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	return _catalog


static func presets() -> Array:
	return catalog().presets


## A preset's look ({parts, colours} plus id, name), or an empty dictionary.
static func preset(id: StringName) -> Dictionary:
	for p: Dictionary in presets():
		if p.id == String(id):
			return p
	return {}


## The first preset whose id is not in `taken`, so each player who joins starts out different;
## past eight players it cycles.
static func default_preset(taken: Array) -> Dictionary:
	var all := presets()
	for p: Dictionary in all:
		if not taken.has(p.id) and not taken.has(StringName(p.id)):
			return p
	return all[taken.size() % all.size()]


## A complete, valid look: unknown slots dropped, missing or unknown parts set to the slot's
## default, colour indices wrapped into their palette.
static func normalized(look: Dictionary) -> Dictionary:
	var cat := catalog()
	var parts := {}
	var given: Dictionary = look.get("parts", {})
	for slot: String in cat.slots:
		var spec: Dictionary = cat.slots[slot]
		var id := String(given.get(slot, spec.default))
		parts[slot] = id if spec.parts.has(id) else String(spec.default)
	var colours := {}
	var picked: Dictionary = look.get("colours", {})
	for channel: String in cat.channels:
		var size: int = cat.palettes[cat.channels[channel]].size()
		colours[channel] = posmod(int(picked.get(channel, 0)), size)
	return {"parts": parts, "colours": colours}


## A new, undressed model (every part hidden until apply()).
static func instantiate() -> Node3D:
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	for mesh in part_meshes(model).values():
		(mesh as MeshInstance3D).visible = false
	return model


## Mesh node name (`<slot>__<part>`) -> MeshInstance3D for every part in the model.
static func part_meshes(model: Node) -> Dictionary:
	var out := {}
	for node in model.find_children("*__*", "MeshInstance3D", true, false):
		out[String(node.name)] = node
	return out


## The mesh names a look shows (headwear that covers the head hides the hair).
static func visible_meshes(look: Dictionary) -> Array[String]:
	var cat := catalog()
	var lk := normalized(look)
	var headwear: Dictionary = cat.slots.headwear.parts[lk.parts.headwear]
	var out: Array[String] = []
	for slot: String in lk.parts:
		var part: Dictionary = cat.slots[slot].parts[lk.parts[slot]]
		if part.mesh == null or (slot == "hair" and headwear.get("hides_hair", false)):
			continue
		out.append(String(part.mesh))
	return out


## Shows the look's parts, hides the rest and gives every part one material with the look's
## colours. Returns the triangle count of what is shown.
static func apply(model: Node, look: Dictionary) -> int:
	var lk := normalized(look)
	var show := visible_meshes(lk)
	var material := make_material(lk.colours)
	var tris := 0
	var meshes := part_meshes(model)
	for mesh_name: String in meshes:
		var mi: MeshInstance3D = meshes[mesh_name]
		mi.visible = show.has(mesh_name)
		mi.material_override = material
		if mi.visible:
			tris += triangles(mi.mesh)
	return tris


## The atlas with the channel swatches filled from the look's palette indices.
static func atlas_image(colours: Dictionary) -> Image:
	var cat := catalog()
	if _atlas == null:
		_atlas = (load(ATLAS) as Texture2D).get_image()
		if _atlas.is_compressed():
			_atlas.decompress()
		_atlas.convert(Image.FORMAT_RGBA8)
	var img := _atlas.duplicate() as Image
	var px: int = cat.atlas.swatch_px
	for channel: String in cat.channels:
		var palette: Array = cat.palettes[cat.channels[channel]]
		var colour := Color.html(palette[posmod(int(colours.get(channel, 0)), palette.size())])
		var shade := colour * float(cat.shade)
		shade.a = 1.0
		for pair in [[channel, colour], [channel + "_shade", shade]]:
			var cell: Array = cat.atlas.cells[pair[0]]
			img.fill_rect(Rect2i(int(cell[0]) * px, int(cell[1]) * px, px, px), pair[1])
	return img


static func make_material(colours: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(atlas_image(colours))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.8
	return m


static func triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as Array).size()) / 3
	return n
