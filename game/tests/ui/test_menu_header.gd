extends GdUnitTestSuite
## What a phone's menu shows on opening, on every phone page down to the narrowest (667 x 375 CSS
## px: a 1334 x 750 canvas, 960 x 540 units): the whole of every top tab with nothing over it,
## and a full row of the wardrobe's items in the Loadout card (#1271).
##
## The header's fault came from the order things happen on a real page: the menu is built before
## the phone factor is on the window (the shell is not shown yet), so the plate was sized on a
## canvas of 1920 units and stood over the end of a bar 960 units wide. The tests build the shell
## the same way: hidden, on a window at the interface size, then shown.

const TEST_PATH := "user://menu_header_test.cfg"
## [window, page's pixel ratio]: the narrowest page, the common one, a long one, and the same
## pages as native windows.
const PAGES: Array = [
	[Vector2i(1334, 750), 2.0],
	[Vector2i(1688, 780), 2.0],
	[Vector2i(1864, 860), 2.0],
	[Vector2i(667, 375), 1.0],
	[Vector2i(844, 390), 1.0],
	[Vector2i(932, 430), 1.0],
]

var _run: UiFitRun
var _saved_path: String
var _stage: Control


func before_test() -> void:
	_saved_path = Settings.path
	Settings.path = TEST_PATH
	Settings.reset_defaults()
	await RouterFixture.clear(get_tree())
	_run = UiFitRun.new(get_tree())
	_run.begin()


func after_test() -> void:
	await _run.close()
	if is_instance_valid(_stage):
		_stage.get_parent().free()
	_run.restore()
	Settings.reset_defaults()
	Settings.save()
	Settings.path = _saved_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## A shell built the way the game builds it: on a window at the interface size, under a part that is
## not shown yet, shown a frame later (the phone factor goes on the window then).
func _open_hidden(window: Vector2i, ratio: float, tab: MenuTab.Id) -> MenuShell:
	await _run.set_window(window, 1.0, ratio)
	get_tree().root.content_scale_factor = 1.0
	var shell := MenuShell.new()
	shell.manual_stage = true
	shell.phone_mode = 1
	shell.context.board = FakeChallengeBoard.new()
	shell.context.profile = MenuProfile.from_json(
		MenuProfile.to_json("Ann", MenuProfile.xp_at(7) + 90, 1250, {"rifle": 900})
	)
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	_stage = Control.new()
	_stage.theme = UIThemeBuilder.build(UITokens.active())
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.visible = false
	layer.add_child(_stage)
	_stage.add_child(shell)
	await _run.frames(2)
	_stage.visible = true
	await _run.frames(2)
	shell.show_tab(tab, false)
	await _run.frames()
	return shell


func _tag(window: Vector2i, ratio: float) -> String:
	return "%dx%d@%s" % [window.x, window.y, ratio]


func test_the_plate_is_clear_of_every_tab_when_the_shell_is_built_before_the_factor() -> void:
	var problems: Array[String] = []
	for entry: Array in PAGES:
		var shell := await _open_hidden(entry[0], entry[1], MenuTab.Id.LOADOUT)
		var canvas := _run.canvas()
		var plate := shell.plate.get_global_rect()
		for id: MenuTab.Id in MenuTab.ORDER:
			var tab := shell.tab_bar.button(id).get_global_rect()
			if tab.intersects(plate):
				problems.append(
					"%s %s %s is under the plate %s" % [_tag(entry[0], entry[1]), id, tab, plate]
				)
			if not canvas.grow(0.5).encloses(tab):
				problems.append(
					"%s %s %s is off the canvas %s" % [_tag(entry[0], entry[1]), id, tab, canvas]
				)
		if not canvas.grow(0.5).encloses(plate):
			problems.append(
				"%s plate %s is off the canvas %s" % [_tag(entry[0], entry[1]), plate, canvas]
			)
		await _run.close()
		_stage.get_parent().free()
	(
		assert_array(problems)
		. override_failure_message(
			"%d header problems:\n%s" % [problems.size(), "\n".join(problems)]
		)
		. is_empty()
	)


func test_the_plate_follows_a_canvas_that_changes_under_it() -> void:
	var shell := await _open_hidden(Vector2i(1688, 780), 2.0, MenuTab.Id.PLAY)
	var wide := shell.plate.get_global_rect().size.x
	# The page turns to the narrowest: the plate gives the bar its room.
	await _run.set_window(Vector2i(1334, 750), 1.0, 2.0)
	get_tree().root.content_scale_factor = MenuScale.PHONE_FACTOR
	await _run.frames(3)
	var bar_end := shell.tab_bar.get_global_rect().end.x
	assert_float(shell.plate.get_global_rect().position.x).is_greater_equal(bar_end)
	assert_float(shell.plate.get_global_rect().size.x).is_less(wide)


