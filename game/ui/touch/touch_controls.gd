# gdlint:disable=max-public-methods
class_name TouchControls
extends Control
## The touch controls of a night: a floating move stick on the left, a look area on the right,
## and buttons under the right thumb. They press the game's own input actions (`move_*`, `fire`,
## `aim`, `jump`, `reload`, `quick_melee`, `interact`, `sprint`, `pause`, `scoreboard`, `ping`,
## and from the HUD's places `weapon_slot_*`, `throw_grenade` and the bots' tag `bot_order_next`),
## so the player and the night read them like a key or a pad and nothing else forks.
##
## Aim is held while the thumb is on it when auto-fire is on (`controls/touch_auto_fire`, the
## default: the weapon fires by itself with the crosshair on a zombie while aiming), and a toggle
## when auto-fire is off: a tap aims, the next tap leaves the aim, so the player can aim and shoot
## by hand. Fire shoots wherever the player aims, in both.
##
## Every finger is tracked by its touch index and has one job until it lifts: the stick, the look,
## or one button. A finger that starts on any button of the right thumb also looks while it drags
## (#1277, `TouchLayout.looks_when_dragged`): one thumb can aim and shoot, turn while the grenade
## is held, or press Reload or Jump and carry on turning. Look goes out as mouse motion in
## mouse pixels (`TouchLook`), so the sensitivity setting,
## the ADS slow-down and invert Y apply as they do for a mouse.
##
## The move stick is drawn only while a finger is on it: a ring where the finger landed. A drag to
## the ring's edge walks at full speed; a drag past the edge by `TouchTuning.sprint_margin_px`
## starts a sprint, with one buzz, that stays on until that finger lifts (`TouchStick`, #1276).
## What cancels a sprint, and what a cancel does to the latch, is in
## `docs/research/mobile-controls.md`.
##
## The layer shows when `TouchMode.wanted`, in landscape, and while the night is live (`live`).
## While it is up the engine's touch-to-mouse emulation is off, or every touch would also click
## Fire, and the player turns only for the layer's own look (`TouchLook.is_stray`): in a browser a
## finger is also a pointer move, which the web runtime reads as a mouse motion (#470).
## The weapons are the HUD's own places (`HudSlots`, #1280): the layer does not draw them, it asks
## the HUD where they are (`zones`) and presses the action of the one a finger lands on, like a
## button of its own. A finger that starts on a weapon's place only picks it: it never fires or
## looks; one that starts on the grenades' place also looks, as every button of the right thumb.
## The bots' tag (`HudBotOrder`, #1286) is such a place too, and a finger on it only taps it: it
## never starts the stick or a look. The zones are tried in the order the HUD lists them and the
## first that holds the point wins (the tag is first), after the buttons and before the stick.
## The interact button shows only while the HUD has a prompt: what it does is its word. The Strike
## button shows only while a dead is within reach of the quick melee (`strike_ready`, #1285), and
## shows the blade. Every other button shows an icon and no words (`TouchIcons`).
##
## Crouch is a toggle: a tap crouches and stays crouched, a second tap (or a Jump, which cannot be
## made crouching) stands, so the right thumb is free for Fire and the look.
##
## Two quick taps on free ground press `swap_shoulder` (`TouchDoubleTap`, #1288): the shoulder is a
## fight verb but a rare one, so it has no button. A touch on free ground is held back from the look
## only while it can still be a tap (under 250 ms, under a finger's slop), and all of it is let out
## at once the moment it is not, so no look is lost and none is late.
##
## While it is up the HUD shows no key hints (`UIInputMode.touch`), and `TouchHints` labels the
## controls the first time each is met, until it is used.

## A look drag, in mouse pixels (also sent to the input system as mouse motion).
signal looked(mouse_relative: Vector2)
## The platform's safe-area insets changed (left, top, right, bottom, canvas units).
signal safe_insets_changed(insets: Vector4)
## The touch layout is flipped for a left hand, or stopped being (the HUD swaps its columns).
signal mirrored_changed(mirrored: bool)
## The controls came up or went away (a phone shows them, a keyboard hides them).
signal active_changed(active: bool)
## A double tap on free ground pressed `swap_shoulder`.
signal shoulder_swapped
## The buttons are somewhere else now, or are there or not (`button_boxes`).
signal layout_changed
## The stick finger crossed the edge: the sprint is on until it lifts (the phone buzzes once).
signal sprint_started

