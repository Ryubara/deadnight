class_name AudioSettle
extends RefCounted
## Lets the deferred sounds an earlier suite left queued on the `Audio` service finish decoding, and
## ends its background load. The service works on both a few milliseconds of every frame, so a test
## that counts the process's objects or resources across frames counts those sounds as its own. Call
## `await AudioSettle.until_idle(get_tree())` before the first count; the count then starts from a
## quiet service (#1093 and #1102; the kit's lessons on a count test that skipped the Audio queue).

## Frames the queue may take to empty before the count goes on regardless (the biggest bank is
## about 500 files at a few milliseconds a frame).
const MAX_FRAMES := 6000


## Ends the work the `Audio` service does on its own in every frame, so that a count starts from a
## quiet service: the menu's background load of every sound (`start_background_preload`, begun by
## the main menu in any suite that builds it, and ended by the night's warm-up in the game), and the
## deferred queue. Both go on in the frames of whatever suite runs next (Deadnight #1102: the UI
## sounds were loaded and decoded inside `test_hud_shapes`, 20 to 40 objects). The background load
## is stopped where it is, as the warm-up does (what it left unloaded is loaded when played); the
## queue is waited for. The autoload is settled too when `service` is a service of the test's own,
## since it runs beside it. Returns the frames it waited (0 when the line was already empty).
static func until_idle(tree: SceneTree, service: AudioService = Audio) -> int:
	service.stop_background_preload()
	Audio.stop_background_preload()
	var frames := 0
	while (service.decode_pending() > 0 or Audio.decode_pending() > 0) and frames < MAX_FRAMES:
		await tree.process_frame
		frames += 1
	return frames