func test_the_last_tab_takes_a_tap_along_its_whole_width() -> void:
	for entry: Array in PAGES:
		var shell := await _open_hidden(entry[0], entry[1], MenuTab.Id.PLAY)
		var more := shell.tab_bar.button(MenuTab.Id.MORE).get_global_rect()
		for x in [more.position.x + 3.0, more.get_center().x, more.end.x - 3.0]:
			shell.show_tab(MenuTab.Id.PLAY, false)
			await _run.frames(1)
			await _click(Vector2(x, more.get_center().y))
			(
				assert_int(shell.tab)
				. override_failure_message(
					(
						"%s: a tap at x=%s on MORE %s opened %s"
						% [_tag(entry[0], entry[1]), x, more, shell.tab]
					)
				)
				. is_equal(MenuTab.Id.MORE)
			)
		await _run.close()
		_stage.get_parent().free()


func _click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	get_viewport().push_input(move, true)
	await get_tree().process_frame
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at
		click.global_position = at
		get_viewport().push_input(click, true)
		await get_tree().process_frame


## What the Loadout card shows on opening: the wardrobe's own scroll area, its view and what lies
## inside it.
func _wardrobe_view(loadout: LoadoutPanel) -> Dictionary:
	var scroll: ScrollContainer = loadout.wardrobe._picker_scroll
	var view := scroll.get_global_rect()
	var whole_cells := 0
	var cut_at_top: Array[String] = []
	for node in scroll.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if not (control is WardrobeCell or control is Label or control is Button):
			continue
		if not rect.intersects(view):
			continue
		if control is WardrobeCell and view.grow(0.5).encloses(rect):
			whole_cells += 1
		if rect.position.y < view.position.y - 0.5:
			cut_at_top.append("%s %s" % [control.name, rect])
	return {"view": view, "whole_cells": whole_cells, "cut_at_top": cut_at_top}


## What is wrong with the view of the wardrobe's tab on show: no item whole in it, a label cut at
## its top, a page that is scrolled when it opens.
func _view_problems(tag: String, loadout: LoadoutPanel) -> Array[String]:
	var found: Array[String] = []
	var seen := _wardrobe_view(loadout)
	var scrolled: int = loadout.wardrobe._picker_scroll.scroll_vertical
	if scrolled != 0:
		found.append("%s: the card opened scrolled by %d units" % [tag, scrolled])
	if seen["whole_cells"] < 1:
		found.append("%s: no item is whole in the card's view %s" % [tag, seen["view"]])
	if not (seen["cut_at_top"] as Array).is_empty():
		found.append("%s: cut at the top of the view: %s" % [tag, seen["cut_at_top"]])
	return found


func test_the_loadout_card_shows_a_full_row_of_items_on_opening() -> void:
	var problems: Array[String] = []
	for entry: Array in PAGES:
		var shell := await _open_hidden(entry[0], entry[1], MenuTab.Id.LOADOUT)
		var tag := _tag(entry[0], entry[1])
		var loadout := shell.panel(MenuTab.Id.LOADOUT) as LoadoutPanel
		# A key or a bumper into the tab puts the focus on its first control, as a real page does.
		shell.focus_panel()
		await _run.frames(3)
		# Every tab of the wardrobe, each as it is shown by a press: the card's own, and the first
		# one on show.
		for key in loadout.wardrobe.tab_keys():
			loadout.wardrobe.show_tab(key)
			await _run.frames(3)
			problems.append_array(_view_problems("%s %s" % [tag, key], loadout))
		# The card's strip of tabs is one row where the canvas allows (the narrowest does).
		var top := loadout.wardrobe.tab_button(&"body").get_global_rect().position.y
		for key in loadout.wardrobe.tab_keys():
			var tab_top := loadout.wardrobe.tab_button(key).get_global_rect().position.y
			if not is_equal_approx(tab_top, top):
				problems.append("%s: the tab %s is on a second row of the strip" % [tag, key])
		await _run.close()
		_stage.get_parent().free()
	(
		assert_array(problems)
		. override_failure_message(
			"%d Loadout problems:\n%s" % [problems.size(), "\n".join(problems)]
		)
		. is_empty()
	)
