class_name PosterSets
extends RefCounted
## Every poster set there is (`data/poster_sets.json`) and what the player's finished challenges
## make of them. Nothing here is stored: a panel is uncovered when its challenge is done, a set is
## finished when all six are, and the prize is owned when the set is (`PlateCatalog`). So the
## prize is granted once however often a board is read, and a retune needs no migration.
##
## A set only names challenges the night counts (progression rule 15: a stat that does not exist
## is not offered), none a crowd is needed for (solo-safe) and none a hidden one (its words stay
## secret until it is done): `problems` says when one does not.

const PATH := "res://gameplay/challenges/data/poster_sets.json"
## The event that tells a set was finished: to the popup lane, the voice and the news.
const DONE := &"poster_set_done"

static var _shared: PosterSets

var _sets: Array[PosterSet] = []
var _problems: Array[String] = []


## The shipped sets, read once for the process.
static func shipped() -> PosterSets:
	if _shared == null:
		_shared = from_text(FileAccess.get_file_as_string(PATH))
	return _shared


static func from_text(text: String) -> PosterSets:
	var found := PosterSets.new()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		found._problems.append("poster sets unreadable")
		return found
	for record: Variant in (json.data as Dictionary).get("sets", []):
		if typeof(record) == TYPE_DICTIONARY:
			found._sets.append(PosterSet.from_dict(record))
	return found


func all() -> Array[PosterSet]:
	return _sets


func get_set(id: StringName) -> PosterSet:
	for poster_set in _sets:
		if poster_set.id == id:
			return poster_set
	return null


## The set a challenge belongs to, or null.
func of_challenge(id: StringName) -> PosterSet:
	for poster_set in _sets:
		if poster_set.challenges.has(id):
			return poster_set
	return null


## The set that `finished` (a challenge id) was the last of, given every challenge now `done`
## (`finished` included): the transition to done, so it is told once. Null for a challenge of no
## set, or a set with panels still covered.
func completed_by(finished: StringName, done: Array[StringName]) -> PosterSet:
	var poster_set := of_challenge(finished)
	if poster_set != null and poster_set.is_done(done):
		return poster_set
	return null


## The sets all of whose challenges are in `done`.
func finished_in(done: Array[StringName]) -> Array[PosterSet]:
	var found: Array[PosterSet] = []
	for poster_set in _sets:
		if poster_set.is_done(done):
			found.append(poster_set)
	return found


## The event that tells `player_id` finished `set` (`player_id` below zero: a menu's, no seat).
func event_of(poster_set: PosterSet, player_id: int = -1) -> Dictionary:
	var event := {
		"type": DONE,
		"id": poster_set.id,
		"title": poster_set.title,
		"card": poster_set.piece(&"card"),
		"emblem": poster_set.piece(&"emblem"),
		"completed": true,
	}
	if player_id >= 0:
		event["player_id"] = player_id
	return event


## What is wrong with the sets (empty when sound): an id twice, a challenge that does not exist or
## is in two sets, a hidden one, a stat the night cannot count, one that needs a crowd, a poster
## with no art, no title or not six panels.
func problems(
	challenges: ChallengeCatalog, weapon_ids: Array[StringName], type_ids: Array[StringName]
) -> Array[String]:
	var found := _problems.duplicate()
	var seen_sets := {}
	var seen_challenges := {}
	for poster_set in _sets:
		if poster_set.id == &"" or seen_sets.has(poster_set.id):
			found.append("set '%s': an id, once" % poster_set.id)
		seen_sets[poster_set.id] = true
		if poster_set.title.strip_edges() == "" or poster_set.lines.is_empty():
			found.append("%s: a title and the lines of the poster are needed" % poster_set.id)
		if not PlatePalettes.has(poster_set.palette):
			found.append("%s: unknown palette '%s'" % [poster_set.id, poster_set.palette])
		if not PlateMotifs.has(poster_set.motif):
			found.append("%s: unknown motif '%s'" % [poster_set.id, poster_set.motif])
		if poster_set.challenges.size() != PosterSet.PANELS:
			found.append(
				(
					"%s: %d challenges, a poster has %d panels"
					% [poster_set.id, poster_set.challenges.size(), PosterSet.PANELS]
				)
			)
		if poster_set.grants.is_empty():
			found.append("%s: gives nothing" % poster_set.id)
		for id in poster_set.challenges:
			var def := challenges.get_def(id)
			if def == null:
				found.append("%s: no challenge '%s'" % [poster_set.id, id])
				continue
			if seen_challenges.has(id):
				found.append("%s: '%s' is in two sets" % [poster_set.id, id])
			seen_challenges[id] = true
			if def.family != ChallengeDef.Family.FEAT:
				found.append("%s: '%s' is not a feat" % [poster_set.id, id])
			# A set prints its challenges' words on the Challenges tab, and a hidden challenge's words
			# may not be read before it is done (#1172).
			if def.hidden:
				found.append("%s: '%s' is hidden" % [poster_set.id, id])
			# A `distinct` feat has no stat of its own; its definition checks the prefix.
			for stat in _stats_of(def):
				if not ChallengeStats.is_known(stat, weapon_ids, type_ids):
					found.append(
						"%s: '%s' counts '%s', which the night does not" % [poster_set.id, id, stat]
					)
				if ChallengeStats.CROWD.has(stat):
					found.append("%s: '%s' needs a crowd ('%s')" % [poster_set.id, id, stat])
	return found


static func _stats_of(def: ChallengeDef) -> Array[StringName]:
	var stats: Array[StringName] = []
	if def.distinct == "":
		stats.append(def.stat)
	stats.append_array(def.stats)
	return stats
