extends CanvasLayer
## The screen router (autoload `UIRouter`): a stack of screens with transitions.
##
## push / replace / pop / reset take a PackedScene, a scene path or an instanced Control, and a
## transition kind. Calls made while a transition runs are queued. Back (`ui_cancel`) pops.
## Input is blocked while a transition runs.
##
## A screen can be freed at any time (a game-over handler, a disconnect). A freed screen leaves
## the stack at once, a transition that loses a screen still ends, and the queue keeps draining.
## When the top screen is freed while the router is idle, the screen below is shown, resumed and
## focused. If nothing is left, the stack is empty (`depth() == 0`) and the stage is blank until
## the next `push` or `reset`; `screen_changed(0)` says so.
##
## A request the router cannot honour (a source it cannot show, a pop or reset that lost its
## screen) logs one error and emits `error_reported` with the same text.

signal idle
signal screen_changed(depth: int)
signal error_reported(message: String)

const BURN_SHADER := preload("res://addons/gds_ui/shaders/film_burn.gdshader")
## The burn covers the whole screen from about this progress, and shows nothing new before the
## reveal reaches `BURN_REVEAL_FROM`: both ends of the hold on char are cut (measured in
## docs/research/main-menu.md).
const BURN_CLOSE_TO := 0.97
const BURN_REVEAL_FROM := 0.27
const IRIS_SHADER := preload("res://addons/gds_ui/shaders/projector_iris.gdshader")
const LAYER := 100
const NOT_SHOWN := "UIRouter: cannot show %s (need a scene, its path or a Control)"
const ALREADY_SHOWN := "UIRouter: cannot show %s (it is already on the stack or in the tree)"
const LOST_POP_TARGET := "UIRouter: pop lost the screen below it; the stack is empty"
const LOST_RESET_SCREEN := "UIRouter: reset lost its new screen; the stack is empty"
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
var _reveal_pending := false


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	UIMotion.load_settings()
	_tokens = UITokens.active()
	_stage = Control.new()
	_stage.name = "Stage"
	# The stage only holds screens and lets the mouse through: a screen over a game world (a
	# night) must not eat the mouse motion the world's look reads in `_unhandled_input`.
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = true
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.hide()
	add_child(_overlay)
	_restyle(_tokens)
	UITokens.active_changed().connect(_restyle)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Applies tokens to what the router owns: the stage's theme (every screen under it inherits it) and
## the colour behind a fade, so a fade passes through the background colour, not the engine's grey.
## It runs at startup and again whenever `UITokens.set_active` changes the tokens; a transition that
## is already playing keeps the tokens it started with.
func _restyle(tokens: UITokens) -> void:
	_tokens = tokens
	RenderingServer.set_default_clear_color(tokens.bg)
	_stage.theme = UIThemeBuilder.build(tokens)


## A key or a pad moved the focus: a scroll area that follows it shows the whole ring of the row it
## reached (after the area's own follow, which shows the row and stops at its edge).
func _on_focus_changed(control: Control) -> void:
	if not UIInputMode.pointer:
		UIFocusRing.keep_in_view.call_deferred(control)


func depth() -> int:
	return _stack.size()


## The stack from the root to the visible top.
func screens() -> Array[Control]:
	return _stack.duplicate()


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
	if focused == null and _top_wants_focus_key() and _is_focus_action(event):
		_focus_top()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if busy or not event.is_action_pressed(&"ui_cancel") or _stack.size() < 2:
		return
	var screen := top() as UIScreen
	if screen != null and not screen.allow_back:
		return
	UIAudio.play(&"back", self)
	pop()
	get_viewport().set_input_as_handled()


