## Prints how every weapon's size fits the Soldier's hand (Deadnight #460): the hand's own numbers,
## measured on his skin, then each weapon's grip, guard and length ratios at its hold's size
## (`WeaponFit`; docs/design/weapon-hold.md, "The size rule").
##
##     godot --headless --path game -s res://tests/art/measure_weapon_fit.gd
## Prints `HAND` and `FIT` lines.
extends SceneTree

## Every weapon model and the size it is held at (its hold file, or for a model with none its scene,
## `model_scale` and `model_length`).
const MODELS := {
	"revolver": "res://gameplay/player/holds/pistol.tres",
	"flare_gun": "res://gameplay/player/holds/flare_gun.tres",
	"tommy_gun": "res://gameplay/player/holds/smg.tres",
	"lever_rifle": "res://gameplay/player/holds/rifle.tres",
	"double_shotgun": "res://gameplay/player/holds/shotgun.tres",
	"baseball_bat": "res://gameplay/player/holds/melee.tres",
	"crowbar": "res://gameplay/player/holds/crowbar.tres",
	"ppsh": "res://gameplay/player/holds/ppsh.tres",
	"mp5": "res://gameplay/player/holds/mp5.tres",
	"m4a1": "res://gameplay/player/holds/m4a1.tres",
	# #797's models, at the size their holds will give them (docs/research/weapon-models.md).
	"service_pistol":
	{
		"scene": "res://assets/weapons/service_pistol/service_pistol.glb",
		"model_scale": 1.95,
		"model_length": 0.25
	},
	"ray_gun":
	{
		"scene": "res://assets/weapons/ray_gun/ray_gun.glb",
		"model_scale": 2.275,
		"model_length": 0.278
	},
	"freeze_gun":
	{
		"scene": "res://assets/weapons/freeze_gun/freeze_gun.glb",
		"model_scale": 1.3,
		"model_length": 0.908
	},
}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var solver := GripSolver.new(root)
	await process_frame
	_hand(solver)
	for name: String in MODELS:
		var hold := _hold(MODELS[name])
		var model := (load(hold.scene) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var fit := WeaponFit.measure(model, hold.model_scale, hold.model_length)
		print(
			(
				"FIT %s model_scale %.3f grip/fingers %.2f guard/finger %.2f length/height %.2f"
				% [name, hold.model_scale, fit.grip, fit.guard, fit.length]
			)
		)
		model.free()
	quit(0)


## A model's hold file, or a hold made from a size for a model with none.
func _hold(entry: Variant) -> WeaponHold:
	if entry is String:
		return load(entry) as WeaponHold
	var hold := WeaponHold.new()
	hold.scene = entry.scene
	hold.model_scale = entry.model_scale
	hold.model_length = entry.model_length
	return hold


## The right hand in the game, along the handle line: the whole fist, the part below the index
## knuckle (the fingers a pistol grip must fill), and the index finger's thickness.
func _hand(solver: GripSolver) -> void:
	var frame := solver.handle_frame("R")
	var hand := solver.hand_world("R")
	var along: Vector3 = (hand.basis * (frame.along as Vector3)).normalized()
	var knuckle := hand * solver._in_hand("R", "Index2")
	var points := solver.contact.skin_points("R")
	var low := INF
	var high := -INF
	for part: String in points:
		for p: Vector3 in points[part]:
			low = minf(low, (p - knuckle).dot(along))
			high = maxf(high, (p - knuckle).dot(along))
	var index_low := INF
	var index_high := -INF
	for p: Vector3 in points["index_mid"]:
		index_low = minf(index_low, p.dot(along))
		index_high = maxf(index_high, p.dot(along))
	print(
		(
			"HAND fist %.3f m along the handle line, %.3f m below the index knuckle; index finger %.3f m"
			% [high - low, -low, index_high - index_low]
		)
	)
