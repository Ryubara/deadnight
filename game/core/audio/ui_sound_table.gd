class_name UiSoundTable
extends RefCounted
## The menu's sound table (#894): which sound each kind of control plays for each event, how loud
## (a trim on top of the sound's own level in `banks/ui_menu.tres`) and which weight it has. The
## words of it are `docs/research/menu-sfx.md`; the rules that keep it from becoming noise (the gap
## between hints, no hover on touch, ticks per step) are `UiSounds`.
##
## A **role** is a kind of control (`ticket`, `tab`, `slider`), a **cue** is an event of the
## `UIAudio` vocabulary (`hover`, `press`, `tick`, ...). A role has a row for every cue its
## controls can make, either a sound or an explicit silence with its reason: a missing row is a
## bug that `test_ui_sound_roles.gd` finds by driving every control of every menu screen.

## Weights, the rungs of the ladder (4 to 6 dB between them): a hint, a move, a press, a commit, a
## moment. A weight of 2 or more is a "strong" sound: a hint never follows it closely.
const HINT := 1
const MOVE := 2
const PRESS := 3
const COMMIT := 4
const MOMENT := 5

## Button texts that are a step back (their press is the back sound, whatever their variant).
const BACK_WORDS: Array[String] = ["back", "cancel", "close", "leave", "leave night"]
## Button texts that commit (a start, a save, a join): the press is the commit sound.
const COMMIT_WORDS: Array[String] = [
	"start the night",
	"start",
	"play",
	"save",
	"join",
	"quick join",
	"join with the code",
	"create a night",
	"continue",
]

const _HOVER := {"sound": &"ui_hover", "weight": HINT}
const _FOCUS := {"sound": &"ui_focus", "weight": HINT}
const _HOVER_SOFT := {"sound": &"ui_hover", "weight": HINT, "db": -4.0}
const _FOCUS_SOFT := {"sound": &"ui_focus", "weight": HINT, "db": -4.0}
const _PRESS := {"sound": &"ui_press", "weight": PRESS}
const _PRESS_SECONDARY := {"sound": &"ui_press", "weight": PRESS, "db": -2.0}
const _PRESS_GHOST := {"sound": &"ui_press", "weight": PRESS, "db": -3.0}
const _BACK := {"sound": &"ui_back", "weight": PRESS}
const _CONFIRM := {"sound": &"ui_confirm", "weight": COMMIT}
const _REFUSE := {"sound": &"ui_refuse", "weight": PRESS}
const _SELECT := {"sound": &"ui_select", "weight": MOVE}
const _TAB := {"sound": &"ui_tab", "weight": MOVE}
const _TICK := {"sound": &"ui_tick", "weight": HINT}
const _ON := {"sound": &"ui_toggle_on", "weight": MOVE}
const _OFF := {"sound": &"ui_toggle_off", "weight": MOVE}
const _PUSH := {"sound": &"ui_push", "weight": MOVE}
const _POP := {"sound": &"ui_pop", "weight": MOVE}
const _SIGN := {"sound": &"ui_sign_on", "weight": MOMENT}

## Every role: cue to row. A row is a sound (`sound`, `weight`, an optional `db` trim) or a silence
## (`silent` with the `why`).
const ROLES := {
	# A ticket of the Play, Shop and More lists, and a lobby row: hint on the pointer or focus,
	# a punch on the press.
	&"ticket": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _PRESS},
	# The three ways to start (the "ADMIT ONE" stubs): the ticket is torn, then punched.
	&"ticket_start": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _CONFIRM},
	# A row that is not there yet: a quiet hint and the shutter that will not open.
	&"ticket_soon": {&"hover": _HOVER_SOFT, &"focus": _FOCUS_SOFT, &"press": _REFUSE},
	# A tab of the bar: the hint is its own, the move is the bar's `tab` cue (one sound for a
	# click, a key and a bumper alike, and none when the tab is already showing).
	&"tab":
	{
		&"hover": _HOVER,
		&"focus": _FOCUS,
		&"press": {"silent": true, "why": "the bar's tab change plays the tab sound once"},
	},
	&"tab_bar": {&"tab": _TAB},
	# A family chip of the challenges.
	&"chip": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _SELECT},
	# A challenge on the sheet: it only reads (silent press); an order can be swapped (a select).
	&"sheet_row":
	{
		&"hover": _HOVER,
		&"focus": _FOCUS,
		&"press": {"silent": true, "why": "a daily or a milestone only reads"},
	},
	&"sheet_row_swap": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _SELECT},
	# A map's card: a pick, or the shutter on one that is locked.
	&"map_card": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _SELECT},
	&"map_card_locked": {&"hover": _HOVER_SOFT, &"focus": _FOCUS_SOFT, &"press": _REFUSE},
	# The addon's buttons, by variant; a back and a commit button have a role of their own.
	&"button_primary": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _PRESS},
	&"button_secondary": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _PRESS_SECONDARY},
	&"button_ghost": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _PRESS_GHOST},
	&"back_button": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _BACK},
	&"commit_button": {&"hover": _HOVER, &"focus": _FOCUS, &"press": _CONFIRM},
	# A switch: the pitch says which way it went.
	&"toggle": {&"hover": _HOVER, &"focus": _FOCUS, &"on": _ON, &"off": _OFF},
	# A slider: a tick for every step crossed (rate limited), higher with the value.
	&"slider": {&"hover": _HOVER, &"focus": _FOCUS, &"tick": _TICK},
	# A selector and a strip of choices: one select a step.
	&"option": {&"hover": _HOVER, &"focus": _FOCUS, &"select": _SELECT},
	&"choice_strip": {&"hover": _HOVER, &"focus": _FOCUS, &"select": _SELECT},
	# A list: the highlight moves with a tick, an activation is a press.
	&"list": {&"hover": _HOVER, &"focus": _FOCUS, &"tick": _TICK, &"press": _PRESS},
	# A text field: the focus is a hint; what is typed is not sounded.
	&"field":
	{
		&"hover": _HOVER,
		&"focus": _FOCUS,
		&"press": {"silent": true, "why": "typing is its own feedback; a click a letter tires"},
	},
	# Not a control: the router, a screen, a panel (a source with no role of its own).
	&"any":
	{
		&"push": _PUSH,
		&"pop": _POP,
		&"back": _BACK,
		&"tab": _TAB,
		&"confirm": _CONFIRM,
		&"refuse": _REFUSE,
		&"select": _SELECT,
		&"press": _PRESS,
		&"tick": _TICK,
		&"on": _ON,
		&"off": _OFF,
		&"sign": _SIGN,
	},
	# A sound nobody in the menu hears (a control of the stage the menu does not sound).
	&"stage":
	{
		&"hover": {"silent": true, "why": "the stage is a picture: dragging it turns the soldier"},
		&"focus": {"silent": true, "why": "continuous: a drag is not an event"},
		&"press": {"silent": true, "why": "continuous: a drag is not an event"},
	},
}


## The row of a role for a cue, or an empty dictionary.
static func row(role: StringName, cue: StringName) -> Dictionary:
	var rows: Dictionary = ROLES.get(role, {})
	return rows.get(cue, {})


static func has_role(role: StringName) -> bool:
	return ROLES.has(role)


## Whether the row is a written silence.
static func is_silent(a_row: Dictionary) -> bool:
	return a_row.get("silent", false)
