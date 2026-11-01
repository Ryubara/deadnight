class_name UIMotion
extends RefCounted
## Tween presets driven by UITokens, and the reduced-motion switch.
##
## Nothing here is linear: every move uses a named easing. With `reduced` set, movement
## completes at once; fades stay (a fade is not motion).

const SETTING_REDUCED := "gds_ui/accessibility/reduced_motion"

static var reduced := false


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


## Fade up from below, one control after another (`gap` seconds apart). Waits a frame so a
## container has placed its children first; the controls are hidden until then.
static func stagger_in(controls: Array[Control], gap := -1.0) -> void:
	if controls.is_empty():
		return
	var tokens := UITokens.active()
	var step := tokens.stagger if gap < 0.0 else gap
	var rise := 0.0 if reduced else float(tokens.space_lg)
	for control in controls:
		control.modulate.a = 0.0
	await controls[0].get_tree().process_frame
	for i in controls.size():
		var control := controls[i]
		if not is_instance_valid(control):
			continue
		var rest := control.position
		control.position = rest + Vector2(0.0, rise)
		var tween := control.create_tween().set_parallel(true)
		apply_ease(tween, UITokens.Ease.ENTER)
		var delay := step * i
		tween.tween_property(control, "modulate:a", 1.0, tokens.dur_base).set_delay(delay)
		tween.tween_property(control, "position", rest, tokens.dur_slow).set_delay(delay)


## A short horizontal shake for a refused action; ends where it started.
static func shake(control: Control) -> Tween:
	var rest := control.position
	var tween := control.create_tween()
	if reduced:
		return tween
	apply_ease(tween, UITokens.Ease.EXIT)
	for offset in [10.0, -8.0, 5.0, -2.0, 0.0]:
		tween.tween_property(control, "position:x", rest.x + offset, 0.05)
	return tween
