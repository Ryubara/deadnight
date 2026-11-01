class_name LotDoors
extends Node3D
## The lot's purchase doors (`Doors/Door_*`, written by tools/world/build_greybox.py). A door is a
## group of slabs that wall an area off, and the price label on it.
##
## `bind` listens to the rules; a `door_opened` event removes the door's slabs and label, so the
## player walks through and shots pass. The zombies' navigation mesh is baked from the slabs, so it
## is out of date the moment a door opens: `DoorNavigation` listens to `door_opened` and swaps in
## the mesh saved for the new set of doors.
## Nothing else opens a door.

## A door was opened (its shop id, e.g. `door_concession`).
signal door_opened(door_id: StringName)

var _rules: GameRules


## Follows `rules`: doors it already has open are opened now, later ones as they are bought.
func bind(rules: GameRules) -> void:
	_rules = rules
	rules.event_emitted.connect(_on_event)
	for door_id: StringName in rules.doors_open:
		open(door_id)


## The shop ids of the doors still closed.
func closed_doors() -> Array[StringName]:
	var closed: Array[StringName] = []
	for door in get_children():
		if not door.has_meta(&"open"):
			closed.append(StringName(door.get_meta(&"shop_id")))
	return closed


## Removes the door's slabs and label. False for an unknown door or one that is already open.
func open(door_id: StringName) -> bool:
	var door := _door(door_id)
	if door == null or door.has_meta(&"open"):
		return false
	door.set_meta(&"open", true)
	for part in door.get_children():
		# Out of the tree now, so the collision and the navigation bake stop seeing it this frame.
		door.remove_child(part)
		part.queue_free()
	door_opened.emit(door_id)
	return true


func _door(door_id: StringName) -> Node:
	for door in get_children():
		if door.get_meta(&"shop_id", "") == String(door_id):
			return door
	return null


func _on_event(event: Dictionary) -> void:
	if event.get("type") == &"door_opened":
		open(StringName(event["door_id"]))
