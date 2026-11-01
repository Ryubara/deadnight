class_name ZombieDummy
extends Node3D
## A greybox zombie for the test range. It draws the hit zones exactly as the server tests them
## (`Hitbox.ZONES`), so what you see is what a shot can hit. Feet at the node's origin.

const ZONE_COLOURS := {
	&"head": Color(0.86, 0.36, 0.30),
	&"body": Color(0.56, 0.60, 0.52),
	&"limb": Color(0.40, 0.46, 0.44),
}
const FLASH_COLOUR := Color(1.0, 0.95, 0.7)
const FLASH_SECONDS := 0.2
const FALL_SECONDS := 0.45
const LINGER_SECONDS := 1.2
const LABEL_HEIGHT := 2.3

var target_id: int = 0

var _materials: Array[StandardMaterial3D] = []
var _label: Label3D
var _alive := true


func _ready() -> void:
	for zone in Hitbox.ZONES:
		_add_zone(zone)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.pixel_size = 0.005
	_label.position = Vector3(0, LABEL_HEIGHT, 0)
	add_child(_label)


func _add_zone(zone: Dictionary) -> void:
	var a: Vector3 = zone["a"]
	var b: Vector3 = zone["b"]
	var radius: float = zone["r"]
	var material := StandardMaterial3D.new()
	material.albedo_color = ZONE_COLOURS[zone["zone"]]
	material.roughness = 0.9
	var mesh: Mesh
	if a.is_equal_approx(b):
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh = sphere
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = a.distance_to(b) + radius * 2.0
		mesh = capsule
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = (a + b) / 2.0
	add_child(instance)
	_materials.append(material)


func show_health(health: float) -> void:
	if _label != null:
		_label.text = str(ceili(health))


## A hit lights the dummy up for a moment.
func flash() -> void:
	for material in _materials:
		material.emission_enabled = true
		material.emission = FLASH_COLOUR
	get_tree().create_timer(FLASH_SECONDS).timeout.connect(_end_flash)


func _end_flash() -> void:
	for material in _materials:
		material.emission_enabled = false


## Falls backwards and goes away.
func die() -> void:
	if not _alive:
		return
	_alive = false
	_label.visible = false
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", -PI / 2.0, FALL_SECONDS).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(LINGER_SECONDS)
	tween.tween_callback(queue_free)
