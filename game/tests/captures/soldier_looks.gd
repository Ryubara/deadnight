extends Node3D
## Scripted capture of the eight starting looks (Deadnight #100): every preset in parts.json,
## assembled by SoldierLook, side by side holding the lever rifle and playing its clips (Aim,
## Fire, Reload). Run with Movie Maker:
##
##     godot --path game --write-movie <out>.png --fixed-fps 10 --quit-after 60 \
##         res://tests/captures/soldier_looks.tscn

const RIFLE := "res://assets/weapons/lever_rifle/lever_rifle.glb"
## The gun hold on Index1.R (docs/design/animation.md, Weapons in the hand).
const HOLD_GUN := Transform3D(
	Basis(
		Vector3(-0.062527, -0.997926, -0.015303),
		Vector3(0.118606, -0.022655, 0.992683),
		Vector3(-0.990971, 0.060254, 0.119776)
	),
	Vector3(-0.039563, 0.197228, -0.070351)
)
const SPACING := 1.1
const SCALE := 0.8
const CLIPS := ["Aim_Rifle", "Fire_Rifle", "Aim_Rifle", "Reload_Rifle"]

var _players: Array[AnimationPlayer] = []


func _ready() -> void:
	var presets := SoldierLook.presets()
	var n := presets.size()
	for i in n:
		var model := SoldierLook.instantiate()
		SoldierLook.apply(model, presets[i])
		model.scale = Vector3.ONE * SCALE
		model.position = Vector3((i - (n - 1) / 2.0) * SPACING, 0, 0)
		model.rotation.y = deg_to_rad(60.0)
		add_child(model)
		var sk: Skeleton3D = model.find_child("Skeleton3D", true, false)
		var hand := BoneAttachment3D.new()
		hand.bone_name = "Index1.R"
		sk.add_child(hand)
		var rifle: Node3D = (load(RIFLE) as PackedScene).instantiate()
		rifle.transform = HOLD_GUN
		hand.add_child(rifle)
		var label := Label3D.new()
		label.text = presets[i].name
		label.position = Vector3(model.position.x, -0.15, 0.6)
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = Color("e9e2cf")
		add_child(label)
		_players.append(model.find_child("AnimationPlayer", true, false))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 7.2)
	cam.fov = 42
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1b1a22")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	_cycle()


func _cycle() -> void:
	for clip: String in CLIPS:
		for p in _players:
			p.play(clip)
		await get_tree().create_timer(maxf(_players[0].get_animation(clip).length, 0.8)).timeout
	_cycle()
