class_name WebClipboard
extends Node
## Copy and paste inside a Discord Activity (Deadnight #516).
##
## The Activity is an iframe of another origin. Two things break the clipboard there. The browser
## keeps the clipboard API (`navigator.clipboard`, which the engine's `DisplayServer.clipboard_get`
## and `clipboard_set` use) from a frame the page around it did not grant `clipboard-read` and
## `clipboard-write`: both calls fail and the engine says nothing. And the engine's web runtime
## cancels every key press on its canvas, so Ctrl+V never makes the page's own `paste` event, the
## one a browser fires with no permission at all.
##
## This node installs `window.deadnightClipboard` (the script below), the whole of it in a frame:
## - Ctrl/Cmd+V is let through to the browser, whose `paste` event hands the text to `heard`, and
##   the next frame `paste` puts it into the focused field;
## - `copy` writes from a user gesture (a hidden text box and `execCommand("copy")`, which the
##   policy does not cover, then the API), and Ctrl/Cmd+C copies the text `offer` set, or the
##   selection of the focused field, through the same native event;
## - `report` says what each of those saw, for `note` and `detail` (the Play together screen reads
##   them, so whoever plays can send the line).
##
## In a browser tab only the paste half is installed (#534): the engine's own Ctrl+V reads the
## clipboard through `navigator.clipboard.readText()`, which answers a moment later, so the first
## press pasted whatever was there before (nothing, on a fresh page). The `paste` event needs no
## permission in a tab either, and `copy_text` stays the engine's own `clipboard_set`.
##
## The desktop is not touched: off the web nothing is installed.

## What a player reads when the host blocks the clipboard API.
const BLOCKED := "Clipboard: the host blocks it here. Ctrl+V and Ctrl+C work through the page."
const ALLOWED := "Clipboard: allowed. Ctrl+V pastes and Ctrl+C copies."
const COPY_FAILED := "Clipboard: copy failed (%s). The text is shown selected: press Ctrl+C."

## The page side. Runs once. Ctrl/Cmd+V and +C are the one place a keydown is not
## stopped from reaching the engine for the engine's sake: the engine would cancel it (so no
## paste event could follow), and the browser's own paste and copy need it uncancelled.
const PAGE_SCRIPT := """
(function () {
  if (window.deadnightClipboard) { return; }
  var canvas = document.getElementById('canvas');
  var policy = document.permissionsPolicy || document.featurePolicy;
  function allowed(name) {
    try { return policy ? policy.allowsFeature(name) : null; } catch (e) { return null; }
  }
  var framed = window.top !== window;
  var c = window.deadnightClipboard = {
    iframe: framed, write: 'untried', offer: '', ctrl_v: 0, pastes: 0, ctrl_c: 0, copies: 0,
    onpaste: null,
    policy_read: allowed('clipboard-read'), policy_write: allowed('clipboard-write')
  };
  function toCanvas() { if (canvas) { canvas.focus(); } }
  c.report = function () {
    return JSON.stringify({iframe: c.iframe, write: c.write, ctrl_v: c.ctrl_v, pastes: c.pastes,
      ctrl_c: c.ctrl_c, copies: c.copies, policy_read: c.policy_read,
      policy_write: c.policy_write});
  };
  function onCanvas(e) {
    var t = e.target;
    return t === canvas || t === document.body || t === document.documentElement;
  }
  addEventListener('paste', function (e) {
    if (!onCanvas(e)) { return; }
    var text = e.clipboardData ? e.clipboardData.getData('text/plain') : '';
    c.pastes++;
    if (c.onpaste) { c.onpaste(text); }
  }, true);
  addEventListener('keydown', function (e) {
    if (!(e.ctrlKey || e.metaKey) || e.altKey || !onCanvas(e) || e.code !== 'KeyV') { return; }
    c.ctrl_v++;
    e.stopImmediatePropagation();
  }, true);
  if (!framed) { return; }
  function gesture(text) {
    var box = document.createElement('textarea');
    box.value = text; box.setAttribute('readonly', '');
    box.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
    document.body.appendChild(box); box.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    box.remove(); toCanvas();
    return ok;
  }
  c.copy = function (text) {
    c.write = 'pending';
    if (gesture(text)) { c.write = 'ok'; return; }
    if (!navigator.clipboard || !navigator.clipboard.writeText) { c.write = 'Unsupported'; return; }
    navigator.clipboard.writeText(text).then(function () { c.write = 'ok'; },
      function (e) { c.write = e && e.name ? e.name : 'Blocked'; });
  };
  addEventListener('keydown', function (e) {
    if (!(e.ctrlKey || e.metaKey) || e.altKey || !onCanvas(e)) { return; }
    if (e.code === 'KeyC' && c.offer) {
      c.ctrl_c++;
      var box = document.getElementById('deadnight-copy') || document.createElement('textarea');
      box.id = 'deadnight-copy'; box.value = c.offer; box.setAttribute('readonly', '');
      box.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0';
      document.body.appendChild(box); box.focus(); box.select();
      e.stopImmediatePropagation();
    }
  }, true);
  addEventListener('copy', function () {
    var box = document.getElementById('deadnight-copy');
    if (box) { c.copies++; setTimeout(function () { box.remove(); toCanvas(); }, 0); }
  }, true);
})();
"""

## The running layer, for a screen to reach; null where there is none (tests, a headless run).
static var current: WebClipboard

