class_name WebKeyboard
extends Node
## The phone's own keyboard on the web (Deadnight #1183).
##
## A LineEdit opens a phone's keyboard through the engine's hidden `<input>`, which exists only when
## the page's export has `html/experimental_virtual_keyboard` on: it was off, so no text field of
## the game could open a keyboard on a phone, in a browser or in a Discord Activity. This layer is
## what the option alone does not do:
##
## - A browser raises the keyboard only for a focus that a tap gave. The engine focuses its input
##   from the very first touch event (`touchstart`), which iOS does not take as a tap; the focus is
##   held until the finger lifts (`touchend`, `pointerup`) and made there. Where the browser would
##   have taken the first, nothing is lost: the keyboard rises a moment later, with the finger.
## - The input must not be smaller than 16 px of type, or iOS zooms the page in and leaves it
##   zoomed.
## - When the keyboard closes the canvas gets the focus back (the engine's own keys need it) and the
##   page goes back to its top: a browser may have scrolled it to show the input.
## - `covered` says how much of the page the keyboard hides (the visual viewport against the layout
##   viewport), which `KeyboardLift` uses to keep the field in view.
##
## Off the web nothing is installed and `covered_units` is 0.

## The page side. Runs once. The engine's input and textarea are the ones with `z-index: -1` that
## sit beside the canvas (`GodotDisplayVK.init`).
const PAGE_SCRIPT := """
(function () {
  if (window.deadnightKeyboard) { return; }
  var canvas = document.getElementById('canvas');
  if (!canvas) { return; }
  var k = window.deadnightKeyboard = {deferred: 0, opened: 0, closed: 0};
  var style = document.createElement('style');
  style.textContent = 'input,textarea{font-size:16px !important}';
  document.head.appendChild(style);
  function engineInput(el) {
    return !!el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')
      && el.parentNode === canvas.parentNode && el.style.zIndex === '-1';
  }
  var real = HTMLElement.prototype.focus;
  var pending = null;
  function firstTouch(e) {
    return !!e && e.isTrusted && (e.type === 'touchstart'
      || (e.type === 'pointerdown' && e.pointerType === 'touch'));
  }
  HTMLElement.prototype.focus = function (options) {
    if (engineInput(this) && firstTouch(window.event)) { pending = this; k.deferred++; return; }
    return real.call(this, options);
  };
  function lifted() {
    var el = pending; pending = null;
    if (!el || el.style.display === 'none' || el.disabled) { return; }
    k.opened++;
    real.call(el);
  }
  ['touchend', 'pointerup', 'mouseup', 'click'].forEach(function (name) {
    addEventListener(name, lifted, true);
  });
  addEventListener('touchcancel', function () { pending = null; }, true);
  addEventListener('focusout', function (e) {
    if (!engineInput(e.target)) { return; }
    setTimeout(function () {
      var a = document.activeElement;
      if (a && a !== document.body && a !== document.documentElement) { return; }
      k.closed++;
      canvas.focus();
      window.scrollTo(0, 0);
    }, 0);
  }, true);
  k.covered = function () {
    var v = window.visualViewport;
    return v ? Math.max(0, Math.round(window.innerHeight - (v.height + v.offsetTop))) : 0;
  };
  k.height = function () { return canvas.getBoundingClientRect().height; };
})();
"""

## The running layer, for a screen to reach; null where there is none (tests, a headless run).
static var current: WebKeyboard

## (String) -> Variant: runs a line of script in the page. The browser's by default; a test stands
## in.
var eval_js := Callable()
## The layer is installed (on the web).
var installed := false


func _ready() -> void:
	current = self
	if OS.has_feature("web") and not eval_js.is_valid():
		eval_js = func(js: String) -> Variant: return JavaScriptBridge.eval(js, true)
		eval_js.call(PAGE_SCRIPT)
		installed = true
	set_process(false)


func _exit_tree() -> void:
	if current == self:
		current = null


## How much of `view`'s height the system keyboard hides, in the view's own units (0 with no
## keyboard, and off the web). The page measures in CSS pixels: they are scaled by the canvas'
## height.
func covered_units(view: Viewport) -> float:
	if not installed:
		return 0.0
	var covered := float(eval_js.call("window.deadnightKeyboard.covered()"))
	if covered <= 0.0:
		return 0.0
	var page_height := float(eval_js.call("window.deadnightKeyboard.height()"))
	if page_height <= 0.0:
		return 0.0
	return covered * view.get_visible_rect().size.y / page_height


## What the page layer did, for a browser test: taps held for the finger's lift, keyboards raised
## there, keyboards closed (empty off the web).
func report() -> Dictionary:
	if not installed:
		return {}
	var parsed: Variant = JSON.parse_string(
		str(eval_js.call("JSON.stringify(window.deadnightKeyboard)"))
	)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
