class_name StageGovernor
extends RefCounted
## Watches how long the frames take while the stage is live and says when to give it up. Auto mode
## only: it steps the stage down a level (live, half resolution, a still) when the mean frame over
## a window is too long, and a machine that is far too slow (a software renderer: several frames a
## second) goes straight to the still. It never steps back up in the same session, so a machine
## that struggles does not flicker between looks.

enum Level { LIVE, HALF, STILL }

## Frames ignored at the start (the scene is still loading and compiling).
const WARMUP := 12
## A window ends after this many frames, or after `WINDOW_SECONDS` once it holds `MIN_FRAMES`, so
## a very slow machine is judged in a couple of seconds, not a minute.
const WINDOW := 90
const WINDOW_SECONDS := 1.5
const MIN_FRAMES := 6
## Mean frame time (seconds) above which the level drops: about 40 and 25 frames a second.
const LIMIT_LIVE := 0.025
const LIMIT_HALF := 0.040
## Above this mean frame (about 8 frames a second) the stage goes straight to the still.
const LIMIT_SEVERE := 0.12
## One frame counts for at most this much, so a single long frame (a shader compiling) is not a
## trend.
const CLAMP := 0.5

var level := Level.LIVE

var _seen := 0
var _sum := 0.0
var _count := 0


## Whether an adapter name is a renderer that draws on the CPU (a browser's SwiftShader, Mesa's
## llvmpipe, Windows' basic render driver): the stage does not go live on one.
static func is_software(adapter: String) -> bool:
	var lower := adapter.to_lower()
	for word in ["swiftshader", "llvmpipe", "softpipe", "software", "basic render"]:
		if lower.contains(word):
			return true
	return false


## Feeds one frame; returns true when the level changed.
func feed(delta: float) -> bool:
	if level == Level.STILL:
		return false
	_seen += 1
	if _seen <= WARMUP:
		return false
	_sum += minf(delta, CLAMP)
	_count += 1
	var done := _count >= WINDOW or (_sum >= WINDOW_SECONDS and _count >= MIN_FRAMES)
	if not done:
		return false
	var mean := _sum / _count
	_sum = 0.0
	_count = 0
	var limit := LIMIT_LIVE if level == Level.LIVE else LIMIT_HALF
	if mean <= limit:
		return false
	level = Level.STILL if mean > LIMIT_SEVERE or level == Level.HALF else Level.HALF
	return true
