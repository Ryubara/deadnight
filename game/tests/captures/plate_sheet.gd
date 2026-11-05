extends Node
## Every calling card (titled) and every emblem on one sheet, for looking at the art (#1070):
## `gds godot -- --path game res://tests/captures/plate_sheet.tscn --resolution 1920x1080
## -- --out=<abs>/sheet.png [--page=frames]`. `--page=frames` is every plate frame (#1071) round a
## ticket-shaped box over a card, a roster row and a swatch. Not part of the game.

const MARGIN := 24.0
const CARD := Vector2(440.0, 120.0)
const GAP := 14.0


func _ready() -> void:
	var args := NetArgs.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	var ground := ColorRect.new()
	ground.color = Color("1b1d22")
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ground)
	var catalog := PlateCatalog.shipped()
	if args.get_string("page") == "frames":
		_frames(layer, catalog)
		await _finish(args.get_string("out"))
		return
	var cards := catalog.ids(PlateCatalog.CARD)
	for i in cards.size():
		var art := CardArt.new()
		art.size = CARD
		art.position = Vector2(MARGIN + (i % 4) * (CARD.x + GAP), MARGIN + (i / 4) * (CARD.y + GAP))
		art.card_id = cards[i]
		art.titled = true
		layer.add_child(art)
	var emblems := catalog.ids(PlateCatalog.EMBLEM)
	var top := MARGIN + 6.0 * (CARD.y + GAP) + 10.0
	for i in emblems.size():
		var art := EmblemArt.make(emblems[i], 96.0)
		art.position = Vector2(MARGIN + (i % 17) * 110.0, top + (i / 17) * 110.0)
		layer.add_child(art)
	await _finish(args.get_string("out"))


## Every frame on three plates: a box over a card, a row and a swatch.
func _frames(layer: CanvasLayer, catalog: PlateCatalog) -> void:
	var ids := catalog.ids(PlateCatalog.FRAME)
	for i in ids.size():
		var top := MARGIN + i * 140.0
		var box := Rect2(Vector2(MARGIN, top), Vector2(330.0, 66.0))
		var card := CardArt.new()
		card.position = box.position
		card.size = box.size
		card.card_id = &"cartoon"
		card.clip = HudStyle.ticket_points(Rect2(Vector2.ZERO, box.size), HudStyle.NOTCH * 0.6)
		card.motif_at = 0.54
		layer.add_child(card)
		var frame := FrameArt.new()
		frame.position = box.position
		frame.size = box.size
		frame.outline = card.clip
		frame.frame_id = ids[i]
		layer.add_child(frame)
		var row := FrameArt.new()
		row.position = Vector2(MARGIN + 370.0, top + 10.0)
		row.size = Vector2(700.0, 46.0)
		row.frame_id = ids[i]
		layer.add_child(row)
		var swatch := FrameArt.make(ids[i], Vector2(160.0, 56.0))
		swatch.ground = Color("1b1d22").lightened(0.1)
		swatch.position = Vector2(MARGIN + 1100.0, top + 5.0)
		layer.add_child(swatch)
		var name_label := Label.new()
		name_label.text = String(ids[i])
		name_label.position = Vector2(MARGIN + 1300.0, top + 20.0)
		layer.add_child(name_label)


func _finish(out: String) -> void:
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()
