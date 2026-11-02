class_name DrawReveal
extends RefCounted
## Holds a scene's meshes out of the picture and brings them back a few at a time, so the renderer
## meets the kinds of material in small steps instead of all at once.
##
## In the Compatibility renderer the first draw of a material's shader builds all four of its
## variants (colour and depth, plain and instanced) at the engine's default specialisation, which
## includes the code for every light type: about 0.5 to 0.9 s each in a browser, whatever the mesh
## is. The lot has nine such shaders, so its first frame took 9 to 12 s with nothing on the screen
## moving (`docs/research/first-use-hitches.md`). The browser cannot build a part of a program, so
## the way to keep any one frame short is to let a frame meet one new kind of material only.
##
## `hide` takes every drawn node under a root out of the picture (the renderer's instance is turned
## off, the node's own `visible` is not touched, so the game can still show and hide it), `steps`
## orders them so that each step brings in one new kind of material, and `reveal` puts a step back.


## A node held back, and the kinds it draws with (`DrawLedger.keys_of`).
class Piece:
	extends RefCounted
	var node: GeometryInstance3D
	var keys: Array[String] = []

	func _init(p_node: GeometryInstance3D, p_keys: Array[String]) -> void:
		node = p_node
		keys = p_keys


var _pieces: Array[Piece] = []


## Takes every drawn node under `root` that is showing now out of the picture; returns how many.
## Nodes the game itself hides (the crane before the server's first frame) are left alone.
func hide(root: Node) -> int:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "GeometryInstance3D", true, false))
	var count := 0
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if geometry == null or not geometry.is_visible_in_tree():
			continue
		_pieces.append(Piece.new(geometry, DrawLedger.keys_of(geometry)))
		RenderingServer.instance_set_visible(geometry.get_instance(), false)
		count += 1
	return count


## How many nodes are still held back.
func pending() -> int:
	var count := 0
	for piece in _pieces:
		if piece != null:
			count += 1
	return count


## The steps that bring the held nodes in, each a list of indices (given to `reveal`). Every step
## meets at most one kind of material the earlier steps did not, and the most used kinds come first.
func steps() -> Array[Array]:
	var keys: Array[Array] = []
	for piece in _pieces:
		keys.append(piece.keys if piece != null else [])
	return plan(keys)


## Brings the nodes at `indices` (from `steps`) back into the picture. Returns them.
func reveal(indices: Array) -> Array[GeometryInstance3D]:
	var shown: Array[GeometryInstance3D] = []
	for index: int in indices:
		var piece := _pieces[index]
		if piece == null:
			continue
		_pieces[index] = null
		if is_instance_valid(piece.node):
			# The node's own state, not `true`: the game may have hidden it meanwhile.
			RenderingServer.instance_set_visible(
				piece.node.get_instance(), piece.node.is_visible_in_tree()
			)
			shown.append(piece.node)
	return shown


## Brings everything still held back into the picture.
func reveal_all() -> void:
	for index in _pieces.size():
		reveal([index])
	_pieces.clear()


## The order to bring pieces in. `keys[i]` is what piece `i` draws with; the result is a list of
## steps, each a list of piece indices. A piece comes in at the step where the last of its kinds is
## first met, so a step meets one new kind at most (a piece with two unseen kinds waits for the
## second). The kinds are met most-used first, so the early steps show the most.
static func plan(keys: Array[Array]) -> Array[Array]:
	var uses: Dictionary[String, int] = {}
	for piece_keys in keys:
		var once: Dictionary[String, bool] = {}
		for key: String in piece_keys:
			once[key] = true
		for key in once:
			uses[key] = uses.get(key, 0) + 1
	var order: Array[String] = []
	order.assign(uses.keys())
	order.sort_custom(func(a: String, b: String) -> bool: return _before(uses, a, b))
	var met: Dictionary[String, bool] = {}
	var left: Array[int] = []
	for index in keys.size():
		left.append(index)
	var result: Array[Array] = []
	# Pieces that draw with nothing the renderer needs to build wait for no kind.
	_take(result, keys, left, met)
	for key in order:
		met[key] = true
		_take(result, keys, left, met)
	return result


static func _before(uses: Dictionary[String, int], a: String, b: String) -> bool:
	if uses[a] != uses[b]:
		return uses[a] > uses[b]
	return a < b


## Moves the pieces in `left` whose kinds are all in `met` into a new step of `result`.
static func _take(
	result: Array[Array], keys: Array[Array], left: Array[int], met: Dictionary[String, bool]
) -> void:
	var step: Array[int] = []
	var rest: Array[int] = []
	for index in left:
		var ready := true
		for key: String in keys[index]:
			if not met.has(key):
				ready = false
				break
		if ready:
			step.append(index)
		else:
			rest.append(index)
	left.assign(rest)
	if not step.is_empty():
		result.append(step)
