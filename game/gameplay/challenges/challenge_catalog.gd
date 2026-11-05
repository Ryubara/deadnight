class_name ChallengeCatalog
extends RefCounted
## Every challenge there is, read from the data files beside this script: `dailies.json` (the pool
## a day's three are dealt from), `orders.json` (the Concession Orders pool), `milestones.json`
## (lifetime ladders) and `feats.json` (lasting goals that give a calling card or an emblem).
## Changing what is asked is a data edit; the tests check the files are sound.

const DATA_DIR := "res://gameplay/challenges/data/"
const FILES := {
	ChallengeDef.Family.DAILY: "dailies.json",
	ChallengeDef.Family.ORDER: "orders.json",
	ChallengeDef.Family.MILESTONE: "milestones.json",
	ChallengeDef.Family.FEAT: "feats.json",
}

const _NONE: Array = []

var _by_id: Dictionary[StringName, ChallengeDef] = {}
var _by_family: Dictionary[int, Array] = {}
var _duplicates: Array[StringName] = []
## The ladders over each stat, found once (a night asks for them at every change a kill makes).
var _ladders: Dictionary[StringName, Array] = {}
## The feats a change of each stat can move, and the feats over distinct stats (found once).
var _feats_over: Dictionary[StringName, Array] = {}
var _distinct: Array[ChallengeDef] = []
var _feats_indexed := false


## The shipped catalogue.
static func load_default() -> ChallengeCatalog:
	var catalog := ChallengeCatalog.new()
	for family: int in FILES:
		var records := _read(DATA_DIR + String(FILES[family]))
		catalog.add_all(records, family as ChallengeDef.Family)
	return catalog


func add_all(records: Array, family: ChallengeDef.Family) -> void:
	for record: Dictionary in records:
		add(ChallengeDef.from_dict(record, family))


func add(def: ChallengeDef) -> void:
	if _by_id.has(def.id):
		_duplicates.append(def.id)
		return
	_by_id[def.id] = def
	_ladders.clear()
	_feats_indexed = false
	var list: Array = _by_family.get(def.family, [])
	list.append(def)
	_by_family[def.family] = list


func has(id: StringName) -> bool:
	return _by_id.has(id)


## The definition with this id, or null.
func get_def(id: StringName) -> ChallengeDef:
	return _by_id.get(id)


## Every definition of a family, in file order.
func of_family(family: ChallengeDef.Family) -> Array[ChallengeDef]:
	var list: Array[ChallengeDef] = []
	list.assign(_by_family.get(family, []))
	return list


## The milestone ladders over `stat`, in file order (the same array each time: do not change it).
func ladders_over(stat: StringName) -> Array:
	var found: Array = _ladders.get(stat, [])
	if found.is_empty() and not _ladders.has(stat):
		for def in of_family(ChallengeDef.Family.MILESTONE):
			if def.stat == stat:
				found.append(def)
		_ladders[stat] = found
	return found


## The feats a change of `stat` can move (the same array each time: do not change it).
func feats_over(stat: StringName) -> Array:
	_index_feats()
	return _feats_over.get(stat, _NONE)


## The feats that count how many stats under a prefix have moved.
func distinct_feats() -> Array[ChallengeDef]:
	_index_feats()
	return _distinct


func _index_feats() -> void:
	if _feats_indexed:
		return
	_feats_indexed = true
	_feats_over.clear()
	_distinct.clear()
	for def in of_family(ChallengeDef.Family.FEAT):
		if def.distinct != "":
			_distinct.append(def)
		var counted: Array[StringName] = [def.stat]
		counted.append_array(def.stats)
		for each in counted:
			if each == &"":
				continue
			var list: Array = _feats_over.get(each, [])
			if not list.has(def):
				list.append(def)
			_feats_over[each] = list


## Every challenge that gives something to wear, in file order: `[{def, grant}]` with the grant
## split into its kind (`card`, `emblem`, `frame`) and the piece's id.
func grants() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for family in FILES:
		for def in of_family(family):
			for grant in def.grants:
				var parts := String(grant).split(":")
				found.append({"def": def, "kind": StringName(parts[0]), "id": StringName(parts[1])})
	return found


## The challenge that gives this piece (`kind` is `card`, `emblem` or `frame`), or null.
func giver_of(kind: StringName, piece: StringName) -> ChallengeDef:
	for grant in grants():
		if grant["kind"] == kind and grant["id"] == piece:
			return grant["def"]
	return null


## The dailies of one tier, in file order.
func dailies_of(tier: ChallengeDef.Tier) -> Array[ChallengeDef]:
	var list: Array[ChallengeDef] = []
	for def in of_family(ChallengeDef.Family.DAILY):
		if def.tier == tier:
			list.append(def)
	return list


## What is wrong with the whole catalogue (empty when sound): a duplicate id, a stat the night
## cannot count, a ladder that does not rise.
func problems(weapon_ids: Array[StringName], type_ids: Array[StringName]) -> Array[String]:
	var found: Array[String] = []
	for id in _duplicates:
		found.append("%s: id used twice" % id)
	for def in _by_id.values():
		found.append_array(def.problems(weapon_ids, type_ids))
	return found


static func _read(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Challenge data missing: %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).get("challenges") is Array:
		return (parsed as Dictionary)["challenges"]
	push_error("Challenge data unreadable: %s" % path)
	return []
