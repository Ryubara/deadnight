class_name LotFuel
extends RefCounted
## The lot's fuel can spots (`FuelSpots/*`, written by tools/world/build_greybox.py): a marker a
## player stands at to buy a can for the generator, in front of a crate of cans. It finds them and
## answers the two questions the night asks: which spot is within a player's reach, and where the
## bot should stand. It decides nothing about the purchase; the rules do (`RulesAction.buy` of the
## spot's shop item, `ShopItem.fuel_offer` for its price).

var _spots: Dictionary[StringName, Marker3D] = {}


## Gathers the spots below `root`.
func _init(root: Node) -> void:
	var group := root.get_node_or_null("FuelSpots")
	if group == null:
		return
	for marker in group.get_children():
		_spots[StringName(marker.name)] = marker as Marker3D


## The spots' ids (the markers' names).
func ids() -> Array[StringName]:
	return _spots.keys()


## Where to stand to buy at the spot.
func standing_point(id: StringName) -> Vector3:
	return _spots[id].global_position


## The shop item the spot sells.
func item_of(id: StringName) -> StringName:
	return StringName(_spots[id].get_meta(&"shop_id"))


## The shop door of the area the spot is in; a spot is no use until it is open.
func door_of(id: StringName) -> StringName:
	return StringName(_spots[id].get_meta(&"door", ""))


## The nearest spot that lies within `reach` metres (flat) of `point`, or empty for none.
func within_reach(point: Vector3, reach: float) -> StringName:
	var best: StringName = &""
	var best_distance := reach
	for id in _spots:
		var at := _spots[id].global_position
		var distance := Vector2(point.x - at.x, point.z - at.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = id
	return best