const MOVE_LEFT := &"move_left"
const MOVE_RIGHT := &"move_right"
const MOVE_FORWARD := &"move_forward"
const MOVE_BACK := &"move_back"
const SPRINT := &"sprint"
## CSS pixels in a canvas unit on a phone's night (844 x 390 CSS px over 1080 units), when no one
## says otherwise (`css_per_unit`): a test's canvas.
const DEFAULT_CSS_PER_UNIT := 0.36
## What the interact button says for each kind of prompt.
const VERBS := {
	&"buy_door": "OPEN",
	&"buy_weapon": "BUY",
	&"buy_ammo": "AMMO",
	&"buy_crane": "PLAY",
	&"crane_take": "TAKE",
	&"fill_fuel": "FUEL",
	&"repair": "HOLD",
	&"circuit": "SWITCH",
	&"revive": "REVIVE",
}
const DEFAULT_VERB := "USE"
## The grenades' place on the HUD's strip presses this action (held while the pin is out).
const GRENADE := &"throw_grenade"
const AUTO_FIRE_SETTING := &"controls/touch_auto_fire"
## The feel numbers (dead zone, sprint, hold, look): `touch_tuning_default.tres`.
var tuning: TouchTuning = TouchLook.tuning
## The double tap on free ground (`TouchDoubleTap`).
var double_tap := TouchDoubleTap.new()
## () -> float, seconds of real time; without it `Time`'s. A test steps its own.
var clock := Callable()
## The finger's slop in canvas units; below 0 it is `TouchSlop` of the window now.
var tap_slop := -1.0
## The HUD state, for the interact button.
var state: HudState
## False while a menu or the result is up: the layer hides and lets go of everything.
var live := true:
	set(value):
		live = value
		_refresh_active()
## Set by a test or a debug view; otherwise read from the platform.
var insets_override: Variant = null
var touch_scale := 1.0
var opacity := 0.7
var insets := Vector4.ZERO
## The layout is flipped for a left hand (the setting `controls/left_handed`).
var left_handed := false
## Whether the first-run hints remember what was used in the settings. Tests turn it off.
var persist_hints := true
## The first-run labels, a child that draws over the buttons.
var hints: TouchHints
## () -> float, the factor on a look drag: the aim assist's friction near a zombie (1 without).
var look_gain := Callable()
## The look the finger has made and the view has not turned yet (`LookSmoother`).
var look_smoother := LookSmoother.new()
## () -> float, the least width of a hit area in canvas units: a fingertip, 44 CSS pixels
## (`MenuScale.tap_units`), which depends on the window and the interface size and so is asked
## again at every layout. Without it the hit areas are the layout's own (#1217).
var finger_units := Callable()
## () -> float, CSS pixels in one canvas unit (`MenuScale.css_per_unit`), so the stick's ring and
## the margin past it are the same movement of the thumb on every phone (#1276). Without it the
## unit of a phone's night (`DEFAULT_CSS_PER_UNIT`).
var css_per_unit := Callable()
## () -> Array[Dictionary], the HUD's places a finger presses: `{action, rect}` in the screen's
## canvas units (`HudSlots.touch_zones`). Without it the layer has none.
var zones := Callable()
## () -> bool, whether a dead is within reach of the quick melee now (`StrikeReach`): the Strike
## button shows while it says yes. Without it the button never shows.
var strike_ready := Callable()

## True while the Strike button shows: a dead is within reach of the quick melee. A property, not
## a method: the class is at the linter's limit of public methods.
var strike_up: bool:
	get:
		return _strike_up

## Auto-fire on: Aim is held. Off: Aim is a toggle (`_aim_latched`).
var _aim_is_hold := true
var _aim_latched := false
var _crouch_latched := false
var _enabled := false
var _active := false
var _circles := {}
var _safe := Rect2()
var _touches := {}
var _pressed_at := {}
var _release_at := {}
var _clock := 0.0
var _inset_clock := INF
var _stick_index := -1
var _stick_vector := Vector2.ZERO
var _interact_verb := ""
var _strike_up := false
var _last_insets := Vector4.ZERO
var _was_mirrored := false
## `_look_key()` at the last draw.
var _drawn_key := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	get_viewport().size_changed.connect(_on_resized)
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service != null and service.has_signal(&"changed"):
		service.connect(&"changed", _on_setting_changed)
	hints = TouchHints.new()
	hints.controls = self
	hints.persist = persist_hints
	add_child(hints)
	refresh()


