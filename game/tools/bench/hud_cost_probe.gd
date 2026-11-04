class_name HudCostProbe
extends Node
## What the HUD costs to draw (#948): the draw calls of a frame with each part, and each control
## inside the parts, hidden in turn, and the redraws a second (a `draw` signal is one redraw of one
## canvas item; the engine also redraws a control whose `scale` or `size` changes). Counts, not
## times: they hold on a loaded machine. Not part of the play.
##
## `report` is for a HUD that stands still (a capture); `watch` and `redraws_per_second` count what
## a running night redraws.

## Frames let go before a count is read, so a hidden control's batches are gone from the frame.
const SETTLE_FRAMES := 3
## Frames a draw count is the mean of.
const COUNT_FRAMES := 3
## A night's HUD cost is read in this many rounds of up and hidden, of this many frames each.
const NIGHT_ROUNDS := 16
const NIGHT_FRAMES := 12

## Redraws counted since `watch`: {path under the HUD: draws}.
var redraws: Dictionary[String, int] = {}
var _hud: Hud
var _counting := false
var _seconds := 0.0
var _first_frame := 0


## Draw calls of the frame the engine last drew (the whole viewport: with no 3D under the HUD, the
## HUD's own).
static func draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## The mean draw calls over a few frames, after letting the scene settle.
func count() -> int:
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	var total := 0
	for _i in COUNT_FRAMES:
		await get_tree().process_frame
		total += draw_calls()
	return total / COUNT_FRAMES


## Draw calls with everything up, with each direct child of the HUD hidden alone, and with each
## visible control below the parts hidden alone (only those that change the count): `"all"`,
## `"parts"` {name: calls the part makes}, `"controls"` {path: calls it makes}.
func report(hud: Hud, deep := true) -> Dictionary:
	var all := await count()
	var parts := {}
	var controls := {}
	for child in hud.get_children():
		if not (child is CanvasItem) or not (child as CanvasItem).visible:
			continue
		parts[_name_of(child)] = all - await _without(child as CanvasItem)
	if deep:
		for node in _controls(hud):
			var made := all - await _without(node)
			if made != 0:
				controls[str(hud.get_path_to(node))] = made
	return {"all": all, "parts": parts, "controls": controls}


## Waits until `hudalive` dead stand in the night, counts the HUD's redraws for `hudsecs` seconds
## of real play, then its draw calls (each part hidden in turn), and prints both as
## `HUDCOST_NIGHT {json}` (`ablation.gd`: `hudcost=1`). Ends the run after it when `hudquit=1`.
func run_night(args: NetArgs, night: Night, screen: Control) -> void:
	var hud: Hud = null
	for child in screen.get_children():
		if child is Hud:
			hud = child
	if hud == null:
		return
	var alive := args.get_int("hudalive", 60)
	while night.state != null and night.state.zombies.size() < alive and not night.state.over:
		await get_tree().process_frame
	watch(hud)
	await get_tree().create_timer(args.get_float("hudsecs", 10.0)).timeout
	var frames := Engine.get_process_frames() - _first_frame
	var row := {
		"dead": night.state.zombies.size(),
		"round": night.state.round_number(),
		"seconds": snappedf(_seconds, 0.1),
		"frames": frames,
		"redraws_per_second": total_redraws_per_second(),
		"redraws_per_frame": snappedf(_total() / maxf(frames, 1.0), 0.01),
		"redraw_rows": redraws_per_second().slice(0, 12),
	}
	_counting = false
	# The HUD's draw calls in the real frame (the lot, the dead and the HUD): the frame with it up
	# less the frame with it hidden, alternated so the lot's own changes average out.
	var shown := 0.0
	var hidden := 0.0
	for _i in NIGHT_ROUNDS:
		hud.visible = true
		shown += await _mean_draws(NIGHT_FRAMES)
		hud.visible = false
		hidden += await _mean_draws(NIGHT_FRAMES)
	hud.visible = true
	row["frame_draw_calls"] = snappedf(shown / NIGHT_ROUNDS, 0.1)
	row["hud_draw_calls"] = snappedf((shown - hidden) / NIGHT_ROUNDS, 0.1)
	# And each part's share, the same way (a column of parts under one name).
	var parts := {}
	for child in hud.get_children():
		if not (child is CanvasItem) or not (child as CanvasItem).visible:
			continue
		var up := 0.0
		var down := 0.0
		for _i in NIGHT_ROUNDS:
			(child as CanvasItem).visible = true
			up += await _mean_draws(NIGHT_FRAMES)
			(child as CanvasItem).visible = false
			down += await _mean_draws(NIGHT_FRAMES)
		(child as CanvasItem).visible = true
		parts[_name_of(child)] = snappedf((up - down) / NIGHT_ROUNDS, 0.1)
	row["parts"] = parts
	print("HUDCOST_NIGHT ", JSON.stringify(row))
	if args.get_int("hudquit") == 1:
		get_tree().quit()


## Counts every redraw of every canvas item below the HUD from now on.
func watch(hud: Hud) -> void:
	_hud = hud
	redraws.clear()
	_seconds = 0.0
	_counting = true
	_first_frame = Engine.get_process_frames()
	_connect_all(hud)
	hud.child_entered_tree.connect(_connect_all)


func _process(delta: float) -> void:
	if _counting:
		_seconds += delta


## Redraws a second, by control, since `watch`, busiest first: [[path, per second]].
func redraws_per_second() -> Array:
	var rows: Array = []
	for path in redraws:
		rows.append([path, snappedf(redraws[path] / maxf(_seconds, 0.001), 0.1)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows


## All redraws a second.
func total_redraws_per_second() -> float:
	return snappedf(_total() / maxf(_seconds, 0.001), 0.1)


func _total() -> int:
	var total := 0
	for path in redraws:
		total += redraws[path]
	return total


## The mean draw calls of a few frames, after two to settle.
func _mean_draws(frames: int) -> float:
	for _i in 2:
		await get_tree().process_frame
	var total := 0
	for _i in frames:
		await get_tree().process_frame
		total += draw_calls()
	return float(total) / frames


## A part's name, and for a column the names of the parts in it (`Round+Objective`): the engine's
## own names for made-in-code containers (`@VBoxContainer@84`) change with every node added.
func _name_of(node: Node) -> String:
	if not str(node.name).begins_with("@"):
		return str(node.name)
	var names: PackedStringArray = []
	for child in node.get_children():
		names.append(_name_of(child))
	return "+".join(names)


func _without(node: CanvasItem) -> int:
	node.visible = false
	var drawn := await count()
	node.visible = true
	return drawn


## The visible controls below the parts: each is hidden alone, so a control whose children make the
## draws shows with them (read the tree, not a sum).
func _controls(hud: Hud) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	for child in hud.get_children():
		_collect(child, found)
	return found


func _collect(node: Node, found: Array[CanvasItem]) -> void:
	for child in node.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			found.append(child as CanvasItem)
			_collect(child, found)


func _connect_all(node: Node) -> void:
	if node is CanvasItem:
		var item := node as CanvasItem
		var on_draw := _on_draw.bind(item)
		if not item.draw.is_connected(on_draw):
			item.draw.connect(on_draw)
	for child in node.get_children():
		_connect_all(child)


func _on_draw(node: CanvasItem) -> void:
	if not _counting:
		return
	var key := str(_hud.get_path_to(node)) if _hud.is_ancestor_of(node) else str(node.name)
	redraws[key] = redraws.get(key, 0) + 1
