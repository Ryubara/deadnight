# The golden hash of what bots send (bots plan, phase 1, scenario 25): four bots, 600 ticks, a fixed
# seed, zombies that come on a schedule and fall to three shots. The hash is of the commands'
# buttons, walking direction and view in 5 degree buckets (`BotTelemetry.signature`), so it moves
# when the bots decide differently and not with the last bit of a float. It is a constant: a change
# to it is a change to what the bots do, to be reviewed and then updated here. No world and no
# physics engine: the zombies are moved by hand, so the same seed gives the same night.
extends GdUnitTestSuite

const SEED := 4242
const TICKS := 600
const SEATS := 4
## A zombie comes at every seat this often (ticks), starting at the offset, from this far away, at
## this speed, and falls to this many shots at it.
const SPAWN_EVERY := 90
const SPAWN_OFFSET := 30
const SPAWN_DISTANCE := 20.0
const WALK_SPEED := 1.5
const SHOTS_TO_KILL := 3
const GOLDEN_HASH := 2644484567


## The hash of a night of four bots, and the shots they fired.
func _night() -> Dictionary:
	var rigs: Array[BotRig] = []
	for i in SEATS:
		var rig := BotRig.new(BotProfile.regular(), SEED + i)
		rig.bot.telemetry.hashing = true
		rig.position = Vector3(float(i) * 4.0 - 6.0, 0.0, 0.0)
		rigs.append(rig)
	var comers := RandomNumberGenerator.new()
	comers.seed = SEED
	var born_at := {}
	var next_id := 1
	for tick in TICKS:
		for rig in rigs:
			if tick % SPAWN_EVERY == SPAWN_OFFSET:
				var around: float = rig.bot.motor.yaw + deg_to_rad(comers.randf_range(-45.0, 45.0))
				var at := rig.position + Vector3(-sin(around), 0.0, -cos(around)) * SPAWN_DISTANCE
				rig.put_zombie(next_id, at)
				born_at[next_id] = rig.shot_ticks.size()
				next_id += 1
			for id: int in rig.zombies.keys():
				var zombie := rig.zombies[id]
				var toward := (rig.position - zombie.position).normalized()
				zombie.position += toward * WALK_SPEED * BotRig.STEP
				if rig.shot_ticks.size() - born_at[id] >= SHOTS_TO_KILL:
					rig.zombies.erase(id)
			rig.step()
	var all: Array[int] = []
	var shots := 0
	for rig in rigs:
		all.append(rig.bot.telemetry.command_hash)
		shots += rig.shot_ticks.size()
	return {"hash": hash(all), "shots": shots}


func test_scenario_25_the_golden_hash_of_four_bots_commands_holds() -> void:
	var first := _night()
	var second := _night()
	# The same seed makes the same night, to the bit, on one machine.
	assert_int(second["hash"]).is_equal(first["hash"])
	# And there is a fight in it: the hash is about more than standing still.
	assert_int(first["shots"]).is_greater(20)
	assert_int(first["hash"]).is_equal(GOLDEN_HASH)
