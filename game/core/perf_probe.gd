class_name PerfProbe
extends RefCounted
## Opt-in timers for the code that runs when something happens (a kill, a spawn): the time a
## labelled piece took is added to the current frame's total, and `PerfLog` writes the totals
## beside the frame's time. Off by default (`enabled`), when `begin` costs a static read and
## `end` returns at once, so the calls stay in the code they measure.
##
##     var t := PerfProbe.begin()
##     do_the_thing()
##     PerfProbe.end(&"thing", t)

## Whether to measure. `PerfLog` turns it on.
static var enabled := false

static var _usec: Dictionary[StringName, int] = {}
static var _counts: Dictionary[StringName, int] = {}


## The clock to give to `end`.
static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0


## Adds the time since `since` (from `begin`) to this frame's total for `label`.
static func end(label: StringName, since: int) -> void:
	if enabled:
		_usec[label] = _usec.get(label, 0) + Time.get_ticks_usec() - since


## Counts one occurrence of `label` this frame (a kill, a spawn).
static func count(label: StringName) -> void:
	if enabled:
		_counts[label] = _counts.get(label, 0) + 1


## The totals and counts of the frame so far, which start again from nothing.
static func take() -> Dictionary:
	var taken := {"usec": _usec, "counts": _counts}
	_usec = {}
	_counts = {}
	return taken
