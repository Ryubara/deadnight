class_name BotRoster
extends RefCounted
## Who the bots of a room are: for each skill, three people with a name and a look of their own, so
## a lobby, a HUD and a screen show a bot as someone, and the skill can be read from the clothes
## (the rookie is a kid in a letterman jacket, the veteran a ranger). Pure data; the server wears
## them on the bots' seats (`NightBots`), the lobby shows the names before the night begins.
##
## A look is a preset of the character catalogue (`LookCatalog.presets()`, by id). A person who
## wears the same one is told apart from the bot by the resolver (`LookResolver`), as two people
## are.

## Skill (`MatchSettings.SKILL_*`) -> the three identities, each `{name, look}`.
const CAST := {
	MatchSettings.SKILL_ROOKIE:
	[
		{"name": "Pip", "look": &"soda_jerk"},
		{"name": "Dale", "look": &"letterman"},
		{"name": "Moe", "look": &"usher"},
	],
	MatchSettings.SKILL_REGULAR:
	[
		{"name": "Ash", "look": &"ranger"},
		{"name": "Fern", "look": &"soda_jerk"},
		{"name": "Moss", "look": &"projectionist"},
	],
	MatchSettings.SKILL_VETERAN:
	[
		{"name": "Rex", "look": &"ranger"},
		{"name": "Sarge", "look": &"projectionist"},
		{"name": "Hawk", "look": &"mechanic"},
	],
}


## The identity of the bot at seat `player_id` (1 to 4) in a room of `skill`: seats take the three
## in turn, so the bots of one night are always three different people.
static func identity(skill: int, player_id: int) -> Dictionary:
	var cast: Array = CAST[clampi(skill, MatchSettings.SKILL_ROOKIE, MatchSettings.SKILL_VETERAN)]
	return cast[posmod(player_id - 1, cast.size())]


static func name_for(skill: int, player_id: int) -> String:
	return identity(skill, player_id)["name"]


## The look the bot at `player_id` wears.
static func look_for(skill: int, player_id: int) -> CharacterLook:
	return look_of_preset(identity(skill, player_id)["look"])


## The look of the catalogue preset `preset_id` (the default look when the catalogue has no such
## id).
static func look_of_preset(preset_id: StringName) -> CharacterLook:
	var presets := LookCatalog.presets()
	for i in presets.size():
		if presets[i]["id"] == preset_id:
			return CharacterLook.from_preset(i)
	return CharacterLook.default_look()
