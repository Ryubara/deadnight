extends Node
## How far the dead's planted foot slides at the pace of a round's walker and runner, lit and in
## the dark, on the real rig and clips of whatever build this runs in. Not part of the game. It is
## the measure of `tests/zombies/test_zombie_gait.gd` (a stationary view, the pose stepped at
## 60 Hz, the median speed of the foot over the frames in which it is planted), so a number here
## compares with that page's, and the same script reads the build before the gait follows the
## speed. Prints one line a case; run it headless:
##
##     godot --headless --path game res://tests/captures/gait_at_speeds.tscn -- --round=8
##
## Slide is the ground speed over the planted foot's backward speed: 1.0 is a foot that stays put on
## the ground, above 1 a foot that moves slower than the ground (it skates), below 1 faster.

const STEP := 1.0 / 60.0
## A planted foot is one within this share of its own lift from its lowest point.
const PLANTED := 0.2
const SECONDS := 5.0
const FEET: Array[String] = ["Foot.L", "Foot.R"]
## The types measured: the look of the model and the speed multiplier of its type.
const TYPES := {&"walker": 1.0, &"runner": 1.4}


func _ready() -> void:
	var args := _parse_args()
	var round_number := int(args.get("round", 8))
	var tuning := RoundTuning.new()
	var shipped: RulesTuning = load("res://gameplay/rules/default_tuning.tres")
	tuning = shipped.rounds
	for look: StringName in TYPES:
		var type := shipped.roster.type_of(look)
		var walking := minf(
			tuning.speed_for_round(round_number) * type.speed_multiplier, tuning.speed_cap
		)
		for lit in [true, false]:
			var pace := tuning.speed_on_ground(walking, lit)
			var foot := _foot_speed(look, pace)
			print(
				(
					"GAIT round=%d %s %s pace=%.2f foot=%.2f slide=%.2f"
					% [
						round_number,
						look,
						"lit " if lit else "dark",
						pace,
						foot,
						pace / maxf(foot, 0.001)
					]
				)
			)
	get_tree().quit()


func _foot_speed(look: StringName, pace: float) -> float:
	var view := ZombieView.new()
	add_child(view)
	view.setup(ZombieModels.scene(look), 1, 0.0, 0.7, look)
	(
		view
		. apply(
			{
				"id": 1,
				"position": Vector3.ZERO,
				"yaw": 0.0,
				"mode": ZombieBody.Mode.CHASE,
				"episode": 1,
				"speed": pace,
			},
			STEP
		)
	)
	view.tree.advance(0.0)
	var skeleton := view.model().find_child("Skeleton3D", true, false) as Skeleton3D
	var bones: Array[int] = []
	for bone_name in FEET:
		bones.append(skeleton.find_bone(bone_name))
	view.tree.advance(0.5)
	var along: Array = []
	var up: Array = []
	for _i in roundi(SECONDS / STEP):
		view.tree.advance(STEP)
		var row_along: Array[float] = []
		var row_up: Array[float] = []
		for bone in bones:
			var at := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
			row_along.append(at.z)
			row_up.append(at.y)
		along.append(row_along)
		up.append(row_up)
	var speeds: Array[float] = []
	for j in bones.size():
		var low := INF
		var high := -INF
		for i in up.size():
			low = minf(low, up[i][j])
			high = maxf(high, up[i][j])
		var limit: float = low + (high - low) * PLANTED
		for i in range(1, up.size()):
			if up[i][j] <= limit and up[i - 1][j] <= limit:
				speeds.append(absf(along[i][j] - along[i - 1][j]) / STEP)
	view.queue_free()
	speeds.sort()
	return speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0


func _parse_args() -> Dictionary:
	var parsed := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else true
	return parsed
