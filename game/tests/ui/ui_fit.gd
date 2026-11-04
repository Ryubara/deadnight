class_name UiFit
extends RefCounted
## The fit of a screen to its own area, as a list of sentences (empty when it fits). One check
## for the test suite and the capture tour, so a number printed by the tour is the number the
## suite fails on (#980: panels taller than their area ran under the footer's key hints).
##
## A control is looked at where a player sees it: its rectangle (with the focus ring around it
## when it takes the focus) cut by every ancestor that clips (a `ScrollContainer`, any control with
## `clip_contents`). What is hidden by scrolling is not on the screen and is not asked to fit.
## Four rules, each a sentence:
##
## - **off the screen**: the shown part leaves the canvas.
## - **outside its area**: the shown part leaves `area` (a panel's allotted rectangle).
## - **under <zone>**: the shown part meets a keep-out zone (the footer, the header) that the
##   control does not belong to.
## - **cut, not scrolled**: the control is wider or taller than an ancestor that clips it, on an
##   axis that ancestor cannot scroll, so part of it can never be reached.

const TOLERANCE := 1.0


## A rectangle that a screen's content keeps clear. `owners` are the nodes that belong to it
## (the footer's own labels): they and their descendants are not asked to keep clear of it.
class Zone:
	extends RefCounted
	var label := ""
	var rect := Rect2()
	var owners: Array[Node] = []

	static func make(name: String, at: Rect2, belongs: Array = []) -> Zone:
		var zone := Zone.new()
		zone.label = name
		zone.rect = at
		for node: Node in belongs:
			zone.owners.append(node)
		return zone


## The sentences for every control under `root` that breaks a rule. `canvas` is the screen,
## `area` the rectangle the content belongs in (an empty rectangle: no such rule), `zones` the
## keep-out rectangles, `ring` the room a focused control's ring takes around it (checked against
## the screen's edge only: a ring is paint, and it may lie over its area's margin).
##
## Only the outermost control that breaks a rule is named: a column that is too tall is one
## sentence, not one for each of its buttons.
static func check(
	root: Node, canvas: Rect2, area := Rect2(), zones: Array[Zone] = [], ring := 0.0
) -> Array[String]:
	var found: Array[String] = []
	var broken := {}
	var controls := root.find_children("*", "Control", true, false)
	if root is Control:
		controls.push_front(root)
	for node in controls:
		var control := node as Control
		if control == null or not _counts(control, root):
			continue
		var rules := _rules(control, canvas, area, zones, ring)
		if rules.is_empty():
			continue
		broken[control] = rules
		var parent := control.get_parent() as Control
		var parent_rules: Dictionary = broken.get(parent, {})
		for key: String in rules:
			if not parent_rules.has(key):
				found.append(
					(
						"%s %s: %s"
						% [_name(control, root), _round(shown_rect(control, canvas)), rules[key]]
					)
				)
	return found


## The rules a control breaks: `{rule key: sentence}`.
static func _rules(
	control: Control, canvas: Rect2, area: Rect2, zones: Array[Zone], ring: float
) -> Dictionary:
	var rules := {}
	for line in _cut_axes(control, control.get_global_rect(), canvas):
		rules["cut"] = line
	var shown := shown_rect(control, canvas)
	if shown.size.x <= 0.0 or shown.size.y <= 0.0:
		return rules
	# A scroll area keeps the theme's room around its content for a hover and a ring; it is the
	# box inside that room which belongs in the area.
	if control is ScrollContainer:
		shown = _inside_room(control as ScrollContainer, shown)
	var ringed := shown.grow(ring) if control.focus_mode != Control.FOCUS_NONE else shown
	if not canvas.grow(TOLERANCE).encloses(ringed):
		rules["screen"] = "off the screen %s" % _round(canvas)
	if area.size != Vector2.ZERO and not area.grow(TOLERANCE).encloses(shown):
		rules["area"] = "outside its area %s" % _round(area)
	for zone in zones:
		if not _belongs(control, zone) and zone.rect.grow(-TOLERANCE).intersects(shown):
			rules["zone " + zone.label] = "under the %s %s" % [zone.label, _round(zone.rect)]
	return rules


