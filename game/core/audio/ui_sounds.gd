class_name UiSounds
extends RefCounted
## The one place the menus get their sound (#894). Every control and the router tell
## `UIAudio.play(cue, source)`, the audio service hands it to `handle`, and this class finds the
## source's role (`role_of`), the row of `UiSoundTable` for the cue, and the rules that keep a menu
## from being noise: the quietest sounds (hints) have a gap between them, never follow a heavier
## sound closely, and are not made on a touch screen; a slider ticks once for a step crossed and
## its pitch follows its value; every play has a small random level on top of the sound's random
## variant and pitch. The design is `docs/research/menu-sfx.md`.

## The least time between two hints (hover, focus), and how long after a heavier sound a hint stays
## quiet (a tab change moves the focus, a press leaves the control focused: both are the sound
## already made).
const HINT_GAP := 0.08
const HINT_AFTER_STRONG := 0.15
## No more than this many hints in any window of this many seconds: a pointer swept over a column
## of rows is a few ticks, not a machine gun.
const HINT_BURST := 5
const HINT_WINDOW := 1.0
## The least time between two slider or list ticks, and between two plays of the same sound.
const TICK_GAP := 0.07
const SAME_GAP := 0.04
## A random level on every play, plus or minus, in dB.
const LEVEL_JITTER_DB := 0.8
## A slider's tick is this many semitones under its pitch at the bottom of the track and over it
## at the top.
const TICK_PITCH_LOW := -3.0
const TICK_PITCH_HIGH := 5.0
## The progression cues (#1062), which come from the popups and the server's events in the middle
## of a fight. Unlock sounds that come within this long of the last one climb the pentatonic
## scale, one step of `UNLOCK_STEPS` (semitones over the sound's own pitch) for each, and stay on
## the last.
const UNLOCK_WINDOW := 2.0
const UNLOCK_STEPS: Array[float] = [0.0, 2.0, 4.0, 7.0]
## Each step of a run is this many dB quieter than the one before it, so the tails of a quick run
## of eight never add up to more than a level up.
const UNLOCK_STEP_DB := -1.0
## A moment (the scratch, the level up, the tier up) that starts while a moment of another group
## still sounds goes under it by this many dB, so the two never add up to much more than the
## louder one. A moment of the same group (a tier up over a level up) takes the other's voice
## instead, at its own level.
const MOMENT_UNDER_DB := -6.0
## In a night (`in_night`) the progression cues are this many dB under their table levels: a
## fight is full of sounds that must stay clear, and at this level a cue stays 6 dB or more under
## a shot, a groan, a shriek, a beep and a soldier's urgent line in their own band and is still
## heard over a burst of automatic fire (`tools/audio/progress_levels.py`,
## `docs/research/menu-sfx.md#the-progression-sounds-1062`). In a menu they play at the table's
## level.
const FIGHT_DB := -10.0
## The meta a plain control carries to name its role, and the one a commit button is marked with.
const ROLE_META := &"ui_sound_role"
## The meta a source of a `tab` cue carries: +1 when the tab chosen is further on, -1 when behind.
const DIRECTION_META := &"ui_sound_direction"

## Cues no row answered for a control that has a role (role/cue), for the test that drives every
## control. A source with no role plays the `any` row of the cue.
var misses: Array[String] = []
## Every sound `handle` started: id, for tests and the capture's log.
var started: Array[StringName] = []
## The pitch (semitones) and the level (dB over the sound's own) of the sound `handle` started last.
var last_pitch := 0.0
var last_extra_db := 0.0
## A night is running: the progression cues (rows with `fight`) are `FIGHT_DB` quieter. The night
## sets it when it starts and clears it when it ends.
var in_night := false

var _audio: AudioService
var _last_hint := -1.0e9
var _hint_times: Array[float] = []
var _last_strong := -1.0e9
var _last_tick := -1.0e9
var _last_by_sound := {}
var _unlock_step := -1
var _last_unlock := -1.0e9
## The moments that still sound: sound id to {ends, group}.
var _moments := {}


