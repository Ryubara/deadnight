extends GdUnitTestSuite
## No display name the player reads is a maker's name or a trademark (#857). The maintainer's
## decision: a gun whose name is a maker's brand gets an original name in the drive-in's voice, with
## the same design (ids, models, stats and sounds stay). `weapon_name_rules.json` keeps the list of
## banned names and the names chosen; this suite reads every place a name reaches the player:
## the definitions (the HUD, the prompt cards, the crane's reveal), their re-cut ("Re-Cut <name>"),
## the wall plaques of both maps, the feed's lines and the challenges' texts.

const RULES := "res://tests/weapons/weapon_name_rules.json"
const SCENES := [
	"res://world/drive_in_greybox.tscn",
	"res://world/smallmap/smallmap_greybox.tscn",
]
const CHALLENGES := [
	"res://gameplay/challenges/data/dailies.json",
	"res://gameplay/challenges/data/orders.json",
]


func _rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(RULES)) as Dictionary


## The lower-case words of a text, with "&" and "'" kept inside a word and every other mark a gap.
static func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var word := ""
	for ch in text.to_lower():
		if (
			ch == "-"
			or ch == "&"
			or ch == "'"
			or (ch >= "a" and ch <= "z")
			or (ch >= "0" and ch <= "9")
		):
			word += ch
		elif word != "":
			out.append(word)
			word = ""
	if word != "":
		out.append(word)
	return out


## The banned names in a text: a term is in it when its words are in the text's words in a row
## (the dashes of a designation are also a gap: "PPSh-41" holds "ppsh", "MP-5" holds "mp5").
static func banned_in(text: String, banned: Array) -> Array[String]:
	var found: Array[String] = []
	var plain := " %s " % " ".join(_words(text.replace("-", "")))
	var dashed := " %s " % " ".join(_words(text.replace("-", " ")))
	for term in banned:
		var words := " ".join(_words(String(term).replace("-", "")))
		var spaced := " ".join(_words(String(term).replace("-", " ")))
		if plain.contains(" %s " % words) or dashed.contains(" %s " % spaced):
			found.append(String(term))
	return found


func _names_of_defs() -> Dictionary:
	var names := {}
	var ids: Array[StringName] = WeaponCatalog.IDS.duplicate()
	ids.append(WeaponCatalog.QUICK_MELEE)
	for id in ids:
		var plain := WeaponCatalog.get_def(id)
		names["%s (name)" % id] = plain.display_name
		names["%s (re-cut)" % id] = plain.upgraded(UpgradeTuning.shipped()).display_name
	return names


func test_the_matcher_finds_makers_and_trademarks() -> void:
	var banned: Array = _rules()["banned"]
	for text in [
		"Barrett .50cal",
		"REMINGTON 870 MCS",
		"Pump 870",
		"MP5",
		"mp-5",
		"PPSh-41",
		"PPSh",
		"M4A1",
		"M249 SAW",
		"Re-Cut M4A1",
		"Ray gun",
		"Smith & Wesson",
		"Heckler and Koch MP5",
		"The Colt",
		"Thompson"
	]:
		(
			assert_bool(banned_in(text, banned).is_empty())
			. override_failure_message("'%s' passed" % text)
			. is_false()
		)
	for text in [
		"Revolver",
		"Tommy gun",
		"Double-barrel",
		"Hunting rifle",
		"Usher SMG",
		"Reel Gun",
		"Matinee Carbine",
		"Double-Feature Gun",
		"Popper",
		"Moonbeam Pistol",
		"Snow-Cone Gun",
		"Fifty cal",
		"Dual Pistols",
		"Flare gun",
		"Crowbar",
		"Baseball bat",
		"Fire axe",
		"Quick melee",
		"Re-Cut Revolver",
		"Colton",
		"Sawmill"
	]:
		(
			assert_array(banned_in(text, banned))
			. override_failure_message("'%s' failed" % text)
			. is_empty()
		)


func test_no_weapon_name_or_re_cut_name_is_a_maker_or_trademark() -> void:
	var banned: Array = _rules()["banned"]
	var names := _names_of_defs()
	for key in names:
		(
			assert_str(String(names[key]))
			. override_failure_message("%s has no name" % key)
			. is_not_empty()
		)
		(
			assert_array(banned_in(String(names[key]), banned))
			. override_failure_message(
				"%s is '%s', a maker's name or a trademark" % [key, names[key]]
			)
			. is_empty()
		)


func test_no_two_weapons_share_a_name() -> void:
	var seen := {}
	for id in WeaponCatalog.IDS:
		var shown := WeaponCatalog.get_def(id).display_name.to_lower()
		(
			assert_bool(seen.has(shown))
			. override_failure_message("%s repeats the name of %s" % [id, seen.get(shown)])
			. is_false()
		)
		seen[shown] = id


## A weapon whose id is a real designation shows the name chosen for it, the moment it is in the
## catalogue: the pull request that adds the gun takes the name, or this fails.
func test_a_weapon_with_a_chosen_name_shows_it() -> void:
	var chosen: Dictionary = _rules()["chosen"]
	var banned: Array = _rules()["banned"]
	for id in chosen:
		(
			assert_array(banned_in(String(chosen[id]), banned))
			. override_failure_message("the name chosen for %s is banned" % id)
			. is_empty()
		)
		if WeaponCatalog.IDS.has(StringName(id)):
			assert_str(WeaponCatalog.get_def(StringName(id)).display_name).is_equal(
				String(chosen[id])
			)


func test_no_wall_plaque_or_sign_names_a_maker() -> void:
	var banned: Array = _rules()["banned"]
	var pattern := RegEx.create_from_string('(?m)^text = "(.*)"$')
	for path in SCENES:
		for hit in pattern.search_all(FileAccess.get_file_as_string(path)):
			var text := hit.get_string(1)
			(
				assert_array(banned_in(text, banned))
				. override_failure_message("%s has the text '%s'" % [path, text])
				. is_empty()
			)


func test_no_feed_line_or_challenge_names_a_maker() -> void:
	var banned: Array = _rules()["banned"]
	for key in HudFeed.ITEM_NAMES:
		(
			assert_array(banned_in(String(HudFeed.ITEM_NAMES[key]), banned))
			. override_failure_message("feed line of %s" % key)
			. is_empty()
		)
	var text_pattern := RegEx.create_from_string('"text": "([^"]*)"')
	for path in CHALLENGES:
		for hit in text_pattern.search_all(FileAccess.get_file_as_string(path)):
			(
				assert_array(banned_in(hit.get_string(1), banned))
				. override_failure_message("%s: '%s'" % [path, hit.get_string(1)])
				. is_empty()
			)
