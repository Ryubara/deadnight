extends Node3D
## A parked car. `Body` and `Cabin` are hidden CSG boxes: the collision, and what the zombies'
## navigation mesh is baked from. The model drawn over them is the lot's 1950s sedan
## (tools/blender/build_props.py) in one of five paints, picked from where the car stands, so the
## same lot always parks the same colours and nothing is random.

const PAINTS: Array[PackedScene] = [
	preload("res://assets/props/car_red.gltf"),
	preload("res://assets/props/car_blue.gltf"),
	preload("res://assets/props/car_green.gltf"),
	preload("res://assets/props/car_yellow.gltf"),
	preload("res://assets/props/car_cream.gltf"),
]


func _ready() -> void:
	var at := global_position
	var pick := posmod(roundi(at.x * 3.0) * 7 + roundi(at.z * 3.0) * 13, PAINTS.size())
	var model := PAINTS[pick].instantiate()
	model.name = "Model"
	add_child(model)