func _top_wants_focus_key() -> bool:
	var screen := top()
	if screen == null:
		return false
	var ui_screen := screen as UIScreen
	return ui_screen == null or ui_screen.wants_focus_key()


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
	UIAudio.play(&"push", self)
	await _run(outgoing, incoming, kind, false)
	if not is_instance_valid(incoming):
		# Lost mid-transition: the screen underneath stays, as if the push never happened.
		_show_top()
		return
	if is_instance_valid(outgoing):
		if replacing:
			_stack.erase(outgoing)
			_kinds.erase(outgoing)
			outgoing.queue_free()
		else:
			_pause(outgoing)
	_adopt(incoming, kind)
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
	UIAudio.play(&"pop", self)
	await _run(outgoing, incoming, kind, true)
	if is_instance_valid(outgoing):
		outgoing.queue_free()
	if top() != null:
		_reveal_top()
	else:
		_report(LOST_POP_TARGET)
		screen_changed.emit(0)


func _do_reset(source: Variant, kind: UITransition.Kind, params: Dictionary) -> void:
	var incoming := _instance(source, params)
	if incoming == null:
		return
	var old := _stack.duplicate()
	await _run(top(), incoming, kind, false)
	for screen in old:
		if is_instance_valid(screen):
			screen.queue_free()
	_stack.clear()
	_kinds.clear()
	if not is_instance_valid(incoming):
		_report(LOST_RESET_SCREEN)
		screen_changed.emit(0)
		return
	_adopt(incoming, kind)
	_finish(incoming, false)


func _run(outgoing: Control, incoming: Control, kind: UITransition.Kind, reverse: bool) -> void:
	if outgoing is UIScreen and is_instance_valid(outgoing):
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
			return UITransitionShader.new(BURN_SHADER, BURN_CLOSE_TO, BURN_REVEAL_FROM)
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
	# A freed object is rejected before any `is` test, which raises a script error on one.
	if typeof(source) == TYPE_OBJECT and not is_instance_valid(source):
		_report(NOT_SHOWN % str(source))
		return null
	var node: Node = null
	if source is PackedScene:
		node = (source as PackedScene).instantiate()
	elif source is String or source is StringName:
		var scene: Resource = null
		if ResourceLoader.exists(str(source)):
			scene = load(str(source))
		if scene is PackedScene:
			node = (scene as PackedScene).instantiate()
	elif source is Control:
		# The caller owns a ready-made screen: it is never freed here, and it must stand alone.
		var given := source as Control
		if given in _stack or given.get_parent() != null:
			_report(ALREADY_SHOWN % given.name)
			return null
		node = given
	var screen := node as Control
	if screen == null:
		if node != null:
			node.free()
		_report(NOT_SHOWN % str(source))
		return null
	if screen is UIScreen:
		(screen as UIScreen).params = params
	return screen


func _report(message: String) -> void:
	push_error(message)
	error_reported.emit(message)


## Puts a shown screen on the stack. It leaves the stack by itself when it is freed.
func _adopt(screen: Control, kind: UITransition.Kind) -> void:
	_stack.append(screen)
	_kinds[screen] = kind
	screen.tree_exiting.connect(_forget.bind(screen), CONNECT_ONE_SHOT)


func _forget(screen: Control) -> void:
	var was_top: bool = not _stack.is_empty() and _stack.back() == screen
	_stack.erase(screen)
	_kinds.erase(screen)
	# Freed on top while nothing runs: no transition will show the screen below, so do it here.
	# A running job (a pop, a replace) finishes the stack itself.
	if was_top and not busy and not _reveal_pending:
		_reveal_pending = true
		_reveal_idle_top.call_deferred()


func _reveal_idle_top() -> void:
	_reveal_pending = false
	if busy or not is_inside_tree():
		return
	if _stack.is_empty():
		screen_changed.emit(0)
	else:
		_reveal_top()


## Makes the top screen visible, enabled, at rest and focused: where every pop ends.
func _reveal_top() -> void:
	_show_top()
	_finish(top(), true)


## Makes the screen on top of the stack visible and at rest, whatever a transition left on it.
func _show_top() -> void:
	var screen := top()
	if screen == null:
		return
	screen.show()
	screen.position.x = 0.0
	screen.modulate = Color.WHITE
	screen.scale = Vector2.ONE


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