func _init(audio: AudioService) -> void:
	_audio = audio


## Names a plain control's role (a `LineEdit`, a button the game builds): the control then sounds
## through the table like every other.
static func tag(control: Object, role: StringName) -> void:
	control.set_meta(ROLE_META, role)


## Marks a button as a commit (Start, Save, Join): its press is the commit sound.
static func commit(button: Control) -> void:
	tag(button, &"commit_button")


## Makes a control of the menu's own sound like the addon's: a pointer arriving is a hover, the
## focus arriving a focus, and a button's press a press, each through `UIAudio` with the control as
## the source (so its role, `ui_sound_role()` or a tag, picks the row). Call it first in `_init`,
## before the control grabs the focus on hover, so the hover is heard before the focus.
static func wire(control: Control) -> void:
	control.mouse_entered.connect(UIAudio.play.bind(&"hover", control))
	control.focus_entered.connect(UIAudio.play.bind(&"focus", control))
	if control is BaseButton:
		(control as BaseButton).pressed.connect(UIAudio.play.bind(&"press", control))


## Makes a plain text field sound like the addon's: a pointer arriving or the focus arriving is a
## hint, and what is typed is not sounded (the `field` role).
static func wire_field(field: LineEdit) -> void:
	tag(field, &"field")
	field.mouse_entered.connect(UIAudio.play.bind(&"hover", field))
	field.focus_entered.connect(UIAudio.play.bind(&"focus", field))


## A tab (a page of one screen, a tab of the bar) was chosen, `direction` +1 forward and -1 back.
static func tab(source: Object, direction: int) -> void:
	source.set_meta(DIRECTION_META, direction)
	UIAudio.play(&"tab", source)


## What kind of control `source` is: its `ui_sound_role()` (the addon's controls, the menu's own),
## else its meta, refined for a button by its words (a back is a back, a start is a commit). A
## source that is not a control (the router) is `any`; a control with no role is the empty name.
static func role_of(source: Object) -> StringName:
	if source == null or not source is Control:
		return &"any"
	var role := &""
	if source.has_meta(ROLE_META):
		role = source.get_meta(ROLE_META)
	elif source.has_method(&"ui_sound_role"):
		role = source.call(&"ui_sound_role")
	if String(role).begins_with("button_") and "text" in source:
		var words := String(source.text).strip_edges().to_lower()
		if UiSoundTable.BACK_WORDS.has(words):
			return &"back_button"
		if UiSoundTable.COMMIT_WORDS.has(words):
			return &"commit_button"
	return role


## Handles one cue; true when a sound started.
func handle(cue: StringName, source: Object = null) -> bool:
	var role := role_of(source)
	var a_row := UiSoundTable.row(role, cue)
	if source is Control and (role == &"" or a_row.is_empty()):
		var kind := String(role) if role != &"" else "<%s>" % source.get_class()
		misses.append("%s/%s" % [kind, cue])
	if a_row.is_empty():
		a_row = UiSoundTable.row(&"any", cue)
	if a_row.is_empty() or UiSoundTable.is_silent(a_row):
		return false
	var weight: int = a_row["weight"]
	var now := _audio.clock()
	if weight == UiSoundTable.HINT:
		if cue == &"tick":
			if not _tick_allowed(source, now):
				return false
		elif not _hint_allowed(cue, now):
			return false
	var id: StringName = a_row["sound"]
	if now - float(_last_by_sound.get(id, -1.0e9)) < SAME_GAP:
		return false
	var extra_db := (
		float(a_row.get("db", 0.0)) + _audio.random_range(-LEVEL_JITTER_DB, LEVEL_JITTER_DB)
	)
	var pitch := _pitch_for(cue, source)
	if a_row.get("moment", false):
		var under := _moment_under(id, a_row, now)
		if is_inf(under):
			return false
		extra_db += under
	if in_night and a_row.get("fight", false):
		extra_db += FIGHT_DB
	if a_row.get("stack", false):
		pitch += _stack_pitch(now)
		extra_db += UNLOCK_STEP_DB * _unlock_step
	_last_by_sound[id] = now
	if weight >= UiSoundTable.MOVE:
		_last_strong = now
	elif cue == &"tick":
		_last_tick = now
	else:
		_last_hint = now
		_hint_times.append(now)
	started.append(id)
	last_pitch = pitch
	last_extra_db = extra_db
	_audio.play(id, null, extra_db, pitch)
	return true


