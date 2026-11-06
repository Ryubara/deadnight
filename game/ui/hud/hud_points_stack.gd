class_name HudPointsStack
extends Container
## The rows of the players' column, top to bottom: your own box, the teammates' boxes, and the
## bots' strip of chips. A teammate's box is one to a row, or `mate_columns` to a row when the
## column is short of room (`HudPoints.room`): the rows are laid out here and not by a box or grid
## container, which would add a node to every night's HUD (the canvas-item budget counts them).
##
## Whatever is not a teammate's box (your own box, the chips) takes a row of its own, the column's
## whole width. A teammate row is `mate_columns` cells wide whatever it holds: the last teammate of
## an odd party stands in the left cell, as wide as the others.

## How many teammates' boxes stand in a row.
var mate_columns := 1:
	set(value):
		value = maxi(value, 1)
		if value != mate_columns:
			mate_columns = value
			update_minimum_size()
			queue_sort()
## The space between rows and between cells.
var gap := float(HudStyle.GAP)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort()
	elif what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_minimum_size()


func _get_minimum_size() -> Vector2:
	var found := Vector2.ZERO
	for row: Array in _rows(mate_columns):
		found.x = maxf(found.x, _row_size(row).x)
	found.y = height_at(mate_columns)
	return found


## The height the rows would take with `columns` teammates to a row, from the boxes and the strip
## as they are now (the chips are a little taller than their constant says: a label's own line).
func height_at(columns: int) -> float:
	var rows := _rows(columns)
	var total := gap * float(maxi(rows.size() - 1, 0))
	for row: Array in rows:
		total += _row_size(row).y
	return total


## The rows as arrays of controls, in order.
func _rows(columns: int) -> Array[Array]:
	var rows: Array[Array] = []
	var run: Array = []
	for child in get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if columns > 1 and _is_mate(control):
			run.append(control)
			if run.size() == columns:
				rows.append(run)
				run = []
			continue
		if not run.is_empty():
			rows.append(run)
			run = []
		rows.append([control])
	if not run.is_empty():
		rows.append(run)
	return rows


func _is_mate(control: Control) -> bool:
	return control is HudPlayerBox and not (control as HudPlayerBox).is_local


## A row's own size: its cells side by side, as tall as the tallest.
func _row_size(row: Array) -> Vector2:
	var found := Vector2.ZERO
	for control: Control in row:
		var cell := control.get_combined_minimum_size()
		found.x += cell.x
		found.y = maxf(found.y, cell.y)
	found.x += gap * float(row.size() - 1)
	return found


func _sort() -> void:
	var y := 0.0
	for row: Array in _rows(mate_columns):
		var tall := _row_size(row).y
		var cells := mate_columns if _is_mate(row[0]) else 1
		var width := (size.x - gap * float(cells - 1)) / float(cells)
		for i in row.size():
			fit_child_in_rect(row[i], Rect2(float(i) * (width + gap), y, width, tall))
		y += tall + gap