func _exit_tree() -> void:
	_release_everything()
	TouchLook.layer_up = false
	Input.emulate_mouse_from_touch = true


## Re-read the settings (mode, size, opacity) and the platform, and lay out again.
func refresh() -> void:
	touch_scale = _setting(&"controls/touch_scale", 1.0)
	opacity = _setting(&"controls/touch_opacity", 0.7)
	left_handed = _flag(SettingsService.LEFT_HANDED)
	var hold := _setting(AUTO_FIRE_SETTING, 1.0) >= 1.0
	if hold != _aim_is_hold:
		_aim_is_hold = hold
		_unlatch_aim()
	_enabled = TouchMode.wanted(get_tree())
	_relayout()
	_refresh_active()


## True while the controls are on screen and taking touches.
func is_active() -> bool:
	return _active


## True while the touch controls are wanted and flipped for a left hand: the HUD's columns
## follow, and stay put under a pause menu (a layer that is down for a menu is still the layout).
func is_mirrored() -> bool:
	return _enabled and left_handed


func button_circle(id: StringName) -> Dictionary:
	return _circles.get(id, {})


func circles() -> Dictionary:
	return _circles


## The buttons a finger is on now (a browser test reads them).
func held_buttons() -> PackedStringArray:
	var held := PackedStringArray()
	for touch: Dictionary in _touches.values():
		if touch.get(&"role", &"") == &"button":
			held.append(String(touch[&"button"]))
	return held


## The box of every button, in the screen's canvas units, while the controls are up (none while
## they are down): what the world markers keep clear of, as a finger is on them (#1218).
func button_boxes() -> Array[Rect2]:
	var found: Array[Rect2] = []
	if not _active:
		return found
	var origin := get_global_rect().position
	var hidden := _hidden()
	for id: StringName in _circles:
		if id in hidden:
			continue  # not drawn, so nothing to keep clear of
		var circle: Dictionary = _circles[id]
		var reach := Vector2.ONE * float(circle[&"radius"])
		found.append(Rect2(origin + Vector2(circle[&"centre"]) - reach, reach * 2.0))
	for zone in _zones():
		found.append(zone[&"rect"])
	return found


## The caption the interact button shows now, "" when it is hidden.
func interact_verb() -> String:
	return _interact_verb


## The contextual buttons that are not up: not drawn, not touched, nothing to keep clear of.
func _hidden() -> Array:
	var hidden := []
	if _interact_verb == "":
		hidden.append(TouchLayout.INTERACT)
	if not _strike_up:
		hidden.append(TouchLayout.STRIKE)
	return hidden


func is_stick_down() -> bool:
	return _stick_index >= 0


## The ring of the finger on the stick, none when there is no finger. The sprint latch is its own.
func stick_pad() -> TouchStick:
	if _stick_index < 0:
		return null
	return _touches.get(_stick_index, {}).get(&"pad") as TouchStick


## The ring's radius in canvas units: `TouchTuning.stick_radius_px` CSS pixels at the touch scale.
func stick_radius() -> float:
	return tuning.stick_radius_px * touch_scale * _units_per_css_px()


## How far past the ring's edge the sprint starts, in canvas units: `sprint_margin_px` CSS pixels.
func sprint_margin() -> float:
	return tuning.sprint_margin_px * _units_per_css_px()


func _units_per_css_px() -> float:
	var per_unit := float(css_per_unit.call()) if css_per_unit.is_valid() else DEFAULT_CSS_PER_UNIT
	return 1.0 / maxf(per_unit, 0.01)


func stick_vector() -> Vector2:
	return _stick_vector


## True while the finger on the stick has gone past the edge and not lifted (the latch).
func is_sprinting() -> bool:
	var pad := stick_pad()
	return pad != null and pad.latched


## True while the aim is toggled on (auto-fire off, Aim tapped once).
func is_aim_latched() -> bool:
	return _aim_latched


