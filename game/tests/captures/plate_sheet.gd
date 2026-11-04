extends Node
## Every calling card (titled) and every emblem on one sheet, for looking at the art (#1070):
## `gds godot -- --path game res://tests/captures/plate_sheet.tscn --resolution 1920x1080
## -- --out=<abs>/sheet.png [--page=emblems]`. Not part of the game.

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
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out := args.get_string("out")
	if out != "":
		get_viewport().get_texture().get_image().save_png(out)
		print("SAVED ", out)
	get_tree().quit()
