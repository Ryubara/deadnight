class_name PerkBottle
extends Node3D
## The perk's bottle in the Soldier's right fist while he drinks it (#912,
## docs/design/animation.md, "Drink"): the model `holds/perk_bottle.tres` names, on the hand
## mount in the weapon's place, in the grip solved for it, coloured for the perk (the glass in
## its machine's drink colour, the label band in the machine's body colour). The drink clip's
## events drive it (`PlayerAnimation`): it shows at `bottle_visible`, its cap pops off at
## `cap_off`, and at `discard` it leaves the hand and is thrown away to the drinker's right,
## landing on the ground beside him. Its sounds (the cap, the gulps, the bottle landing) are
## played here, where the bottle is.

const HOLD := "res://gameplay/player/holds/perk_bottle.tres"
const GRIP := "perk_bottle"
## The soda fountain's tonic has no cooler look: its colours are the fountain's.
const HEARTY := &"tonic_hearty"
## How bright the drink glows (the machines' bottles glow at 0.5; in the hand it is closer).
const GLOW := 0.35
## The empty bottle's throw (m/s, in the drinker's frame: x to his right, y up, z behind), its spin
## (rad/s), how far it bounces back up (of its speed), and how long it lies before it goes.
const THROW := Vector3(1.6, 2.0, 0.6)
const SPIN := Vector3(9.0, 3.0, 6.0)
const BOUNCE := 0.3
const LIE_SECONDS := 4.0
## The cap flicks up and out to the left.
const CAP_THROW := Vector3(-0.8, 2.0, -0.3)
const GRAVITY := 9.8
## The sounds, from the `perks` bank (deferred, #864).
const SOUND_OPEN := &"drink_open"
const SOUND_DRINK := &"drink_gulp"
const SOUND_DISCARD := &"drink_discard"

## The grip the right hand closes on while the bottle shows.
var grip: HandGrip
## The perk the bottle is coloured for.
var item_id: StringName = &""

var _model: Node3D
var _cap: Node3D
var _glass: StandardMaterial3D
var _label: StandardMaterial3D
## What flies or lies on the ground now: {node, velocity, spin, floor, left (s), landed}.
var _loose: Array[Dictionary] = []


func _init() -> void:
	name = "PerkBottle"
	var hold := load(HOLD) as WeaponHold
	grip = HandGrip.for_name(GRIP)
	_model = (load(hold.scene) as PackedScene).instantiate() as Node3D
	add_child(_model)
	_cap = _model.find_child("Cap", true, false) as Node3D
	_glass = StandardMaterial3D.new()
	_glass.emission_enabled = true
	_glass.emission_energy_multiplier = GLOW
	_glass.roughness = 0.15
	_label = StandardMaterial3D.new()
	_label.roughness = 0.7
	for mesh: MeshInstance3D in _meshes(_model):
		if mesh.name == "Label":
			mesh.material_override = _label
		elif mesh.name != "Cap":
			mesh.material_override = _glass
	transform = HeldWeapon.grip_hold(grip, PlayerAnimation.HOLD_MELEE).scaled_local(
		Vector3.ONE * hold.model_scale
	)
	visible = false


## The colours of a perk's bottle: {drink, label}, from its machine's look.
static func colours_of(tonic_id: StringName) -> Dictionary:
	if tonic_id == HEARTY:
		return {"drink": SodaFountain.TONIC, "label": SodaFountain.RED}
	for look: Dictionary in PerkMachine.LOOKS.values():
		if look["item"] == tonic_id:
			return {"drink": look["drink"], "label": look["body"]}
	return {"drink": SodaFountain.TONIC, "label": SodaFountain.CREAM}


## A full bottle of `tonic_id` in the hand, capped, not shown yet (the clip shows it).
func fill(tonic_id: StringName) -> void:
	item_id = tonic_id
	var colours := colours_of(tonic_id)
	_glass.albedo_color = colours["drink"]
	_glass.emission = colours["drink"]
	_label.albedo_color = colours["label"]
	if _cap != null:
		_cap.visible = true


## The glass's colour now (for tests).
func drink_colour() -> Color:
	return _glass.albedo_color


func label_colour() -> Color:
	return _label.albedo_color


## Whether the cap is still on (for tests).
func capped() -> bool:
	return _cap != null and _cap.visible


## The bottles and caps thrown that are still in the world (for tests).
func loose() -> int:
	return _loose.size()


