# The predicting client and the server in a loop with the network's delay between them, in one
# dimension and with the real `Reconciler`: a client that freezes for a moment (its engine then
# runs up to eight ticks at once, and the server takes only the newest of the commands that come
# together) must come back to where the server has the player, at any round trip, and not be thrown
# further off by every correction (#483).
extends GdUnitTestSuite

const STEP_METRES := 0.1
## Engine ticks a frame runs to catch up after a freeze (`max_physics_steps_per_frame`).
const CATCH_UP_TICKS := 8
const WALK_UNTIL := 700
const TICKS := 1400
## How far apart the two may end, after both stopped, and how far a freeze may throw the client.
const SETTLED := 0.1
const MOST_OFF := 2.5


## One run: `rtt_ticks` is the round trip in ticks, the client freezes for `stall` ticks from tick
## 300. Returns `{"final": client - server at the end, "worst": the largest |client - server|
## after the freeze, less the lead a delay gives}`.
func _run(rtt_ticks: int, stall: int) -> Dictionary:
	var lag := rtt_ticks / 2
	var reconciler := Reconciler.new()
	var client := 0.0
	var server := 0.0
	var seq := 0
	var last_ack := 0
	var up: Array[Vector3i] = []
	var down: Array[Vector3] = []
	var back := 300 + stall
	var worst := 0.0
	for t in TICKS:
		var frozen := t >= 300 and t < back
		if not frozen:
			var ticks := CATCH_UP_TICKS if (t == back and stall > 0) else 1
			for _i in ticks:
				var walking := t < WALK_UNTIL
				if walking:
					client += STEP_METRES
				seq += 1
				reconciler.record(seq, Vector3(client, 0, 0))
				up.append(Vector3i(t + lag, seq, 1 if walking else 0))
			while not down.is_empty() and int(down[0].x) <= t:
				var frame: Vector3 = down.pop_front()
				client += reconciler.correction(int(frame.y), Vector3(frame.z, 0, 0)).x
		var newest := Vector3i(0, -1, 0)
		while not up.is_empty() and up[0].x <= t:
			newest = up.pop_front()
		if newest.y != -1:
			last_ack = newest.y
			if newest.z == 1:
				server += STEP_METRES
		if t % 2 == 0:
			down.append(Vector3(t + lag, last_ack, server))
		if t > back + 2 * rtt_ticks and t < WALK_UNTIL:
			worst = maxf(worst, absf(client - server) - STEP_METRES * lag * 2)
	return {"final": client - server, "worst": worst}


func test_a_freeze_never_throws_the_client_off_at_any_round_trip() -> void:
	for rtt_ms in [50, 100, 200, 300, 400]:
		for stall in [0, 30, 120, 300]:
			var result := _run(roundi(rtt_ms / 16.667), stall)
			var label := "rtt %d ms, freeze %d ticks" % [rtt_ms, stall]
			(
				assert_float(absf(result["final"]))
				. override_failure_message(
					"%s: ended %s m from the server" % [label, result["final"]]
				)
				. is_less(SETTLED)
			)
			(
				assert_float(result["worst"])
				. override_failure_message("%s: thrown %s m off" % [label, result["worst"]])
				. is_less(MOST_OFF)
			)
