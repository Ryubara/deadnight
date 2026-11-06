class_name CraneBlock
extends StaticBody3D
## The prize crane's cabinet as a wall. The crane you see (`CraneView`, `PrizeCrane`) is only a
## drawing, and a game server draws nothing, so the wall lives in the world both sides hold
## (`NightWorld`): the server's rules move it with the crane (`crane_moved`) and a client's frames
## do (`WorldMirror`). A wall only the client held was one its predicted body stopped at while the
## server's walked through, 2 m or more apart (#748).

## The cabinet's height (m); its width and depth are the drawing's.
const HEIGHT := 2.6

## The cabinet as the dead's sim sees it (`ZombieSim.solids`): the same box, where it stands now.
var solid := ZombieSolid.new()

var _places: Dictionary[int, Transform3D] = {}
var _shape := CollisionShape3D.new()
var _spot := -1


func _init() -> void:
	name = "CraneBlock"
	var box := BoxShape3D.new()
	box.size = Vector3(PrizeCrane.WIDTH, HEIGHT, PrizeCrane.DEPTH)
	_shape.shape = box
	_shape.position.y = HEIGHT / 2.0
	_shape.disabled = true
	add_child(_shape)


## `spots` is `NightWorld.shop_spots()`; the crane's own are the ones of kind `crane`.
func setup(spots: Array[Dictionary]) -> void:
	for spot in spots:
		if spot["kind"] == &"crane":
			_places[spot["crane_spot"]] = CraneView.stand_at(spot["position"], spot["yaw"])


## The crane stands at `spot` (the rules' index): the wall is there and nowhere else. A spot the map
## has no marker for takes the wall away.
func place(spot: int) -> void:
	if spot == _spot:
		return
	_spot = spot
	_shape.disabled = not _places.has(spot)
	if _shape.disabled:
		solid.clear()
	else:
		global_transform = _places[spot]
		solid.place(_places[spot], Vector3(PrizeCrane.WIDTH, HEIGHT, PrizeCrane.DEPTH))


## The spot the wall stands at, -1 when it stands nowhere.
func spot() -> int:
	return _spot if not _shape.disabled else -1
