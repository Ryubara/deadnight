class_name LoadingOverlay
extends Control
## The screen over a night while it gets ready: the Deadnight name, a bar and what is being done.
## It covers the 3D world completely (the warm-up draws the lot and its effects behind it), takes
## `show_progress` from `Night.loading`, and goes when `finish` is called.

const BAR_WIDTH := 640.0
## How fast the bar eases toward its target (per second), so a step that takes the main thread for a
## while does not make it jump.
const EASE_RATE := 8.0
const FADE_SECONDS := 0.35

var _tokens := UITokens.active()
var _title := UILabel.new()
var _step := UILabel.new()
var _fill := ColorRect.new()
var _track := ColorRect.new()
var _target := 0.0
var _shown := 0.0
var _finished := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = _tokens.bg
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = BAR_WIDTH
	box.add_theme_constant_override(&"separation", _tokens.space_md)
	centre.add_child(box)
	_title.style = UILabel.Style.TITLE
	_title.text = "Dusk at the drive-in"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_track.color = _tokens.outline
	_track.custom_minimum_size = Vector2(BAR_WIDTH, _tokens.track_height)
	box.add_child(_track)
	_fill.color = _tokens.accent
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(0.0, _tokens.track_height)
	_track.add_child(_fill)
	_step.style = UILabel.Style.CAPTION
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step.modulate = _tokens.ink_muted
	_step.text = " "
	box.add_child(_step)


func _process(delta: float) -> void:
	_shown = lerpf(_shown, _target, 1.0 - exp(-EASE_RATE * delta))
	_fill.size.x = BAR_WIDTH * _shown


## The bar's target (0 to 1) and the line under it.
func show_progress(fraction: float, text: String) -> void:
	_target = clampf(fraction, 0.0, 1.0)
	if text != "":
		_step.text = text


## The fraction the bar shows now (it eases toward the target).
func shown_fraction() -> float:
	return _shown


## Fills the bar and fades the overlay away, then frees it.
func finish() -> void:
	if _finished:
		return
	_finished = true
	_target = 1.0
	_shown = 1.0
	_fill.size.x = BAR_WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)
