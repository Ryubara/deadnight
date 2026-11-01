extends Node
## Every catalogue weapon in the hand as the player sees it in the night (#285): the shoulder
## camera, at the hip and aimed, one weapon after another. Not part of the game. Run with Movie
## Maker: `godot --path game res://tests/captures/hand_view.tscn --fixed-fps 10
## --write-movie out.png --quit-after 400`. It prints `SHOT <weapon> <pose> <frame>` for the frame
## each pose is ready on.

const SECOND := 60
const POSE_SECONDS := 1.2
const WEAPONS: Array[StringName] = [
	&"pistol", &"smg", &"flare_gun", &"rifle", &"shotgun", &"crowbar"
]

var _night: Night
var _frame := 0


func _ready() -> void:
	var tuning := RulesFixture.tuning()
	tuning.rounds.intro_seconds = 1.0
	_night = Night.new()
	add_child(_night)
	await _night.start(Night.Mode.HUMAN, 7, tuning)
	await get_tree().physics_frame
	var player := _night.player()
	player.local_input = false
	player.camera_rig.yaw = PI
	player.camera_rig.snap_to(player.global_position)
	await _wait(SECOND)
	for id in WEAPONS:
		_night.server.combat.apply(CombatAction.give_weapon(_night.PLAYER_ID, id))
		_night.server.combat.apply(CombatAction.equip(_night.PLAYER_ID, id))
		for pose in ["hip", "aim"]:
			if pose == "aim":
				Input.action_press("aim")
			else:
				Input.action_release("aim")
			await _wait(roundi(POSE_SECONDS * SECOND))
			print("SHOT %s %s %d" % [id, pose, Engine.get_process_frames()])
	Input.action_release("aim")
	get_tree().quit()


func _wait(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame
