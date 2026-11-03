class_name BotSay
extends RefCounted
## What a bot may call out (bots plan, phase 5): an enumerated set of lines, each with the words the
## feed shows (and a voice may say later), the seconds before the same bot may say it again and
## whether it is urgent (a shorter wait before the next line of any kind). A line is an id, never
## free text, so a bot cannot say anything the design did not name; the server answers a `say`
## action with a `bot_say` event for every screen.
##
## The words are what a person says in the moment, not a caption for the event
## (`docs/research/maintainer-corrections.md`, the voice lines).

const REVIVING := &"reviving"
const NEED_AMMO := &"need_ammo"
const RELOADING := &"reloading"
const DOOR_BOUGHT := &"door_bought"
const LOW_FUEL := &"low_fuel"
const BOSS_COMING := &"boss_coming"
const RUNNERS := &"runners"
const BREACH_OPEN := &"breach_open"
const COVER_ME := &"cover_me"
const THANKS := &"thanks"
const TRAPPED := &"trapped"
const HELP := &"help"

## id to `{text, cooldown (seconds the same bot waits to say it again), urgent}`.
const LINES := {
	&"reviving": {"text": "GOT YOU, HOLD ON!", "cooldown": 20.0, "urgent": true},
	&"need_ammo": {"text": "I'M RUNNING LOW ON ROUNDS", "cooldown": 60.0, "urgent": false},
	&"reloading": {"text": "RELOADING!", "cooldown": 30.0, "urgent": false},
	&"door_bought": {"text": "DOOR'S OPEN!", "cooldown": 30.0, "urgent": false},
	&"low_fuel": {"text": "GENERATOR'S RUNNING LOW!", "cooldown": 60.0, "urgent": false},
	&"boss_coming": {"text": "BIG ONE COMING!", "cooldown": 60.0, "urgent": true},
	&"runners": {"text": "RUNNERS!", "cooldown": 45.0, "urgent": true},
	&"breach_open": {"text": "THEY'RE THROUGH THE FENCE!", "cooldown": 40.0, "urgent": false},
	&"cover_me": {"text": "COVER ME!", "cooldown": 20.0, "urgent": true},
	&"thanks": {"text": "THANKS!", "cooldown": 30.0, "urgent": false},
	&"trapped": {"text": "I'M BOXED IN!", "cooldown": 30.0, "urgent": true},
	&"help": {"text": "I'M DOWN, HELP!", "cooldown": 60.0, "urgent": true},
}
## Lines whose `subject` is a zombie (a bot names only one it has made out).
const ABOUT_A_ZOMBIE: Array[StringName] = [&"boss_coming", &"runners"]


static func is_line(line: StringName) -> bool:
	return LINES.has(line)


static func text_of(line: StringName) -> String:
	return str(LINES.get(line, {}).get("text", ""))


static func cooldown_of(line: StringName) -> float:
	return float(LINES.get(line, {}).get("cooldown", 30.0))


static func is_urgent(line: StringName) -> bool:
	return bool(LINES.get(line, {}).get("urgent", false))
