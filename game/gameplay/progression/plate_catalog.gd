class_name PlateCatalog
extends RefCounted
## Every calling card, emblem and frame there is, what each looks like (`plate_pieces.json`: a
## title, a palette and, for a card or an emblem a motif, for a frame a style: the parts
## `PlateMotifs` and `PlateFrames` compose it from) and where each comes from. One gate per piece
## (docs/design/progression.md rule 3): the ladder gives a piece at a level (`LadderUnlocks`: the
## `tier_card`, `tier_emblem`, `emblem` and `plate_frame` rows) or a challenge gives it
## (`ChallengeDef.grants`), never both and never two. What a player owns is therefore derived: the
## level (from XP) and the list of finished challenges (`Profile.done`), so a retune needs no
## migration and nothing is stored twice.
##
## A HIDDEN challenge's pieces (`ChallengeDef.hidden`) are not named until the challenge is done:
## `shown_title` is `???` and `how_to_get` its riddle, and the art is a silhouette. Every screen
## asks those two, never `title` and the challenge's words. A DERIVED challenge (*Final cut*) is
## done when its rule is true of the level (`is_done`), so it needs no stored finish.
##
## A new piece is a line in `plate_pieces.json` and a row in `unlocks.json` or a `grants` entry in
## a challenge file; the poster sets (#1073) and the stats the odd challenges need (#1074) add
## theirs the same way.

const PATH := "res://gameplay/progression/plate_pieces.json"
const CARD := &"card"
const EMBLEM := &"emblem"
## A border for the plate (#1071): a level gives some, a challenge the rest.
const FRAME := &"frame"
const KINDS: Array[StringName] = [CARD, EMBLEM, FRAME]
## What a hidden piece is called until its challenge is done.
const CONCEALED := "???"
## The ladder rows that give each kind a piece.
const LADDER_SLOTS := {
	CARD: [&"tier_card"], EMBLEM: [&"tier_emblem", &"emblem"], FRAME: [&"plate_frame"]
}

static var _shared: PlateCatalog

## kind -> piece id -> the piece's record (`{id, title, motif, palette, ...}`).
var _pieces: Dictionary = {CARD: {}, EMBLEM: {}, FRAME: {}}
## kind -> piece ids in the order they are listed: the ladder by level, then the challenges.
var _order: Dictionary = {CARD: [], EMBLEM: [], FRAME: []}
## kind -> piece id -> `{level}` or `{challenge: ChallengeDef}`.
var _sources: Dictionary = {CARD: {}, EMBLEM: {}, FRAME: {}}
var _problems: Array[String] = []
## The cards the ladder gives as a tier's (`tier_card` rows), for the derived *Final cut*.
var _tier_cards: Array[StringName] = []


## The shipped catalogue, read once for the process.
static func shipped() -> PlateCatalog:
	if _shared == null:
		_shared = from_parts(
			FileAccess.get_file_as_string(PATH),
			LadderUnlocks.shipped(),
			ChallengeCatalog.load_default()
		)
	return _shared


## A catalogue from the pieces' JSON text, the ladder's table and the challenges.
static func from_parts(
	text: String, ladder: LadderUnlocks, challenges: ChallengeCatalog
) -> PlateCatalog:
	var catalog := PlateCatalog.new()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		catalog._problems.append("plate pieces unreadable")
		return catalog
	var data: Dictionary = json.data
	for kind in KINDS:
		for record: Variant in data.get(String(kind) + "s", []):
			if typeof(record) == TYPE_DICTIONARY:
				catalog._add_piece(kind, record)
	catalog._add_ladder(ladder)
	catalog._add_grants(challenges)
	return catalog


## What is wrong with the catalogue (empty when sound): a piece with no source or two, a source
## with no piece, a motif, a style or a palette nobody has, an id twice.
func problems() -> Array[String]:
	var found := _problems.duplicate()
	for kind in KINDS:
		for id: StringName in _pieces[kind]:
			var record: Dictionary = _pieces[kind][id]
			var label := "%s %s" % [kind, id]
			if not _sources[kind].has(id):
				found.append("%s: nothing gives it" % label)
			if kind == FRAME:
				if not PlateFrames.has(StringName(record.get("style", ""))):
					found.append("%s: unknown style '%s'" % [label, record.get("style", "")])
			elif not PlateMotifs.has(StringName(record.get("motif", ""))):
				found.append("%s: unknown motif '%s'" % [label, record.get("motif", "")])
			if not PlatePalettes.has(StringName(record.get("palette", ""))):
				found.append("%s: unknown palette '%s'" % [label, record.get("palette", "")])
			if String(record.get("title", "")).strip_edges() == "":
				found.append("%s: no title" % label)
		for id: StringName in _sources[kind]:
			if not _pieces[kind].has(id):
				found.append("%s %s: given, but there is no such piece" % [kind, id])
	return found


