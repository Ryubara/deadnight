class_name DeadSnapshot
extends RefCounted
## Where the standing dead were at one server tick, in the centimetres a frame carries them in, so
## that the server and the client that drew the frame hold the same numbers (`DeadField`).

var tick := 0
var ids := PackedInt32Array()
var positions := PackedVector3Array()


## The living zombies of `zombies` as a frame would show them.
static func of_sim(zombies: Dictionary[int, ZombieBody], at_tick: int) -> DeadSnapshot:
	var snapshot := DeadSnapshot.new()
	snapshot.tick = at_tick
	for zombie: ZombieBody in zombies.values():
		if not zombie.is_alive():
			continue
		snapshot.ids.append(zombie.id)
		snapshot.positions.append(
			Vector3(
				roundf(zombie.position.x * 100.0) * 0.01,
				roundf(zombie.position.y * 100.0) * 0.01,
				roundf(zombie.position.z * 100.0) * 0.01
			)
		)
	return snapshot


## The same from the entries a client decoded (`ZombieCodec.decode`).
static func of_entries(entries: Array[Dictionary]) -> DeadSnapshot:
	var snapshot := DeadSnapshot.new()
	for entry in entries:
		if int(entry["mode"]) == ZombieBody.Mode.DYING:
			continue
		snapshot.ids.append(int(entry["id"]))
		snapshot.positions.append(entry["position"])
	return snapshot
