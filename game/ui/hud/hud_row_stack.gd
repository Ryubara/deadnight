class_name HudRowStack
extends Control
## A column of one-line rows (the point gains, the event and notice lists) whose rows ease into
## their slots. Every row has a slot: the sum of the heights of the rows above it and the gaps. When
## a row leaves, or a taller row joins, the rows below it slide to their new slots; a new row rises
## into its slot while it fades in. The slots are laid out one under the other, so rows that
## arrive in the same frame never overlap, and every row moves by the same fraction of its
## remaining distance, so the gap between two rows never shrinks below the slot gap.
##
## The motion is the view's: `advance(delta)` steps it by seconds the owner passes in (the same
## fixed step that fades the rows), so a test or a capture needs no wall time. The height this
## part reports eases too, so what sits under the stack follows the rows. With reduced motion
## every row is in its slot at once.

## Seconds in which a row covers about 95% of its distance to its slot.
const SETTLE_TIME := 0.18
## How far below its slot a new row starts, and the seconds it takes to fade in.
const ENTER_RISE := HudStyle.MD
const ENTER_TIME := 0.18
## Closer than this to its slot (canvas units) a row is there.
const SNAP := 0.25

## Space between two rows.
var gap := HudStyle.GAP

var _rows: Array[Control] = []
## Fade-in progress by row, 0 to 1.
var _enter: Dictionary = {}
var _height := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	var width := 0.0
	for row in _rows:
		width = maxf(width, row.get_combined_minimum_size().x)
	return Vector2(width, _height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		for row in _rows:
			_fit(row)


## Puts `row` last. It starts a little below its slot and fades in (at once with reduced motion).
func add_row(row: Control) -> void:
	_rows.append(row)
	add_child(row)
	row.minimum_size_changed.connect(_on_row_resized.bind(row))
	_fit(row)
	if UIMotion.reduced:
		_enter[row] = 1.0
		_snap()
		return
	_enter[row] = 0.0
	# Below its slot, and never above the bottom of the row before it: when that row has not got
	# to its own slot yet (rows came in faster than they settle) the new one starts under it.
	var start := target_y(row) + ENTER_RISE
	if _rows.size() > 1:
		var above := _rows[_rows.size() - 2]
		start = maxf(start, above.position.y + above.get_combined_minimum_size().y + gap)
	row.position.y = start
	row.self_modulate.a = 0.0


## Takes `row` out and frees it. The rows below it slide up into the space.
func remove_row(row: Control) -> void:
	_rows.erase(row)
	_enter.erase(row)
	remove_child(row)
	row.queue_free()
	if UIMotion.reduced:
		_snap()


## Where `row` belongs: below the rows above it. A row that is not here has no slot (0).
func target_y(row: Control) -> float:
	var y := 0.0
	for other in _rows:
		if other == row:
			return y
		y += other.get_combined_minimum_size().y + gap
	return 0.0


## The height all the rows need, the last one's bottom edge.
func target_height() -> float:
	var total := 0.0
	for row in _rows:
		total += row.get_combined_minimum_size().y
	return total + gap * maxi(_rows.size() - 1, 0)


## True when every row is in its slot and the height has caught up.
func is_settled() -> bool:
	if absf(_height - target_height()) > SNAP:
		return false
	for row in _rows:
		if absf(row.position.y - target_y(row)) > SNAP or float(_enter[row]) < 1.0:
			return false
	return true


## Steps the rows toward their slots by `delta` seconds: each covers the same fraction of what is
## left, so the motion is the same at any frame rate.
func advance(delta: float) -> void:
	if UIMotion.reduced:
		_snap()
		return
	var fraction := 1.0 - exp(-delta * 3.0 / SETTLE_TIME)
	for row in _rows:
		var goal := target_y(row)
		var y := lerpf(row.position.y, goal, fraction)
		row.position.y = goal if absf(y - goal) <= SNAP else y
		var entered := minf(float(_enter[row]) + delta / ENTER_TIME, 1.0)
		_enter[row] = entered
		row.self_modulate.a = entered
	var height := lerpf(_height, target_height(), fraction)
	_set_height(target_height() if absf(height - target_height()) <= SNAP else height)


func _snap() -> void:
	for row in _rows:
		_enter[row] = 1.0
		row.self_modulate.a = 1.0
		row.position.y = target_y(row)
	_set_height(target_height())


func _set_height(value: float) -> void:
	if is_equal_approx(value, _height):
		return
	_height = value
	update_minimum_size()


func _fit(row: Control) -> void:
	var minimum := row.get_combined_minimum_size()
	row.position.x = 0.0
	row.size = Vector2(maxf(size.x, minimum.x), minimum.y)


func _on_row_resized(row: Control) -> void:
	_fit(row)
	update_minimum_size()
