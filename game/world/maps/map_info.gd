class_name MapInfo
extends Resource
## One map a night can be played on: what the picker shows (name, a line about it, size, how many
## players, a preview picture) and where the night loads it from. A map that is not shipped yet is
## listed so the picker can show it as "coming soon", but cannot be chosen or loaded
## (`is_playable`). The list of them is `MapRegistry`; the reasoning is in docs/design/maps.md.

## The id the match settings, the backend and the wire carry (`MatchSettings.map`).
@export var id := ""
@export var title := ""
## One line about the map, for the card's caption.
@export var blurb := ""
## The scene `NightWorld` builds: the same node layout as `world/drive_in_greybox.tscn` (doors,
## spawns, lamps, switches, fuel). Empty while the map is not built.
@export_file("*.tscn") var scene_path := ""
## The picture on the card, 16:9. Empty draws the card's placeholder panel.
@export_file("*.png") var preview_path := ""
## Floor the players can walk, in square metres, as the design page measured it.
@export var area_m2 := 0
@export var min_players := 1
@export var max_players := 4
## False for a map that is listed but not built: its card is locked, "coming soon".
@export var shipped := true

var _preview: Texture2D


## Whether a night can be played on it now.
func is_playable() -> bool:
	return shipped and not scene_path.is_empty()


## The scene a night builds this map from, or null when it has none.
func load_scene() -> PackedScene:
	return load(scene_path) as PackedScene if is_playable() else null


## The card's picture, or null (loaded once).
func preview() -> Texture2D:
	if _preview == null and not preview_path.is_empty():
		_preview = load(preview_path) as Texture2D
	return _preview


## `13,200 m²`: the size as a player reads it, rounded to the hundred above a thousand.
func size_text() -> String:
	if area_m2 <= 0:
		return ""
	var shown := area_m2 if area_m2 < 1000 else roundi(float(area_m2) / 100.0) * 100
	return "%s m²" % MenuNav.grouped(shown)


## `1 to 4 players`, or `1 player` for a map of one.
func players_text() -> String:
	if min_players == max_players:
		return "%d player%s" % [max_players, "" if max_players == 1 else "s"]
	return "%d to %d players" % [min_players, max_players]


## The two facts under the title: `13,200 m² · 1 to 4 players`.
func facts_text() -> String:
	var parts: Array[String] = []
	if area_m2 > 0:
		parts.append(size_text())
	parts.append(players_text())
	return " · ".join(parts)
