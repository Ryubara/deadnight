class_name ChallengeDef
extends RefCounted
## One challenge, as the data files write it (`data/*.json`): what it says, the stat it counts, how
## far it goes and what it will pay. A plain value; progress is the profile's.
##
## `mode` is how the stat counts toward the target: TOTAL adds up across nights, ONE_NIGHT is the
## most a single night reached ("Reach round 8 in one night"). A milestone has `steps` (a ladder of
## targets, each reached in turn) instead of one `target`; its target is the next step.
## `reward` is a placeholder: nothing pays out yet, the numbers are the design's first guess.

enum Family { DAILY, ORDER, MILESTONE }
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
	return def


func is_ladder() -> bool:
	return not steps.is_empty()


## The words for `at` (a target; a ladder's is its next step): `{n}` is the number.
func words(at: int = -1) -> String:
	return text.replace("{n}", str(at if at >= 0 else target))


## What is wrong with this definition, or an empty list when it is sound.
func problems(weapon_ids: Array[StringName], type_ids: Array[StringName]) -> Array[String]:
	var found: Array[String] = []
	if id == &"" or text == "":
		found.append("%s: an id and a text are needed" % id)
	if not ChallengeStats.is_known(stat, weapon_ids, type_ids):
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
	return found