## What a moment goes under, in dB (0 when nothing else sounds, `-INF` when it is redundant: a
## level up while the tier up that includes it sounds), and notes that it sounds from now on.
func _moment_under(id: StringName, a_row: Dictionary, now: float) -> float:
	for other: StringName in a_row.get("over", []):
		if _is_sounding(other, now):
			return -INF
	var group := SoundCatalog.get_def(id).group
	var under := 0.0
	for other: StringName in _moments:
		if other != id and _is_sounding(other, now) and _moments[other]["group"] != group:
			under = MOMENT_UNDER_DB
	_moments[id] = {"ends": now + float(a_row.get("seconds", 0.0)), "group": group}
	return under


func _is_sounding(id: StringName, now: float) -> bool:
	return _moments.has(id) and now < float(_moments[id]["ends"])


## The semitones an unlock sound is raised by: the first of a run is at its own pitch, each one that
## follows within `UNLOCK_WINDOW` of the last a step higher, and the fourth and every one after it
## the top step. A run ends two seconds after its last sound.
func _stack_pitch(now: float) -> float:
	if now - _last_unlock > UNLOCK_WINDOW:
		_unlock_step = 0
	else:
		_unlock_step = mini(_unlock_step + 1, UNLOCK_STEPS.size() - 1)
	_last_unlock = now
	return UNLOCK_STEPS[_unlock_step]


## A hover follows a pointer that moved (on a touch screen there is none, and after a key the mouse
## did not move); a focus move is a hint only when the keys or the pad made it (a pointer's hover
## already sounded); both wait their gap and the end of a heavier sound's moment.
func _hint_allowed(cue: StringName, now: float) -> bool:
	if UIInputMode.touch:
		return false
	if cue == &"hover" and not UIInputMode.pointer:
		return false
	if cue == &"focus" and UIInputMode.pointer:
		return false
	if now - _last_hint < HINT_GAP or now - _last_strong < HINT_AFTER_STRONG:
		return false
	while not _hint_times.is_empty() and now - _hint_times[0] >= HINT_WINDOW:
		_hint_times.pop_front()
	return _hint_times.size() < HINT_BURST


## A tick belongs to a control the player is using (a value set by code at build is not a step),
## and has its gap.
func _tick_allowed(source: Object, now: float) -> bool:
	if source is Control and not _in_use(source):
		return false
	return now - _last_tick >= TICK_GAP


## Whether the player has a control: the focus is on it, or the pointer is.
func _in_use(control: Control) -> bool:
	if control.has_focus():
		return true
	var viewport := control.get_viewport()
	return viewport != null and viewport.gui_get_hovered_control() == control


## A slider's tick rises with its value; a tab goes up a little forward and down a little back.
func _pitch_for(cue: StringName, source: Object) -> float:
	if cue == &"tick" and source is Range:
		var span: float = source.max_value - source.min_value
		if span > 0.0:
			return lerpf(TICK_PITCH_LOW, TICK_PITCH_HIGH, (source.value - source.min_value) / span)
	if cue == &"tab" and source != null and source.has_meta(DIRECTION_META):
		return 1.5 * float(source.get_meta(DIRECTION_META))
	return 0.0
