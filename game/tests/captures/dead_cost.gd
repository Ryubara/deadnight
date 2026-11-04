extends Node
## What the dead's meeting with the bodies costs a server tick (#914), by the number of dead and of
## players: the microseconds a tick spends on the snapshot of where the dead stand, on filling each
## body's field, on stopping each body (`DeadBlock`) and on counting the pushes (`DeadShove`), and
## the client's share (decoding nothing: its snapshot from the frame's entries, and the fill). The
## dead are spread over the ground the bodies walk across, so the numbers are not the empty case.
##
## `godot --headless --path game res://tests/captures/dead_cost.tscn`  prints `DEADCOST {json}`
## rows.

const TICKS := 3000
const PLAYERS := [1, 4]
const DEAD := [0, 10, 20, 40]


func _ready() -> void:
	var lab := await DeadLab.start(self)
	var tuning := lab.tuning
	for players in PLAYERS:
		for count in DEAD:
			print("DEADCOST ", JSON.stringify(await _row(lab, tuning, players, count)))
	lab.world.queue_free()
	get_tree().quit()


func _row(lab: DeadLab, tuning: DeadContactTuning, players: int, count: int) -> Dictionary:
	lab.sim.zombies.clear()
	var centre := Vector3(38.0, 0.0, 4.0)
	var bodies: Array[Player] = []
	var fields: Array[DeadField] = []
	for i in players:
		var body := lab.world.add_body(centre + Vector3(float(i) * 2.0, 0.0, 0.0), false, false)
		var field := DeadField.new(tuning)
		body.dead = field
		bodies.append(body)
		fields.append(field)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in count:
		# Within a few metres of the bodies for a quarter of them, farther for the rest.
		var spread := 3.0 if i % 4 == 0 else 30.0
		lab.place(
			(
				centre
				+ Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
			)
		)
	var shove := DeadShove.new(lab.sim, tuning)
	var totals := {"snapshot": 0, "fill": 0, "block": 0, "shove": 0, "client": 0, "body_tick": 0}
	var command := PlayerCommand.new()
	command.move = Vector2(0.0, -1.0)
	var near := 0.0
	for t in TICKS:
		var began := Time.get_ticks_usec()
		var snapshot := DeadSnapshot.of_sim(lab.sim.zombies, t)
		totals["snapshot"] += Time.get_ticks_usec() - began
		for i in players:
			began = Time.get_ticks_usec()
			fields[i].fill(snapshot, bodies[i].global_position)
			totals["fill"] += Time.get_ticks_usec() - began
			near += fields[i].ids.size()
			# The body's tick with the dead, and without, to take the difference.
			began = Time.get_ticks_usec()
			bodies[i].tick(command)
			totals["body_tick"] += Time.get_ticks_usec() - began
			began = Time.get_ticks_usec()
			DeadBlock.apply(
				bodies[i], fields[i], bodies[i].global_position, Vector3(0.0, 0.0, -4.0), 0.35, 1.8
			)
			totals["block"] += Time.get_ticks_usec() - began
			began = Time.get_ticks_usec()
			shove.step(i + 1, fields[i], 1.0 / 60.0)
			totals["shove"] += Time.get_ticks_usec() - began
		# The client's: entries as a frame decodes them, then its snapshot and fill, once.
		var entries: Array[Dictionary] = []
		for zombie: ZombieBody in lab.sim.zombies.values():
			entries.append({"id": zombie.id, "mode": zombie.mode, "position": zombie.position})
		began = Time.get_ticks_usec()
		var seen := DeadSnapshot.of_entries(entries)
		fields[0].fill(seen, bodies[0].global_position)
		totals["client"] += Time.get_ticks_usec() - began
		if t % 2 == 0:
			lab.sim.tick(ZombieSim.STEP, {})
		for i in players:
			bodies[i].teleport(centre + Vector3(float(i) * 2.0, 0.0, 0.0))
	var row := {
		"players": players,
		"dead": count,
		"mean_near": snappedf(near / float(TICKS * players), 0.01)
	}
	for key: String in totals:
		row[key + "_us"] = snappedf(float(totals[key]) / float(TICKS), 0.01)
	for body in bodies:
		body.queue_free()
	return row
