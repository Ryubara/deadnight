class_name QuietCount
extends RefCounted
## Brings the process to a standstill that a count of objects can be read at. A fight or a menu
## holds objects of its own that come and go with it, a different number at every frame: a Tween
## with its tweeners (3 to 5 objects, a torn board in flight), every sound that plays (a budget
## voice and the engine's playback, 2 objects and up to 44 at once), the last playback each voice
## keeps until it is used again. A count taken at one moment of that swing against another moment's
## was 37 to 45 locally and 49 and 52 on the runners (Deadnight #1102), and it could not be told
## from a made mesh. Call `await QuietCount.settle(get_tree())` before each reading; what is left is
## what is held. The caller stands its own source of motion still first (the night's ticks, a bot).

## Frames given first, so the sounds the `Audio` service held back for a later frame
## (`DEFER_MAX_SECONDS`) have started and are stopped with the rest.
const DEFER_FRAMES := 12
## Frames the tweens may take to finish (the longest in the game, a torn board in flight, is a few
## seconds; a frame is a sixtieth).
const MAX_FRAMES := 900


## Stops every sound, waits for the tweens to finish and for the audio thread to take the stopped
## playbacks off. Returns whether no tween was left running. It asserts nothing, so no assertion
## object is made between two readings. `AudioSettle.until_idle` is a separate wait (the decode
## queue) that comes before the first reading.
static func settle(tree: SceneTree, service: AudioService = Audio) -> bool:
	for _i in DEFER_FRAMES:
		await tree.physics_frame
	service.stop_all()
	var frames := 0
	while not tree.get_processed_tweens().is_empty() and frames < MAX_FRAMES:
		await tree.physics_frame
		frames += 1
	await service.wait_for_mixer()
	# A frame for what the last tween's end freed.
	await tree.physics_frame
	return tree.get_processed_tweens().is_empty()