## The part of the control a player sees: its rectangle cut by each ancestor that clips. Empty
## (size zero) when scrolled or clipped out of sight.
## A clipper that holds the whole `canvas` (the router's stage) is the screen's edge, which has
## its own rule, so it is not taken into account when `canvas` is given.
static func shown_rect(control: Control, canvas := Rect2()) -> Rect2:
	var rect := control.get_global_rect()
	var up := control.get_parent()
	while up != null:
		var clip := up as Control
		if clip != null and _clips(clip):
			if (
				canvas.size != Vector2.ZERO
				and clip.get_global_rect().grow(TOLERANCE).encloses(canvas)
			):
				up = up.get_parent()
				continue
			rect = rect.intersection(clip.get_global_rect())
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return Rect2(rect.position, Vector2.ZERO)
		up = up.get_parent()
	return rect


## The scroll area's rectangle less the room its theme keeps around the content.
static func _inside_room(scroll: ScrollContainer, rect: Rect2) -> Rect2:
	var style := scroll.get_theme_stylebox(&"panel")
	var bar := scroll.get_v_scroll_bar()
	var track := bar.get_combined_minimum_size().x if scroll.vertical_scroll_mode != 0 else 0.0
	return rect.grow_individual(
		-style.get_margin(SIDE_LEFT),
		-style.get_margin(SIDE_TOP),
		-style.get_margin(SIDE_RIGHT) - track,
		-style.get_margin(SIDE_BOTTOM)
	)


## Whether the control cuts off what lies outside its rectangle.
static func _clips(control: Control) -> bool:
	return control.clip_contents or control is ScrollContainer


## A control worth asking: shown, with a size, and not the root of a layer that only holds others.
static func _counts(control: Control, root: Node) -> bool:
	if not control.is_visible_in_tree() or control is ScrollBar:
		return false
	if control.size.x <= 0.0 or control.size.y <= 0.0:
		return false
	# A scroll area or container is asked through its children; it is the clipper itself.
	return control != root or not (control is Container)


## One sentence for each axis on which a clipping ancestor cannot scroll and the control is
## larger than it, or sits outside it.
static func _cut_axes(control: Control, rect: Rect2, canvas: Rect2) -> Array[String]:
	var lines: Array[String] = []
	var up := control.get_parent()
	while up != null:
		var clip := up as Control
		if clip != null and _clips(clip):
			var room := clip.get_global_rect()
			# The screen's own edge is the "off the screen" rule, not this one.
			if room.grow(TOLERANCE).encloses(canvas):
				up = up.get_parent()
				continue
			var scroll := clip as ScrollContainer
			var x_scrolls := scroll != null and scroll.horizontal_scroll_mode != 0
			var y_scrolls := scroll != null and scroll.vertical_scroll_mode != 0
			var inner := room
			if (
				not x_scrolls
				and (
					rect.position.x < inner.position.x - TOLERANCE
					or rect.end.x > inner.end.x + TOLERANCE
				)
			):
				lines.append("cut, not scrolled, sideways by %s %s" % [clip.name, _round(room)])
				break
			if (
				not y_scrolls
				and (
					rect.position.y < inner.position.y - TOLERANCE
					or rect.end.y > inner.end.y + TOLERANCE
				)
			):
				lines.append("cut, not scrolled, vertically by %s %s" % [clip.name, _round(room)])
				break
		up = up.get_parent()
	return lines


static func _belongs(control: Control, zone: Zone) -> bool:
	for owner in zone.owners:
		if owner == control or owner.is_ancestor_of(control) or control.is_ancestor_of(owner):
			return true
	return false


static func _name(control: Control, root: Node) -> String:
	if control == root:
		return String(control.name)
	var parts: PackedStringArray = []
	for part in String(root.get_path_to(control)).split("/"):
		# An engine-named node is "@Class@12": the class says enough.
		parts.append(part.split("@")[1] if part.begins_with("@") else part)
	return "/".join(parts)


static func _round(rect: Rect2) -> String:
	return (
		"(%d,%d %dx%d)"
		% [
			roundi(rect.position.x),
			roundi(rect.position.y),
			roundi(rect.size.x),
			roundi(rect.size.y)
		]
	)