## (String) -> Variant: runs a line of script in the page. The browser's by default; a test stands
## in for it.
var eval_js := Callable()
## The game runs inside a frame of another page (a Discord Activity). Decided at start.
var in_frame := false
## The page layer is installed (on the web, in a tab and in a frame): Ctrl+V pastes through the
## page's `paste` event.
var pastes_here := false
## Seconds a copy may take before it counts as refused.
var copy_wait := 2.0

var _callback: JavaScriptObject
var _heard: Array[String] = []
var _offered := ""
var _last_sent := ""


func _ready() -> void:
	current = self
	if OS.has_feature("web") and not eval_js.is_valid():
		eval_js = func(js: String) -> Variant: return JavaScriptBridge.eval(js, true)
		in_frame = bool(eval_js.call("window.top !== window"))
		eval_js.call(PAGE_SCRIPT)
		_callback = JavaScriptBridge.create_callback(heard_by_page)
		JavaScriptBridge.get_interface("window").deadnightClipboard.onpaste = _callback
		pastes_here = true
	set_process(in_frame or pastes_here)


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(_delta: float) -> void:
	while not _heard.is_empty():
		paste(_heard.pop_front())
	if not in_frame:
		return  # copy is the engine's own in a tab
	# Ctrl+C offers the focused field's selection, else what a screen asked to offer.
	var selected := selected_text(get_viewport().gui_get_focus_owner())
	var wanted := selected if selected != "" else _offered
	if wanted != _last_sent and eval_js.is_valid():
		_last_sent = wanted
		eval_js.call("window.deadnightClipboard.offer = %s" % JSON.stringify(wanted))


## Text the page heard from a paste, queued for the next frame (the page calls this inside its
## event, and the screen is edited between frames).
func heard(text: String) -> void:
	_heard.append(text)


## The page's callback form of `heard` (a callback gets its arguments as an array).
func heard_by_page(args: Array) -> void:
	if not args.is_empty():
		heard(str(args[0]))


## Puts pasted text into the focused field at the caret, over its selection: one line (a code is
## not a paragraph) and no longer than the field allows. False when nothing focused takes text.
func paste(text: String) -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		var field := focus as LineEdit
		if not field.editable:
			return false
		var line := one_line(text)
		if field.has_selection():
			var from := field.get_selection_from_column()
			field.delete_text(from, field.get_selection_to_column())
			field.deselect()
			field.caret_column = from
		if field.max_length > 0:
			line = line.substr(0, maxi(field.max_length - field.text.length(), 0))
		if line != "":
			field.insert_text_at_caret(line)
			field.text_changed.emit(field.text)  # a field that reacts to typing reacts to this too
		return true
	if focus is TextEdit:
		var area := focus as TextEdit
		if not area.editable:
			return false
		area.insert_text_at_caret(text.replace("\r\n", "\n").replace("\r", "\n"))
		return true
	return false


## Asks that Ctrl+C copy this (a code a screen shows selected), until something else is offered.
func offer(text: String) -> void:
	_offered = text


## Copies from a user gesture: true when the browser took it. The page tries the gesture first,
## then the API, and answers in `write` ("pending", "ok" or the error's name).
func copy(text: String) -> bool:
	eval_js.call("window.deadnightClipboard.copy(%s)" % JSON.stringify(text))
	var waited := 0.0
	while waited < copy_wait:
		var state := str(eval_js.call("window.deadnightClipboard.write"))
		if state == "ok":
			return true
		if state != "pending":
			return false
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	return false


## Copies `text` to the clipboard the way the platform allows: through the page's gesture layer in
## a frame, the engine's own call anywhere else. True when it is on the clipboard.
static func copy_text(text: String) -> bool:
	if current == null or not current.in_frame:
		DisplayServer.clipboard_set(text)
		return true
	return await current.copy(text)


## Whether a window can copy by itself here: not in a frame, else asks the page.
static func in_a_frame() -> bool:
	return current != null and current.in_frame


## What a field has selected ("" for none, or for something that is not a field).
static func selected_text(focus: Control) -> String:
	if focus is LineEdit:
		return (focus as LineEdit).get_selected_text()
	if focus is TextEdit:
		return (focus as TextEdit).get_selected_text()
	return ""


## Pasted text as one line: line breaks and the spaces around it dropped, as a code needs.
static func one_line(text: String) -> String:
	return text.replace("\r", "").replace("\n", "").replace("\t", "").strip_edges()


## The page's report (empty off the web, or before the layer started).
static func read() -> Dictionary:
	if current == null or not current.pastes_here:
		return {}
	var parsed: Variant = JSON.parse_string(
		str(current.eval_js.call("window.deadnightClipboard.report()"))
	)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The sentence for a report; empty outside a frame.
static func note(report: Dictionary) -> String:
	if report.is_empty() or not report.get("iframe", false):
		return ""
	var write := str(report.get("write", "untried"))
	if write not in ["untried", "pending", "ok"]:
		return COPY_FAILED % write
	if report.get("policy_read") == false or report.get("policy_write") == false:
		return BLOCKED
	return ALLOWED


## What the page saw, as one short line to send along with a problem.
static func detail(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	return (
		(
			"clipboard api read %s, write %s, button copy %s, "
			+ "Ctrl+V %d seen %d pasted, Ctrl+C %d seen %d copied"
		)
		% [
			_yes_no(report.get("policy_read")),
			_yes_no(report.get("policy_write")),
			str(report.get("write", "untried")),
			int(report.get("ctrl_v", 0)),
			int(report.get("pastes", 0)),
			int(report.get("ctrl_c", 0)),
			int(report.get("copies", 0)),
		]
	)


static func _yes_no(value: Variant) -> String:
	return "?" if value == null else ("yes" if value else "no")
