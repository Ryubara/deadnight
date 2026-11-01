extends CanvasLayer
## The screen router (autoload `UIRouter`): a stack of screens with transitions.
##
## push / replace / pop / reset take a PackedScene, a scene path or an instanced Control, and a
## transition kind. Calls made while a transition runs are queued. Back (`ui_cancel`) pops.
## Input is blocked while a transition runs.

signal idle
signal screen_changed(depth: int)

const BURN_SHADER := preload("res://addons/gds_ui/shaders/film_burn.gdshader")
const IRIS_SHADER := preload("res://addons/gds_ui/shaders/projector_iris.gdshader")
const LAYER := 100
const FOCUS_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"
]

var busy := false

var _tokens: UITokens
var _stage: Control
var _overlay: ColorRect
var _stack: Array[Control] = []
var _queue: Array[Callable] = []
## How each stacked screen was pushed, so a pop plays the same transition backwards.
var _kinds := {}


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIMotion.load_settings()
	_tokens = UITokens.active()
	# A fade passes through the background colour, not the engine's grey.
	RenderingServer.set_default_clear_color(_tokens.bg)
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.theme = UIThemeBuilder.build(_tokens)
	_stage.clip_contents = true
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)


func depth() -> int:
	return _stack.size()


func top() -> Control:
	return _stack.back() if not _stack.is_empty() else null


## Shows a screen over the current one, which stays alive underneath.
func push(source: Variant, kind := UITransition.Kind.FADE, params := {}) -> void:
	_submit(_do_push.bind(source, kind, params, false))


## Shows a screen in place of the current one, which is freed.
func replace(source: Variant, kind := UITransition.Kind.FADE, params := {}) -> void:
	_submit(_do_push.bind(source, kind, params, true))


## Returns to the previous screen and frees the current one. Does nothing at the root.
## `kind` -1 repeats the transition the screen arrived with.
func pop(kind := -1) -> void:
	_submit(_do_pop.bind(kind))


## Frees the whole stack and shows one screen.
func reset(source: Variant, kind := UITransition.Kind.CUT, params := {}) -> void:
	_submit(_do_reset.bind(source, kind, params))


func _input(event: InputEvent) -> void:
	UIInputMode.track(event)
	if busy:
		get_viewport().set_input_as_handled()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null and top() != null and _is_focus_action(event):
		_focus_top()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if busy or not event.is_action_pressed(&"ui_cancel") or _stack.size() < 2:
		return
	var screen := top() as UIScreen
	if screen != null and not screen.allow_back:
		return
	UIAudio.play(&"back")
	pop()
	get_viewport().set_input_as_handled()


func _is_focus_action(event: InputEvent) -> bool:
	for action in FOCUS_ACTIONS:
		if event.is_action_pressed(action):
			return true
	return false


func _focus_top() -> void:
	var screen := top() as UIScreen
	if screen != null:
		screen.focus_initial()


func _submit(job: Callable) -> void:
	_queue.append(job)
	if not busy:
		_drain()


func _drain() -> void:
	busy = true
	while not _queue.is_empty():
		var job: Callable = _queue.pop_front()
		await job.call()
	busy = false
	idle.emit()


func _do_push(
	source: Variant, kind: UITransition.Kind, params: Dictionary, replacing: bool
) -> void:
	var incoming := _instance(source, params)
	if incoming == null:
		return
	var outgoing := top()
	UIAudio.play(&"push")
	await _run(outgoing, incoming, kind, false)
	if outgoing != null:
		if replacing:
			_stack.erase(outgoing)
			_kinds.erase(outgoing)
			outgoing.queue_free()
		else:
			_pause(outgoing)
	_stack.append(incoming)
	_kinds[incoming] = kind
	_finish(incoming, false)


func _do_pop(requested: int) -> void:
	if _stack.size() < 2:
		return
	var outgoing := _stack.pop_back() as Control
	var kind: UITransition.Kind = (
		_kinds.get(outgoing, UITransition.Kind.FADE) if requested < 0 else requested
	)
	_kinds.erase(outgoing)
	var incoming := top()
	UIAudio.play(&"pop")
	await _run(outgoing, incoming, kind, true)
	outgoing.queue_free()
	_finish(incoming, true)


func _do_reset(source: Variant, kind: UITransition.Kind, params: Dictionary) -> void:
	var incoming := _instance(source, params)
	if incoming == null:
		return
	var old := _stack.duplicate()
	await _run(top(), incoming, kind, false)
	for screen in old:
		screen.queue_free()
	_stack.clear()
	_kinds.clear()
	_stack.append(incoming)
	_finish(incoming, false)


func _run(outgoing: Control, incoming: Control, kind: UITransition.Kind, reverse: bool) -> void:
	if outgoing is UIScreen:
		(outgoing as UIScreen).remember_focus()
	incoming.hide()
	incoming.process_mode = Node.PROCESS_MODE_INHERIT
	if incoming.get_parent() == null:
		_stage.add_child(incoming)
		incoming.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ctx := UITransitionContext.new()
	ctx.stage = _stage
	ctx.overlay = _overlay
	ctx.outgoing = outgoing
	ctx.incoming = incoming
	ctx.reverse = reverse
	ctx.tokens = _tokens
	ctx.origin = _focus_origin()
	await _make(kind).play(ctx)


func _make(kind: UITransition.Kind) -> UITransition:
	if (
		UIMotion.reduced
		and kind in [UITransition.Kind.SLIDE, UITransition.Kind.BURN, UITransition.Kind.IRIS]
	):
		kind = UITransition.Kind.FADE
	match kind:
		UITransition.Kind.FADE:
			return UITransitionFade.new()
		UITransition.Kind.SLIDE:
			return UITransitionSlide.new()
		UITransition.Kind.BURN:
			return UITransitionShader.new(BURN_SHADER)
		UITransition.Kind.IRIS:
			return UITransitionShader.new(IRIS_SHADER)
	return UITransition.new()


## The focused control's centre as a 0..1 point on the stage; the middle when nothing has focus.
func _focus_origin() -> Vector2:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or _stage.size.x <= 0.0 or _stage.size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var centre := focused.get_global_rect().get_center() - _stage.global_position
	return (centre / _stage.size).clamp(Vector2.ZERO, Vector2.ONE)


func _instance(source: Variant, params: Dictionary) -> Control:
	var node: Node = null
	if source is PackedScene:
		node = (source as PackedScene).instantiate()
	elif source is String or source is StringName:
		node = (load(str(source)) as PackedScene).instantiate()
	elif source is Control:
		node = source
	var screen := node as Control
	if screen == null:
		push_error(
			"UIRouter: cannot show %s (need a PackedScene, a scene path or a Control)" % str(source)
		)
		return null
	if screen is UIScreen:
		(screen as UIScreen).params = params
	return screen


func _pause(screen: Control) -> void:
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	if screen is UIScreen:
		(screen as UIScreen).screen_pause()


func _finish(screen: Control, resumed: bool) -> void:
	screen.process_mode = Node.PROCESS_MODE_INHERIT
	if screen is UIScreen:
		var ui_screen := screen as UIScreen
		if resumed:
			ui_screen.screen_resume()
		else:
			ui_screen.screen_enter()
	else:
		_focus_top()
	screen_changed.emit(_stack.size())
