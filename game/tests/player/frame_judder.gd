class_name FrameJudder
extends RefCounted
## How uneven a point's path on the screen is, frame to frame: the numbers the side-on smoothness
## test and capture report (docs/research/physics-interpolation.md).
##
## A point that moves at a steady speed, or eases in and out, has a small second difference
## `x[i + 1] - 2 x[i] + x[i - 1]`. A body drawn at its last physics tick while the camera is blended
## between ticks steps by a whole tick of travel every few frames, which is a second difference
## of that size. The unit is whatever the positions are in (pixels for the screen).


## The change from each position to the next.
static func deltas(positions: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(1, positions.size()):
		out.append(positions[i] - positions[i - 1])
	return out


## `x[i + 1] - 2 x[i] + x[i - 1]` for every frame that has both neighbours.
static func second_differences(positions: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(1, positions.size() - 1):
		out.append(positions[i + 1] - 2.0 * positions[i] + positions[i - 1])
	return out


## The largest absolute value.
static func peak(values: PackedFloat64Array) -> float:
	var highest := 0.0
	for value in values:
		highest = maxf(highest, absf(value))
	return highest


## The distance between the smallest and the largest value.
static func peak_to_peak(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var lowest := values[0]
	var highest := values[0]
	for value in values:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return highest - lowest


## The root mean square.
static func rms(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value * value
	return sqrt(total / float(values.size()))


## Peak and RMS of the second differences, and the mean travel per frame, as a dictionary.
static func summary(positions: PackedFloat64Array) -> Dictionary:
	var second := second_differences(positions)
	var moves := deltas(positions)
	var mean_move := 0.0
	for move in moves:
		mean_move += absf(move)
	if not moves.is_empty():
		mean_move /= float(moves.size())
	return {&"peak": peak(second), &"rms": rms(second), &"mean_move": mean_move}