## The piece ids of a kind in the order they are listed.
func ids(kind: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	found.assign(_order.get(kind, []))
	return found


func has(kind: StringName, id: StringName) -> bool:
	return _pieces.get(kind, {}).has(id)


## A piece's record (`id`, `title`, `palette`, and `motif` with `side` or `shape`, or a frame's
## `style`); empty for none.
func piece(kind: StringName, id: StringName) -> Dictionary:
	return _pieces.get(kind, {}).get(id, {})


func title(kind: StringName, id: StringName) -> String:
	return String(piece(kind, id).get("title", ""))


## Where a piece comes from: `{level}` for the ladder or `{challenge}` (a `ChallengeDef`); empty
## for a piece nothing gives.
func source(kind: StringName, id: StringName) -> Dictionary:
	return _sources.get(kind, {}).get(id, {})


## Whether a player at `level` who finished `done` owns the piece.
func owns(kind: StringName, id: StringName, level: int, done: Array[StringName]) -> bool:
	var from := source(kind, id)
	if from.has("level"):
		return level >= int(from["level"])
	if from.has("challenge"):
		return is_done(from["challenge"], level, done)
	return false


## Whether a player at `level` who finished `done` has finished the challenge: it is on their list,
## or it is derived and its rule holds (every tier card owned).
func is_done(def: ChallengeDef, level: int, done: Array[StringName]) -> bool:
	if done.has(def.id):
		return true
	if def.derived == ChallengeDef.DERIVED_TIER_CARDS:
		for card in _tier_cards:
			if not owns(CARD, card, level, done):
				return false
		return not _tier_cards.is_empty()
	return false


## The pieces of a kind a player owns, in the listed order.
func owned(kind: StringName, level: int, done: Array[StringName]) -> Array[StringName]:
	var found: Array[StringName] = []
	for id in ids(kind):
		if owns(kind, id, level, done):
			found.append(id)
	return found


## What it takes to get a piece, in words: "Reach level 10", the challenge's own, or a hidden
## challenge's riddle.
func how_to_get(kind: StringName, id: StringName) -> String:
	var from := source(kind, id)
	if from.has("level"):
		return "Reach level %d" % int(from["level"])
	if from.has("challenge"):
		return (from["challenge"] as ChallengeDef).hint()
	return ""


## Whether a challenge keeps this piece secret until it is done.
func is_hidden(kind: StringName, id: StringName) -> bool:
	var from := source(kind, id)
	return from.has("challenge") and (from["challenge"] as ChallengeDef).hidden


## What a screen calls the piece: its title, or `???` while it is a hidden piece not yet owned.
func shown_title(kind: StringName, id: StringName, is_owned: bool) -> String:
	if not is_owned and is_hidden(kind, id):
		return CONCEALED
	return title(kind, id)


## What a player wears of what they chose: `{card, emblem, frame}` (ids, `&""` for none), a choice
## they do not own left out. `chosen` is `{card: id, emblem: id, frame: id}` as the profile keeps
## it (`equipped`).
func worn(chosen: Dictionary, level: int, done: Array[StringName]) -> Dictionary:
	var out := {CARD: &"", EMBLEM: &"", FRAME: &""}
	for kind in KINDS:
		var id := StringName(str(chosen.get(String(kind), "")))
		if id != &"" and owns(kind, id, level, done):
			out[kind] = id
	return out


func _add_piece(kind: StringName, record: Dictionary) -> void:
	var id := StringName(str(record.get("id", "")))
	if id == &"":
		_problems.append("%s: a piece with no id" % kind)
	elif _pieces[kind].has(id):
		_problems.append("%s %s: id used twice" % [kind, id])
	else:
		_pieces[kind][id] = record


func _add_ladder(ladder: LadderUnlocks) -> void:
	for level in ladder.levels():
		for row: Dictionary in ladder.at_level(level):
			for kind in KINDS:
				if row["slot"] in LADDER_SLOTS[kind]:
					_give(kind, StringName(row["item"]), {"level": level})
					if row["slot"] == &"tier_card":
						_tier_cards.append(StringName(row["item"]))


func _add_grants(challenges: ChallengeCatalog) -> void:
	for grant in challenges.grants():
		if grant["kind"] in KINDS:
			_give(grant["kind"], grant["id"], {"challenge": grant["def"]})


func _give(kind: StringName, id: StringName, from: Dictionary) -> void:
	if _sources[kind].has(id):
		_problems.append("%s %s: given twice" % [kind, id])
		return
	_sources[kind][id] = from
	_order[kind].append(id)
