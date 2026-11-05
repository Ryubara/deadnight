class_name ChallengeDef
extends RefCounted
## One challenge, as the data files write it (`data/*.json`): what it says, the stat it counts, how
## far it goes and what it will pay. A plain value; progress is the profile's.
##
## `mode` is how the stat counts toward the target: TOTAL adds up across nights, ONE_NIGHT is the
## most a single night reached ("Reach round 8 in one night"). A milestone has `steps` (a ladder of
## targets, each reached in turn) instead of one `target`; its target is the next step.
## `reward` is the XP a finished challenge pays (`xp`).
##
## A FEAT is a lasting goal that is done once and gives something to show (`grants`): the calling
## cards and emblems of the plate (`PlateCatalog`). `grants` lists what a challenge gives, each
## `card:<id>`, `emblem:<id>` or `frame:<id>`. A feat may be counted over several stats (`stats`):
## it is done when the lowest of them reaches the target ("250 kills with every weapon"). A feat
## may instead count how many stats under a prefix the player has ever moved (`distinct`, such as
## `kills:weapon:`): "Kill with five different weapons".

enum Family { DAILY, ORDER, MILESTONE, FEAT }
enum Mode { TOTAL, ONE_NIGHT }
enum Tier { SHORT, MEDIUM, LONG }

const TIER_NAMES := {&"short": Tier.SHORT, &"medium": Tier.MEDIUM, &"long": Tier.LONG}

var id: StringName = &""
var family: Family = Family.DAILY
var text := ""
var stat: StringName = &""
var mode: Mode = Mode.TOTAL
var target := 1
var steps: Array[int] = []
var tier: Tier = Tier.SHORT
## Dailies: two of one group are never dealt on the same day, so a day is varied.
var group: StringName = &""
## Orders: which pillar of the night the goal belongs to (night, light, craft).
var pillar: StringName = &""
var reward: Dictionary = {}
## What finishing gives to wear: `card:<id>`, `emblem:<id>`, `frame:<id>`.
var grants: Array[StringName] = []
## A feat over several stats: the lowest of them is its progress (`stat` is the first).
var stats: Array[StringName] = []
## A feat over how many stats starting with this have a lifetime total: its progress.
var distinct := ""


## The definition a data record describes.
static func from_dict(record: Dictionary, p_family: Family) -> ChallengeDef:
	var def := ChallengeDef.new()
	def.id = StringName(record.get("id", ""))
	def.family = p_family
	def.text = String(record.get("text", ""))
	def.stat = StringName(record.get("stat", ""))
	def.mode = Mode.ONE_NIGHT if record.get("mode", "total") == "night" else Mode.TOTAL
	def.steps.assign(record.get("steps", []))
	def.target = int(record.get("target", def.steps[0] if not def.steps.is_empty() else 0))
	def.tier = TIER_NAMES.get(StringName(record.get("tier", "short")), Tier.SHORT)
	def.group = StringName(record.get("group", ""))
	def.pillar = StringName(record.get("pillar", ""))
	def.reward = record.get("reward", {})
	for grant: Variant in record.get("grants", []):
		def.grants.append(StringName(str(grant)))
	for each: Variant in record.get("stats", []):
		def.stats.append(StringName(str(each)))
	def.distinct = String(record.get("distinct", ""))
	if def.stat == &"" and not def.stats.is_empty():
		def.stat = def.stats[0]
	return def


func is_ladder() -> bool:
	return not steps.is_empty()


## Whether a change of `changed` (a stat) can move this challenge.
func counts(changed: StringName) -> bool:
	return changed == stat or stats.has(changed)


## The words for `at` (a target; a ladder's is its next step): `{n}` is the number.
func words(at: int = -1) -> String:
	return text.replace("{n}", str(at if at >= 0 else target))


## What is wrong with this definition, or an empty list when it is sound.
func problems(weapon_ids: Array[StringName], type_ids: Array[StringName]) -> Array[String]:
	var found: Array[String] = []
	if id == &"" or text == "":
		found.append("%s: an id and a text are needed" % id)
	if distinct != "":
		if not [ChallengeStats.WEAPON_PREFIX, ChallengeStats.TYPE_PREFIX].has(distinct):
			found.append("%s: distinct '%s' is not a prefix of stats" % [id, distinct])
		if family != Family.FEAT or mode != Mode.TOTAL or not stats.is_empty():
			found.append("%s: only a feat counted in total goes over distinct stats" % id)
	elif not ChallengeStats.is_known(stat, weapon_ids, type_ids):
		found.append("%s: unknown stat '%s'" % [id, stat])
	if target <= 0:
		found.append("%s: the target must be above zero" % id)
	if ChallengeStats.is_best(stat) and mode != Mode.ONE_NIGHT and family != Family.MILESTONE:
		found.append("%s: a best stat can only be reached in one night" % id)
	if family == Family.MILESTONE:
		if steps.is_empty():
			found.append("%s: a milestone needs steps" % id)
		for i in range(1, steps.size()):
			if steps[i] <= steps[i - 1]:
				found.append("%s: steps must rise" % id)
	elif not steps.is_empty():
		found.append("%s: only a milestone has steps" % id)
	if family == Family.DAILY and group == &"":
		found.append("%s: a daily needs a group" % id)
	for each in stats:
		if not ChallengeStats.is_known(each, weapon_ids, type_ids):
			found.append("%s: unknown stat '%s'" % [id, each])
	if not stats.is_empty() and (family != Family.FEAT or mode != Mode.TOTAL):
		found.append("%s: only a feat counted in total goes over several stats" % id)
	for grant in grants:
		if not _is_grant(String(grant)):
			found.append("%s: grant '%s' is not card:<id>, emblem:<id> or frame:<id>" % [id, grant])
	return found


static func _is_grant(grant: String) -> bool:
	var parts := grant.split(":")
	return (
		parts.size() == 2
		and parts[0] in ["card", "emblem", "frame"]
		and not (parts[1] as String).is_empty()
		and (parts[1] as String) == (parts[1] as String).to_snake_case()
	)
