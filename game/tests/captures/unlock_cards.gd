extends Control
## Capture for #1131: an unlock card of each slot the wardrobe holds (a top, trousers, shoes,
## headwear, eyewear, neckwear, a colour) and a map, each with the wardrobe's thumbnail and name,
## then a plate item whose art is not drawn (its letter chip) and a name too long for the card. Not
## part of the game.
## Record: `gds godot -- --path game res://tests/captures/unlock_cards.tscn --write-movie
## <abs>/c.png --fixed-fps 10 --resolution 1280x720 --quit-after 5`; the last frame is the shot.

const CARDS: Array[Array] = [
	[&"top", &"letter_jacket"],
	[&"trousers", &"swing_skirt"],
	[&"shoes", &"saddle_shoes"],
	[&"headwear", &"projectionists_visor"],
	[&"eyewear", &"cinema_glasses"],
	[&"neck", &"bolo_tie"],
	[&"colour", &"mustard"],
	[&"map", &"back_rooms"],
	[&"emblem", &"admit_one"],
	[&"top", &"the_projectionists_very_long_named_jacket_of_the_late_show"],
]
const GAP := 14.0


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color("14111f")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var column := 0
	var row := 0
	for pair in CARDS:
		var card := PopupCard.new()
		card.setup(PopupQueue.Kind.UNLOCK, {"slot": pair[0], "item": pair[1], "level": 1})
		var step := PopupCard.UNLOCK_SIZE + Vector2(GAP, GAP)
		card.position = Vector2(60.0 + column * step.x, 50.0 + row * step.y)
		add_child(card)
		row += 1
		if row == 5:
			row = 0
			column += 1