## True while Crouch is toggled on (tapped once, not yet tapped again or jumped from).
func is_crouch_latched() -> bool:
	return _crouch_latched


func is_pressed(id: StringName) -> bool:
	return _pressed_at.has(id) and not _release_at.has(id)


func safe_rect() -> Rect2:
	return _safe


## Portrait: the canvas is taller than wide. The rotate prompt covers it; the controls wait.
func is_portrait() -> bool:
	var canvas := _canvas()
	return canvas.y > canvas.x


## This node's size, or the viewport's when it sits under a CanvasLayer (no parent to fill).
func _canvas() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return get_viewport_rect().size


func _process(delta: float) -> void:
	_clock += delta
	_turn_view(look_smoother.step(delta))
	for action: StringName in _release_at.keys():
		if _clock >= float(_release_at[action]):
			_release_at.erase(action)
			_pressed_at.erase(action)
			Input.action_release(action)
	_inset_clock += delta
	if _inset_clock >= tuning.inset_period:
		_inset_clock = 0.0
		if _enabled:  # the notch is for a finger: a page without the controls never asks (#983)
			_relayout()
		_refresh_active()
	var verb := _verb_now()
	if verb != _interact_verb:
		_interact_verb = verb
		if verb == "":
			_drop_button(TouchLayout.INTERACT)
		layout_changed.emit()  # the button came or went: the world markers make room (#1218)
	var strike := _active and strike_ready.is_valid() and bool(strike_ready.call())
	if strike != _strike_up:
		_strike_up = strike
		if not strike:
			_drop_button(TouchLayout.STRIKE)
		layout_changed.emit()
	if _active:
		_redraw_if_changed()


## Redraws only when what the buttons show has changed. Every `draw_circle` and `draw_arc` is a
## polygon the Compatibility renderer builds into its own vertex array and buffers, and redrawing
## about forty of them every frame made the web page create, and its WebGL id tables keep, some
## two hundred objects a frame (the page's heap grew 50 MB a minute, #834).
func _redraw_if_changed() -> void:
	var key := _look_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


