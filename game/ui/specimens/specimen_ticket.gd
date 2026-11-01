class_name SpecimenTicket
extends Control
## A ticket stub: a cream card with a notch on each side and a perforated tear line. The text
## on top is laid out by the specimen; this draws only the paper.

const PAPER := Color("e9d9b0")
const INK := Color("2a1d12")
const NOTCH_RADIUS := 14.0
const STUB_FRACTION := 0.72

var _tokens := UITokens.active()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PAPER)
	draw_rect(r.grow(-8.0), INK, false, 2.0)
	var tear_x := r.size.x * STUB_FRACTION
	var y := 10.0
	while y < r.size.y - 10.0:
		draw_line(Vector2(tear_x, y), Vector2(tear_x, y + 7.0), INK, 2.0)
		y += 14.0
	# Notches are cut from the page colour.
	draw_circle(Vector2(tear_x, 0.0), NOTCH_RADIUS, _tokens.bg)
	draw_circle(Vector2(tear_x, r.size.y), NOTCH_RADIUS, _tokens.bg)
