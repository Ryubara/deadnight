class_name MapWords
extends Resource
## What a map calls its own things on the HUD: the name and the line on the card of each paid link,
## and what its breaches are. The lot's words are the HUD's defaults (`NightHudBinding.DOOR_NAMES`,
## `HudPrompt.DETAILS`) and it has no `MapWords`; a map that has other things to sell names them
## here, so a card never speaks of the lot on a map that has none (`MapTuning.words`, read through
## `MapLayout.words`). The words are plain text; the HUD sets them in capitals.

## Link id (`ShopItem.id`) to the name on its card, its marker and the feed's line.
@export var link_names: Dictionary[StringName, String] = {}
## Link id to the line under its name: what it opens.
@export var link_details: Dictionary[StringName, String] = {}
## The name on the card of a breach (the lot's is a broken fence).
@export var breach_name := ""


## The name of the link `id`, or "" when this map does not name it.
func link_name(id: StringName) -> String:
	return link_names.get(id, "")


## The line on the card of the link `id`, or "" when this map has none for it.
func link_detail(id: StringName) -> String:
	return link_details.get(id, "")