## A number that differs whenever anything `_draw` reads differs: what is held, the stick, the
## verb on the interact button, the layout, the opacity and the look.
func _look_key() -> int:
	var held := PackedStringArray()
	for touch: Dictionary in _touches.values():
		held.append(String(touch.get(&"button", &"")))
	held.sort()
	var pad := stick_pad()
	var stick: Variant = [pad.origin, pad.pos] if pad != null else null
	return hash(
		[
			held,
			_aim_latched,
			_crouch_latched,
			_stick_index,
			stick,
			is_sprinting(),
			_interact_verb,
			_strike_up,
			opacity,
			touch_scale,
			left_handed,
			_circles,
			UITokens.active().get_instance_id(),
		]
	)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# This layer handles the touch before the HUD sees it: the input mode is told here.
		UIInputMode.track(event)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touch_down(touch.index, touch.position)
		else:
			_touch_up(touch.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touch_drag(drag.index, drag.position, drag.velocity)
		get_viewport().set_input_as_handled()


func _touch_down(index: int, point: Vector2) -> void:
	if _touches.has(index):
		_touch_up(index)
	var button := TouchLayout.button_at(point, _circles, _hidden())
	if button == &"":
		button = zone_at(point)
	if button != &"":
		double_tap.interrupt()
		_touches[index] = _own(&"button", point, {&"button": button, &"start": point})
		_press_button(button)
		if button == TouchLayout.INTERACT:
			hints.mark_used(TouchHints.INTERACT)
		elif button == HudBotOrder.ACTION:
			hints.mark_used(TouchHints.BOTS)
		elif button == TouchLayout.STRIKE:
			hints.mark_used(TouchHints.STRIKE)
	elif _stick_index < 0 and _stick_zone().has_point(point):
		hints.mark_used(TouchHints.MOVE)
		double_tap.interrupt()
		_stick_index = index
		_touches[index] = _own(&"stick", point, {&"pad": TouchStick.new(point)})
		_set_stick(Vector2.ZERO)
	elif not _has_role(&"look"):
		# Free ground. A finger the stick's side holds (the stick finger is down already) looks and
		# never counts as a tap.
		var taps := not _stick_zone().has_point(point)
		_touches[index] = _own(&"look", point, {&"tap": taps, &"held": Vector2.ZERO, &"at": _now()})
		if taps:
			double_tap.press(index, point, _now())
		else:
			double_tap.interrupt()


## The action of the HUD's place under `point`, or "" (a weapon's slot, or the grenade).
func zone_at(point: Vector2) -> StringName:
	for zone in _zones():
		if (zone[&"rect"] as Rect2).has_point(point):
			return zone[&"action"]
	return &""


func _zones() -> Array:
	return zones.call() if zones.is_valid() else []


## The box of the HUD's place that presses `action` (the bots' tag), or an empty rectangle when it
## is not there now: what a first-run hint points at.
func zone_rect(action: StringName) -> Rect2:
	for zone in _zones():
		if zone[&"action"] == action:
			return zone[&"rect"]
	return Rect2()


func _touch_up(index: int) -> void:
	var touch: Dictionary = _touches.get(index, {})
	_touches.erase(index)
	match touch.get(&"role", &""):
		&"stick":
			_stick_index = -1
			_set_stick(Vector2.ZERO)
		&"button":
			_release_button(touch[&"button"])
		&"look":
			_lift_look(index, touch)


## A look finger lifted: a tap that completes a double tap swaps the shoulder; a touch held back as
## a possible tap that was none lets out the look it kept.
func _lift_look(index: int, touch: Dictionary) -> void:
	if not touch.get(&"tap", false):
		return
	var now := _now()
	if double_tap.release(index, now):
		_press_button(TouchDoubleTap.ACTION)
		_release_button(TouchDoubleTap.ACTION)
		hints.mark_used(TouchHints.SWAP)
		shoulder_swapped.emit()
	elif now - float(touch[&"at"]) >= TouchDoubleTap.TAP_SECONDS and touch[&"held"] != Vector2.ZERO:
		_look(touch[&"held"], Vector2.ZERO)


## What a finger owns from its press to its lift: one job (`role`), where it last was (`last`), and
## how many drags it made (`drags`).
func _own(role: StringName, point: Vector2, extra := {}) -> Dictionary:
	var owned := {&"role": role, &"last": point, &"drags": 0}
	owned.merge(extra)
	return owned


## A drag is read from the finger's own path, not from the event's `relative`: with two fingers
## down the browser's runtime measures the first drag of a finger from somewhere else (the origin
## for one finger, the other finger's press for the next), and the view flicked round by a whole
## screen (#497). `velocity` is stale for a finger's first few drags too: it counts after three.
func _touch_drag(index: int, point: Vector2, velocity: Vector2) -> void:
	var touch: Dictionary = _touches.get(index, {})
	if touch.is_empty():
		return
	var relative: Vector2 = point - touch[&"last"]
	touch[&"last"] = point
	touch[&"drags"] += 1
	match touch[&"role"]:
		&"stick":
			_follow_stick(touch[&"pad"], point)
		&"look":
			var speed := _trusted_velocity(touch, velocity)
			if touch.get(&"tap", false):
				touch[&"held"] += relative
				if double_tap.is_tap(index, point, _now(), _slop()):
					return  # still a tap, perhaps: its look waits
				# It is a look: all of what it made so far goes out now, none lost.
				touch[&"tap"] = false
				double_tap.drop(index)
				relative = touch[&"held"]
			_look(relative, speed)
		&"button":
			# The grenades' place on the HUD looks too: the thumb is on it for the whole cook (#599).
			if touch[&"button"] == GRENADE or TouchLayout.looks_when_dragged(touch[&"button"]):
				_look(relative, _trusted_velocity(touch, velocity))


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else Time.get_ticks_usec() * 0.000001


func _slop() -> float:
	return tap_slop if tap_slop >= 0.0 else TouchSlop.units(get_window())


func _trusted_velocity(touch: Dictionary, velocity: Vector2) -> Vector2:
	return velocity if touch[&"drags"] > tuning.velocity_warmup_drags else Vector2.ZERO


func _look(relative: Vector2, velocity: Vector2) -> void:
	var look := TouchLook.mouse_equivalent(relative, velocity.length(), _canvas().y)
	if look_gain.is_valid():
		look *= float(look_gain.call())
	looked.emit(look)
	if relative != Vector2.ZERO:
		hints.mark_used(TouchHints.LOOK)
	# The view turns in `_process`, a share of what the fingers made each frame (#598).
	TouchLook.samples += 1
	look_smoother.time_constant = tuning.look_smoothing
	look_smoother.frames = tuning.look_smoothing_frames
	look_smoother.add(look)


## Everything the fingers made and the view has not turned yet turns it now (a test, a menu that
## opens).
func flush_look() -> void:
	_turn_view(look_smoother.take_all())


## Sends what the view turns this frame as the mouse motion the player reads.
func _turn_view(look: Vector2) -> void:
	if look == Vector2.ZERO:
		return
	# Injected events are in window pixels and the viewport maps them back to canvas units, so
	# the look is sent through the stretch in advance: the player receives exactly `look`.
	var motion := InputEventMouseMotion.new()
	motion.relative = get_viewport().get_final_transform().basis_xform(look)
	# The player turns by `screen_relative`: the layer's look is already in mouse pixels, the same
	# at every window size, so it is sent as it is.
	motion.screen_relative = look
	motion.position = get_viewport().get_final_transform() * get_viewport().get_mouse_position()
	motion.device = TouchLook.DEVICE
	TouchLook.sent += 1
	# Alone and at once: the engine adds a mouse motion in the input buffer to the next one that
	# arrives, under the first one's device. A stray copy of a finger waiting there would take the
	# layer's own motion in with it and the player would drop both.
	Input.flush_buffered_events()
	Input.parse_input_event(motion)
	Input.flush_buffered_events()


## The finger moved: the pad reads it, and the first time it is past the edge the sprint starts
## with one buzz. Up to the edge the stick is fixed where the finger landed, so the edge is the
## same place for the whole drag; once the sprint is on, the ring follows the finger.
func _follow_stick(pad: TouchStick, point: Vector2) -> void:
	var started := pad.drag(point, stick_radius(), sprint_margin())
	_set_stick(pad.vector(stick_radius(), tuning.stick_deadzone))
	if started:
		_buzz(tuning.sprint_haptic_ms)
		sprint_started.emit()


func _set_stick(vector: Vector2) -> void:
	_stick_vector = vector
	_axis(MOVE_RIGHT, maxf(vector.x, 0.0))
	_axis(MOVE_LEFT, maxf(-vector.x, 0.0))
	_axis(MOVE_BACK, maxf(vector.y, 0.0))
	_axis(MOVE_FORWARD, maxf(-vector.y, 0.0))
	# The latch is the finger's: with no finger on the stick the sprint is let go.
	if is_sprinting():
		Input.action_press(SPRINT)
	else:
		Input.action_release(SPRINT)


func _axis(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _press_button(id: StringName) -> void:
	_buzz()
	if id == TouchLayout.PAUSE:
		_send_action(id, true)
		_send_action.call_deferred(id, false)
		return
	if id == TouchLayout.AIM and not _aim_is_hold:
		_aim_latched = not _aim_latched
		if _aim_latched:
			Input.action_press(id)
		else:
			Input.action_release(id)
		return
	if id == TouchLayout.CROUCH:
		_crouch_latched = not _crouch_latched
		if _crouch_latched:
			Input.action_press(id)
		else:
			Input.action_release(id)
		return
	if id == TouchLayout.JUMP:
		# A crouching body cannot jump: the press stands it up and the jump goes on, in one tick.
		_unlatch_crouch()
	_release_at.erase(id)
	_pressed_at[id] = _clock
	Input.action_press(id)


func _release_button(id: StringName) -> void:
	if id == TouchLayout.PAUSE or not _pressed_at.has(id):
		return
	var held_until: float = float(_pressed_at[id]) + tuning.min_hold
	if _clock >= held_until:
		_pressed_at.erase(id)
		Input.action_release(id)
	else:
		_release_at[id] = held_until


func _unlatch_aim() -> void:
	if _aim_latched:
		_aim_latched = false
		Input.action_release(TouchLayout.AIM)


func _unlatch_crouch() -> void:
	if _crouch_latched:
		_crouch_latched = false
		Input.action_release(TouchLayout.CROUCH)


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## A finger on a button that is gone (interact hid) lets go.
func _drop_button(id: StringName) -> void:
	for index: int in _touches.keys():
		if _touches[index].get(&"button", &"") == id:
			_touch_up(index)


func _has_role(role: StringName) -> bool:
	for touch: Dictionary in _touches.values():
		if touch[&"role"] == role:
			return true
	return false


func _buzz(duration_ms := -1) -> void:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service != null and service.has_method(&"get_value"):
		if service.call(&"get_value", &"controls/haptics") == false:
			return
	Input.vibrate_handheld(tuning.haptic_ms if duration_ms < 0 else duration_ms)


func _verb_now() -> String:
	if state == null or state.prompt.is_empty():
		return ""
	return VERBS.get(state.prompt.get("kind", &""), DEFAULT_VERB)


func _setting(key: StringName, fallback: float) -> float:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service == null or not service.has_method(&"get_value"):
		return fallback
	var value: Variant = service.call(&"get_value", key)
	return float(value) if value is float or value is int else fallback


func _flag(key: StringName) -> bool:
	var service := get_tree().root.get_node_or_null(TouchMode.SETTING_PATH)
	if service == null or not service.has_method(&"get_value"):
		return false
	return service.call(&"get_value", key) == true


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	# The hints' own bookkeeping is no reason to lay the buttons out again.
	if key != SettingsService.TOUCH_HINTS_SEEN:
		refresh()


func _on_resized() -> void:
	_relayout()
	_refresh_active()


func _refresh_active() -> void:
	var now := _enabled and live and not is_portrait() and is_inside_tree()
	if now != _active:
		_active = now
		active_changed.emit(now)
		layout_changed.emit()
		if now:
			# Controls up and no other device used yet: the HUD shows a finger, not a keycap.
			UIInputMode.touch = true
			UIInputMode.gamepad = false
		if not now:
			_release_everything()
		queue_redraw()
	visible = _active
	if is_mirrored() != _was_mirrored:
		_was_mirrored = is_mirrored()
		mirrored_changed.emit(_was_mirrored)
	# Touch-to-mouse emulation would also click Fire (left mouse) and look twice.
	Input.emulate_mouse_from_touch = not _active
	TouchLook.layer_up = _active


func _release_everything() -> void:
	double_tap.reset()
	look_smoother.take_all()
	_touches.clear()
	_stick_index = -1
	_set_stick(Vector2.ZERO)
	_unlatch_aim()
	_unlatch_crouch()
	for action: StringName in _pressed_at.keys():
		Input.action_release(action)
	_pressed_at.clear()
	_release_at.clear()


## Where a finger may start the stick: below the bottom of Ping's hit area (#1289).
func _stick_zone() -> Rect2:
	var ping: Dictionary = _circles.get(TouchLayout.PING, {})
	var below := -INF
	if not ping.is_empty():
		below = (ping[&"centre"] as Vector2).y + float(ping[&"hit"])
	return TouchLayout.stick_zone(_safe, left_handed, below)


func _relayout() -> void:
	insets = insets_override if insets_override != null else _platform_insets()
	_safe = TouchLayout.safe_rect(_canvas(), insets)
	var finger := float(finger_units.call()) if finger_units.is_valid() else 0.0
	_circles = TouchLayout.buttons(_safe, touch_scale, left_handed, finger)
	if insets != _last_insets:
		_last_insets = insets
		safe_insets_changed.emit(insets)
	layout_changed.emit()


## The notch, rounded corners and home bar, in canvas units. On the web the page's CSS insets
## (needs `viewport-fit=cover`, see `docs/research/mobile-controls.md`); on a phone build the
## display server's safe area; nowhere else.
func _platform_insets() -> Vector4:
	if OS.has_feature("web"):
		return _web_insets()
	if OS.has_feature("android") or OS.has_feature("ios"):
		return TouchLayout.insets_from(
			DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), _canvas()
		)
	return Vector4.ZERO


func _web_insets() -> Vector4:
	var script := (
		"(function(){var d=document.createElement('div');"
		+ "d.style.cssText='position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;"
		+ "padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) "
		+ "env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';"
		+ "document.body.appendChild(d);var s=getComputedStyle(d);"
		+ "var r=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom,"
		+ "window.innerWidth].join(',');document.body.removeChild(d);return r;})()"
	)
	var answer: Variant = JavaScriptBridge.eval(script, true)
	if not answer is String:
		return Vector4.ZERO
	var parts := (answer as String).replace("px", "").split(",")
	if parts.size() < 5 or float(parts[4]) <= 0.0:
		return Vector4.ZERO
	var k := _canvas().x / float(parts[4])
	return Vector4(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])) * k