## The cap pops off: it flicks up off the lip and falls.
func pop_cap() -> void:
	if _cap == null or not _cap.visible:
		return
	_cap.visible = false
	_throw_copy(_cap, CAP_THROW, SPIN * 2.0, 1.5)
	_sound(SOUND_OPEN)


func gulp() -> void:
	_sound(SOUND_DRINK)


## The empty bottle leaves the hand and is thrown away to the drinker's right (`right`, `up` and
## `back` are his world axes); the one in the hand is hidden.
func discard(right: Vector3, back: Vector3) -> void:
	if not visible:
		return
	visible = false
	var velocity := right * THROW.x + Vector3.UP * THROW.y + back * THROW.z
	_throw_copy(_model, velocity, SPIN, LIE_SECONDS, true)
	_sound(SOUND_DISCARD)


## The bottle falls from the hand where it is (the drinker went down mid-drink).
func drop() -> void:
	if not visible:
		return
	visible = false
	_throw_copy(_model, Vector3(0.0, 0.5, 0.0), SPIN * 0.3, LIE_SECONDS, true)


## Steps what was thrown: it falls, lands on the floor it was thrown above, bounces once, lies a
## moment and goes. Driven by the animation's own step (no clock of its own).
func step(delta: float) -> void:
	for i in range(_loose.size() - 1, -1, -1):
		var part: Dictionary = _loose[i]
		var node: Node3D = part["node"]
		part["left"] -= delta
		if part["left"] <= 0.0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_loose.remove_at(i)
			continue
		if part["landed"]:
			continue
		var velocity: Vector3 = part["velocity"]
		velocity.y -= GRAVITY * delta
		node.global_position += velocity * delta
		node.rotate_object_local(Vector3.RIGHT, part["spin"].x * delta)
		node.rotate_object_local(Vector3.UP, part["spin"].y * delta)
		node.rotate_object_local(Vector3.FORWARD, part["spin"].z * delta)
		var floor_y: float = part["floor"]
		if node.global_position.y <= floor_y and velocity.y < 0.0:
			node.global_position.y = floor_y
			if part["bounced"]:
				part["landed"] = true
				_lay_down(node)
			else:
				part["bounced"] = true
				velocity = Vector3(velocity.x * 0.5, -velocity.y * BOUNCE, velocity.z * 0.5)
				part["spin"] = part["spin"] * 0.4
		part["velocity"] = velocity


## A copy of `source` as it is drawn now, let go into the world with `velocity`.
func _throw_copy(
	source: Node3D, velocity: Vector3, spin: Vector3, seconds: float, whole := false
) -> void:
	var world := _world_root()
	if world == null:
		return
	var copy := source.duplicate() as Node3D
	if whole and copy.find_child("Cap", true, false) != null:
		(copy.find_child("Cap", true, false) as Node3D).visible = _cap != null and _cap.visible
	copy.visible = true
	world.add_child(copy)
	copy.global_transform = source.global_transform
	copy.top_level = true
	var feet := global_position.y
	var body := _body()
	if body != null:
		feet = body.global_position.y
	(
		_loose
		. append(
			{
				"node": copy,
				"velocity": velocity,
				"spin": spin,
				"floor": feet + (0.055 if whole else 0.005),
				"left": seconds,
				"landed": false,
				"bounced": false,
			}
		)
	)


## On its side on the ground, its axis kept level the way it lay (its size kept).
func _lay_down(node: Node3D) -> void:
	var size := node.global_basis.get_scale()
	var along := node.global_basis.y
	along.y = 0.0
	if along.length() < 0.01:
		along = Vector3.RIGHT
	var turned := Basis.looking_at(along.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2.0)
	node.global_basis = turned.scaled_local(size)


## Through the `Audio` service found by its node, not its name: the player's scripts are also loaded
## by tools run with `-s` (the grip solver), where an autoload's name does not compile.
func _sound(id: StringName) -> void:
	if not is_inside_tree():
		return
	var audio := get_tree().root.get_node_or_null(^"Audio")
	if audio != null:
		audio.call(&"play", id, global_position)


## The drinker's body (the nearest `Player` above), or null.
func _body() -> Node3D:
	var node := get_parent()
	while node != null and not node is Player:
		node = node.get_parent()
	return node as Node3D


## Where thrown things go: the drinker's own parent (the world he stands in).
func _world_root() -> Node:
	var body := _body()
	if body != null and body.get_parent() != null:
		return body.get_parent()
	return get_tree().current_scene if is_inside_tree() else null


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
