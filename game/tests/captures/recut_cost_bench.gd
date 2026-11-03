extends "res://tests/captures/crowd_cost_bench.gd"
## What the re-cut skin costs a frame (Deadnight #787): the crowd bench (a crowd running the lot,
## no HUD) with
## every weapon that can be re-cut held out in front of the camera, a fan of them near and large,
## more than a
## night ever shows (four soldiers hold one each, at arm's length and smaller). `--recut=1`
## dresses them in
## `RecutSkin`, `--recut=0` leaves the palette material, so the difference of the two is the skin:
## its draw
## calls (none added: it stands in the surface's material) and its fill. Not part of the game:
## `tools/web_smoke/recut_cost.py` exports a copy of the project that starts on this scene.
## Extra arguments: `--recut=0|1`, `--copies=N` (rings of the eight weapons, default 2).

const DISTANCE := 1.6
const SPREAD := 0.55

var _recut := true
var _weapons: Array[Node3D] = []


func _ready() -> void:
	await super._ready()
	_recut = int(_args.get("recut", 1)) != 0
	var copies := int(_args.get("copies", 2))
	var ids: Array = UpgradeTuning.new().weapons
	var at := 0
	for copy in copies:
		for id in ids:
			var hold := WeaponHoldMap.hold_for(id)
			if hold == null:
				continue
			var model := (load(hold.scene) as PackedScene).instantiate() as Node3D
			model.scale = Vector3.ONE * hold.model_scale
			_camera.add_child(model)
			var column := at % 4
			var row := at / 4
			model.position = Vector3(
				(column - 1.5) * SPREAD * 1.4, (row - 1.0) * SPREAD * 0.8, -DISTANCE - 0.1 * row
			)
			model.rotation = Vector3(0.0, PI * 0.5 + 0.4, 0.0)
			if _recut:
				RecutSkin.wear(model)
			_weapons.append(model)
			at += 1
	_extra = {"recut": _recut, "weapons": _weapons.size()}