func _draw() -> void:
	if not _active:
		return
	var tokens := UITokens.active()
	var font := tokens.display_font(tokens.embolden_display * 0.3)
	_draw_stick(tokens, font)
	# Every icon is one canvas command, flushed after the discs: no two buttons overlap.
	var icons := HudShapes.new()
	var hidden := _hidden()
	for id: StringName in _circles:
		if id in hidden:
			continue
		_draw_button(tokens, font, icons, id, _circles[id])
	icons.flush(self)


## Colour at the resting opacity, or full while its control is held.
func _alpha(colour: Color, held: bool) -> Color:
	return Color(colour, colour.a * (1.0 if held else opacity))


func _is_held(id: StringName) -> bool:
	if (id == TouchLayout.AIM and _aim_latched) or (id == TouchLayout.CROUCH and _crouch_latched):
		return true
	for touch: Dictionary in _touches.values():
		if touch.get(&"button", &"") == id:
			return true
	return false


func _draw_button(
	tokens: UITokens, font: Font, icons: HudShapes, id: StringName, circle: Dictionary
) -> void:
	var centre: Vector2 = circle[&"centre"]
	var radius: float = circle[&"radius"]
	var held := _is_held(id)
	var primary := id == TouchLayout.FIRE or id == TouchLayout.INTERACT
	var fill := tokens.surface_raised
	if held:
		fill = tokens.accent_bright
	elif primary:
		fill = tokens.accent
	var ink := tokens.ink_on_accent if (held or primary) else tokens.ink
	draw_circle(centre + Vector2(3.0, 4.0), radius, _alpha(tokens.shadow, held))
	draw_circle(centre, radius, _alpha(fill, held))
	draw_arc(centre, radius, 0.0, TAU, 48, _alpha(tokens.outline.lightened(0.5), held), 3.0, true)
	TouchIcons.add(icons, id, centre, radius, _alpha(ink, held), _alpha(fill, held))
	if id == TouchLayout.INTERACT:
		# The one control that keeps a word: what the thing in front of the player lets it do.
		var px := int(radius * (0.34 if _interact_verb.length() <= 4 else 0.27))
		var width := font.get_string_size(_interact_verb, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at := centre + Vector2(-width * 0.5, radius * 0.5)
		draw_string(font, at, _interact_verb, HORIZONTAL_ALIGNMENT_LEFT, -1, px, _alpha(ink, held))


## The ring, only while a finger is on the stick. It is dark ink at the edge to walk to and has a
## faint outer line where the sprint starts; with the sprint on it turns to the accent colour,
## thick, with SPRINT above it: the cue where the phone cannot buzz.
func _draw_stick(tokens: UITokens, font: Font) -> void:
	var pad := stick_pad()
	if pad == null:
		return
	var radius := stick_radius()
	var sprint := pad.latched
	var ring := tokens.accent_bright if sprint else tokens.ink
	var fill := Color(tokens.accent, 0.3) if sprint else Color(tokens.shadow, 0.35)
	draw_circle(pad.origin, radius, _alpha(fill, true))
	draw_arc(pad.origin, radius, 0.0, TAU, 64, _alpha(ring, true), 6.0 if sprint else 4.0, true)
	if not sprint:
		var edge := Color(tokens.ink, 0.35)
		draw_arc(pad.origin, radius + sprint_margin(), 0.0, TAU, 64, edge, 2.0, true)
	draw_circle(
		pad.knob(radius), radius * 0.45, _alpha(tokens.accent if sprint else tokens.ink, true)
	)
	if sprint:
		var px := int(radius * 0.28)
		var width := font.get_string_size("SPRINT", HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		# Above the knob, which the finger holds at the ring's far edge.
		var at := pad.knob(radius) + Vector2(-width * 0.5, -radius * 0.45 - px * 0.5)
		var outline := Color(tokens.shadow, 0.9)
		draw_string_outline(font, at, "SPRINT", HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, outline)
		draw_string(font, at, "SPRINT", HORIZONTAL_ALIGNMENT_LEFT, -1, px, tokens.accent_bright)
