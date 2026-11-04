class_name AudioSettle
extends RefCounted
## Lets the deferred sounds an earlier suite left queued on the `Audio` service finish decoding.
## The service decodes a few milliseconds of them every frame, so a test that counts the process's
## objects or resources across frames counts those decoded sounds as its own. Call
## `await AudioSettle.until_idle(get_tree())` before the first count; the count then starts from a
## quiet service (#1093; the kit's lesson on a count test that skipped the Audio queue).

## Frames the queue may take to empty before the count goes on regardless (the biggest bank is
## about 500 files at a few milliseconds a frame).
const MAX_FRAMES := 6000


## Waits, a frame at a time, until the service (the `Audio` autoload unless a test brings its own)
## has nothing left to decode. Returns the frames it waited (0 when the line was already empty).
static func until_idle(tree: SceneTree, service: AudioService = Audio) -> int:
	var frames := 0
	while service.decode_pending() > 0 and frames < MAX_FRAMES:
		await tree.process_frame
		frames += 1
	return frames
