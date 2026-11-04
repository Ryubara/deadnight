class_name MenuPlate
extends Control
## Top right of every tab: the player's name plate, a ticket with the name, the Billing level and
## the stubs on the left and a ring of progress to the next level, with the level in it, behind
## a perforation. It shows a `MenuProfile` and nothing else.

const SIZE := Vector2(440.0, 74.0)
const RING_ZONE := 108.0
## A phone's plate is narrower, to leave the tab bar its room.
const COMPACT_WIDTH := 372.0

var _paper: MenuLook.Paper
var _name: Label
var _level: Label
var _stubs: Label
var _ring: MenuLook.Ring
var _ring_number: Label


## `width` (when it is more than 0) is the plate's own width: the tab bar's end leaves less than
## `COMPACT_WIDTH` on the narrowest phone canvas (960 units).
func _init(compact := false, width := 0.0) -> void:
	var plate_size := Vector2(COMPACT_WIDTH if compact else SIZE.x, SIZE.y)
	if width > 0.0:
		plate_size.x = minf(plate_size.x, width)
	custom_minimum_size = plate_size
	size = plate_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper = MenuLook.Paper.new(9.0)
	_paper.perf_x = plate_size.x - RING_ZONE
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_paper)
	_name = MenuLook.label("", 30, MenuLook.PAPER_INK, &"wide")
	_name.position = Vector2(24.0, 2.0)
	_name.size = Vector2(plate_size.x - RING_ZONE - 40.0, 38.0)
	# A name of sixteen wide letters is longer than the room before the ring: it ends in an
	# ellipsis instead of running over the ring.
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_name)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 12)
	line.position = Vector2(24.0, 40.0)
	line.size = Vector2(plate_size.x - RING_ZONE - 40.0, 28.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	_level = MenuLook.label("", MenuLook.SIZE_CAPTION, MenuLook.RED, &"wide")
	_stubs = MenuLook.label("", MenuLook.SIZE_CAPTION, MenuLook.PAPER_MUTED, &"wide")
	_stubs.clip_text = true
	_stubs.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stubs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_level)
	line.add_child(_stubs)
	_ring = MenuLook.Ring.new()
	var diameter := SIZE.y - 12.0
	_ring.size = Vector2(diameter, diameter)
	_ring.position = Vector2(plate_size.x - RING_ZONE * 0.5 - diameter * 0.5, 6.0)
	add_child(_ring)
	_ring_number = MenuLook.label(
		"", 24, MenuLook.PAPER_INK, &"display", HORIZONTAL_ALIGNMENT_CENTER
	)
	_ring_number.size = Vector2(diameter, diameter)
	_ring_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ring_number.position = _ring.position
	add_child(_ring_number)


## Shows `profile`.
func show_profile(profile: MenuProfile) -> void:
	_name.text = profile.display_name.to_upper()
	_level.text = "LEVEL %d" % profile.level()
	_stubs.text = "%s STUBS" % MenuNav.grouped(profile.stubs)
	_ring.fraction = profile.level_fraction()
	_ring.queue_redraw()
	_ring_number.text = str(profile.level())


func name_text() -> String:
	return _name.text


func level_text() -> String:
	return _level.text


func stubs_text() -> String:
	return _stubs.text


## How far round the ring is, 0 to 1.
func level_fraction() -> float:
	return _ring.fraction
