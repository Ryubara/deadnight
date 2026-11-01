extends Control
## Scripted capture of two clients through the loopback hub: four players, two of them with the same
## look, drawn from the point of view of player 1 (top row) and player 4 (bottom row). Each row
## should show the same four characters, the two twins told apart, every armband in its seat colour.
## Run it with Movie Maker (`--write-movie out.png --fixed-fps 10 --quit-after 40`).

const PREVIEW_SIZE := Vector2(400, 400)


func _ready() -> void:
	UIMotion.reduced = true
	var background := ColorRect.new()
	background.color = Color(0.05, 0.04, 0.09)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var hub := LoopbackHub.new()
	var ids: Array[int] = []
	for i in 4:
		ids.append(hub.connect_client())
	# Players 2 and 3 picked the same preset: the later one is shifted.
	var picks := [0, 3, 3, 6]
	for i in 4:
		hub.send_look(ids[i], CharacterLook.from_preset(picks[i]))
	hub.pump()
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	for viewer in [ids[0], ids[3]]:
		column.add_child(_row(hub, viewer, ids))
	await get_tree().create_timer(1.5).timeout
	print("beat lot frame ", Engine.get_process_frames())
	get_tree().quit()


func _row(hub: LoopbackHub, viewer: int, ids: Array[int]) -> Control:
	var registry: LookRegistry = hub.clients[viewer]
	var resolved := registry.resolved()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id in ids:
		var cell := VBoxContainer.new()
		var preview := LookPreview.new()
		preview.custom_minimum_size = PREVIEW_SIZE
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.angle = 0.3
		preview.show_look(resolved[id], registry.seats[id])
		cell.add_child(preview)
		var label := Label.new()
		var shift: int = (resolved[id] as CharacterLook).shift
		label.text = (
			"Player %d (seat %d)%s - seen by player %d"
			% [id, registry.seats[id] + 1, " - tint shifted" if shift > 0 else "", viewer]
		)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		row.add_child(cell)
	return row
