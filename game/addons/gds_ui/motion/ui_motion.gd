class_name UIMotion
extends RefCounted
## Tween presets driven by UITokens, and the reduced-motion switch.
##
## Nothing here is linear: every move uses a named easing. With `reduced` set, movement
## completes at once; fades stay (a fade is not motion).

const SETTING_REDUCED := "gds_ui/accessibility/reduced_motion"
## Where a control keeps the entrance it is in: {serial, tween}.
const STAGGER_META := &"gds_ui_stagger"


## Carries the `changed` signal: a static variable cannot declare one itself.
class Bus:
	extends RefCounted
	signal changed(reduced: bool)


static var _bus := Bus.new()
static var _stagger_serial := 0

## True when the player wants calm: no flicker, flashes or movement. Set it at any time;
## whoever shows motion connects to `changed()` and follows it live.
static var reduced := false:
	set(value):
		if value == reduced:
			return
		reduced = value
		_bus.changed.emit(value)


## Emitted with the new value whenever `reduced` changes. Connect to it in `_ready`; a freed
## listener is disconnected on its own.
static func changed() -> Signal:
	return _bus.changed


## Reads the project setting. The router calls this once at startup.
static func load_settings() -> void:
	reduced = bool(ProjectSettings.get_setting(SETTING_REDUCED, false))


static func apply_ease(tween: Tween, kind: UITokens.Ease) -> Tween:
	match kind:
		UITokens.Ease.EMPHASIZED:
			tween.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		UITokens.Ease.ENTER:
			tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		UITokens.Ease.EXIT:
			tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		UITokens.Ease.OVERSHOOT:
			tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_:
			tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tween


## One property to a value. Movement properties snap when `reduced`.
static func to(
	node: Node,
	property: NodePath,
	value: Variant,
	seconds: float,
	kind: UITokens.Ease = UITokens.Ease.STANDARD,
	is_movement := true
) -> Tween:
	var tween := node.create_tween()
	apply_ease(tween, kind)
	tween.tween_property(node, property, value, 0.0 if reduced and is_movement else seconds)
	return tween


## Fade a control in with a small settle (scale 0.97 to 1), the default way a card appears.
## The tween belongs to `owner` (default: the control); pass a node that outlives the control
## when the control may be freed meanwhile, or `finished` never fires.
static func fade_in(control: Control, delay := 0.0, owner: Node = null) -> Tween:
	var tokens := UITokens.active()
	control.modulate.a = 0.0
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE * (1.0 if reduced else 0.97)
	var tween := (owner if owner != null else control).create_tween().set_parallel(true)
	apply_ease(tween, UITokens.Ease.ENTER)
	tween.tween_property(control, "modulate:a", 1.0, tokens.dur_base).set_delay(delay)
	tween.tween_property(control, "scale", Vector2.ONE, tokens.dur_slow).set_delay(delay)
	return tween


## Fade up from below, one control after another (`gap` seconds apart). The controls are hidden
## until their container has placed them, and end exactly where it put them.
##
## A container sorts its children in a deferred call that runs after the frame's `process_frame`
## signal. A caller that comes from an input event (a tab click) runs before that signal in the same
## frame, so one `process_frame` is not enough: a control that has never been laid out would still
## read position (0, 0) and the rise would end there. Two are: the second comes after the flush.
## An earlier entrance of the same control is stopped first, or abandoned if it has not started, so
## two tweens never write one position.
static func stagger_in(controls: Array[Control], gap := -1.0) -> void:
	if controls.is_empty():
		return
	var tokens := UITokens.active()
	var step := tokens.stagger if gap < 0.0 else gap
	var rise := 0.0 if reduced else float(tokens.space_lg)
	var tree := controls[0].get_tree()
	_stagger_serial += 1
	var serial := _stagger_serial
	for control in controls:
		_stop_stagger(control)
		control.set_meta(STAGGER_META, {"serial": serial, "tween": null})
		control.modulate.a = 0.0
	await tree.process_frame
	await tree.process_frame
	for i in controls.size():
		var control := controls[i]
		if not is_instance_valid(control) or _entrance_of(control).get("serial") != serial:
			continue
		var rest := control.position
		control.position = rest + Vector2(0.0, rise)
		var tween := control.create_tween().set_parallel(true)
		apply_ease(tween, UITokens.Ease.ENTER)
		var delay := step * i
		tween.tween_property(control, "modulate:a", 1.0, tokens.dur_base).set_delay(delay)
		tween.tween_property(control, "position", rest, tokens.dur_slow).set_delay(delay)
		_entrance_of(control)["tween"] = tween
		# The layout may have changed while the control rose (a new scale, a longer text): let the
		# container say where it belongs once the rise is over.
		var parent := control.get_parent()
		if parent is Container:
			tween.finished.connect((parent as Container).queue_sort)


static func _entrance_of(control: Control) -> Dictionary:
	return control.get_meta(STAGGER_META, {})


## Stops an earlier entrance of `control`, so two tweens never write one position, and has its
## container put it back where it belongs.
static func _stop_stagger(control: Control) -> void:
	var tween: Tween = _entrance_of(control).get("tween")
	control.remove_meta(STAGGER_META)
	if tween == null or not tween.is_valid():
		return
	tween.kill()
	var parent := control.get_parent()
	if parent is Container:
		(parent as Container).queue_sort()


## A short horizontal shake for a refused action; ends where it started.
static func shake(control: Control) -> Tween:
	var rest := control.position
	var tween := control.create_tween()
	if reduced:
		# A tween with no step is an engine error when it starts; give it one empty step.
		tween.tween_interval(0.0)
		return tween
	apply_ease(tween, UITokens.Ease.EXIT)
	for offset in [10.0, -8.0, 5.0, -2.0, 0.0]:
		tween.tween_property(control, "position:x", rest.x + offset, 0.05)
	return tween
