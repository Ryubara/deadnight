@tool
class_name UIFitScroll
extends UIScroll
## A scroll area that asks for the height its content needs and no more than the screen has left,
## so a card holding it never grows past its area. The part of the card that is not this area (a
## title above, buttons below) keeps its own height and stays on the screen; the rows in between
## scroll. Without it a card built from a column is as tall as its tallest state, and a screen
## shorter than that (a phone held sideways is 540 units, a laptop's browser frame 720 px) lets it
## run under the footer or off the edge.
##
## Put it inside the card (a `UIPanel`, or any control whose height is the screen's concern), give
## it one child, the content. The card is the nearest ancestor that is not a plain container
## (`card`, set it to choose another). The room is the height of `limit` (default: the viewport)
## less `margin` above and below and less what the rest of the card needs.

## What the card may take: this control's height. Empty is the viewport's.
@export var limit: Control
## Free height kept above and below the card, the screen's own margins.
@export var margin := 0.0
## The card whose whole height must fit; the nearest `PanelContainer` ancestor when not set.
@export var card: Control
## The height the area keeps when its content is shorter and the screen has the room, so a card
## does not jump between pages of different lengths.
@export var steady := 0.0
## The least height the area keeps, so a very short screen still shows a row (at the cost of the
## card being taller than the screen).
@export var least := 120.0

var _queued := false


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	child_entered_tree.connect(_on_child_entered)
	for child in get_children():
		_watch(child)
	get_viewport().size_changed.connect(_queue_fit)
	resized.connect(_queue_fit)
	_queue_fit()


func _on_child_entered(child: Node) -> void:
	_watch(child)
	_queue_fit()


func _watch(child: Node) -> void:
	var control := child as Control
	if control != null and not control.minimum_size_changed.is_connected(_queue_fit):
		control.minimum_size_changed.connect(_queue_fit)


func _queue_fit() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_fit_deferred.call_deferred()


func _fit_deferred() -> void:
	_queued = false
	if is_inside_tree():
		fit()


## Sets the area's height now: the content's, or the room the screen leaves if that is less.
func fit() -> void:
	var content := maxf(_content_height(), steady)
	var holder := card if card != null else _nearest_card()
	if holder == null:
		return
	# The rest of the card is what it needs with this area asking for nothing.
	custom_minimum_size.y = 0.0
	var rest := holder.get_combined_minimum_size().y
	var screen := limit.size.y if limit != null else get_viewport_rect().size.y
	var room := screen - 2.0 * margin - rest
	custom_minimum_size.y = clampf(content, minf(least, content), maxf(room, least))


## The height the content asks for, with the room the theme keeps around it.
func _content_height() -> float:
	var height := 0.0
	for child in get_children():
		var control := child as Control
		if control != null and control.visible:
			height = maxf(height, control.get_combined_minimum_size().y)
	return height + UIScroll.margins(self).y


func _nearest_card() -> Control:
	var up := get_parent()
	while up != null:
		if up is PanelContainer:
			return up as Control
		up = up.get_parent()
	return get_parent() as Control
