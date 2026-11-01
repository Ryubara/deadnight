extends Node3D
## Scripted capture of the boss zombie in Godot (Deadnight #98): the boss at game scale (x1.3)
## beside the Soldier (x0.8) on a dark lot, playing its five clips in order, then once more far
## away at 25 m with the lights low, so the lamp in its chest can be judged at night. Run with
## Movie Maker, an absolute path (the frame count is how long it runs):
##
##     godot --path game res://tests/captures/boss_tour.tscn --write-movie <abs>/boss.png \
##         --fixed-fps 10 --quit-after 150
## Prints CLIP <name> <frame> at each start, so frames can be matched to clips.

const BOSS := "res://assets/characters/zombie_boss/zombie_boss.glb"
const SOLDIER := "res://assets/characters/soldier/soldier.glb"
const CLIPS := ["Boss_Roar", "Boss_Walk", "Boss_Attack", "Boss_Stagger", "Boss_Death"]

var _frame := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.025, 0.04)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.4, 0.55)
	env.environment.ambient_light_energy = 0.35
	env.environment.glow_enabled = true
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-50, 30, 0)
	add_child(moon)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.08, 0.08, 0.09)
	ground.material_override = asphalt
	add_child(ground)
	var soldier: Node3D = (load(SOLDIER) as PackedScene).instantiate()
	soldier.scale = Vector3.ONE * 0.8
	soldier.position = Vector3(-1.8, 0, 0)
	add_child(soldier)
	var sp: AnimationPlayer = soldier.find_child("AnimationPlayer", true, false)
	for clip in sp.get_animation_list():  # the kit file names them CharacterArmature|Idle
		if clip.ends_with("Idle"):
			sp.play(clip)
	var boss := _boss(Vector3(0.6, 0, 0))
	var far := _boss(Vector3(4.0, 0, -24.0))
	far.find_child("AnimationPlayer", true, false).play("Boss_Walk")
	var cam := Camera3D.new()
	cam.position = Vector3(-0.9, 1.7, 4.6)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(-0.4, 1.25, 0.0))
	var bp: AnimationPlayer = boss.find_child("AnimationPlayer", true, false)
	for clip: String in CLIPS:
		print("CLIP ", clip, " ", _frame)
		bp.play(clip)
		if clip == "Boss_Walk":
			await _wait(3.3)  # a loop never finishes: two strides
		else:
			await bp.animation_finished
	print("CLIP night ", _frame)
	moon.light_energy = 0.05
	env.environment.ambient_light_energy = 0.08
	cam.look_at(far.position + Vector3(0, 1.5, 0))
	cam.fov = 35


func _boss(at: Vector3) -> Node3D:
	var boss: Node3D = (load(BOSS) as PackedScene).instantiate()
	boss.scale = Vector3.ONE * 1.3
	boss.position = at
	boss.rotation_degrees.y = -15
	add_child(boss)
	# The far mesh is for the game's visibility ranges; the capture shows the gameplay mesh.
	boss.find_child("Zombie_Far", true, false).visible = false
	# The import does not loop clips; the behaviour code loops Boss_Walk (clips.json says so).
	var player: AnimationPlayer = boss.find_child("AnimationPlayer", true, false)
	player.get_animation("Boss_Walk").loop_mode = Animation.LOOP_LINEAR
	return boss


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds).timeout


func _process(_delta: float) -> void:
	_frame += 1
