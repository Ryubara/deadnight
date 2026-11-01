class_name UISpring
extends RefCounted
## A damped spring on one float: hover lift, press squash and focus glow ride on these.
##
## Fixed internal timestep, so the result does not depend on the frame rate (and captures repeat).

const STEP := 1.0 / 240.0
const REST_DISTANCE := 0.0005
const REST_SPEED := 0.005

var value := 0.0
var target := 0.0
var velocity := 0.0
var stiffness := 360.0
var damping := 24.0

var _carry := 0.0


func _init(spring_stiffness: float = 360.0, spring_damping: float = 24.0) -> void:
	stiffness = spring_stiffness
	damping = spring_damping


func step(delta: float) -> void:
	_carry += minf(delta, 0.1)
	while _carry >= STEP:
		_carry -= STEP
		velocity += (stiffness * (target - value) - damping * velocity) * STEP
		value += velocity * STEP
	if is_settled():
		snap(target)


func snap(to: float) -> void:
	value = to
	target = to
	velocity = 0.0


func is_settled() -> bool:
	return absf(target - value) < REST_DISTANCE and absf(velocity) < REST_SPEED
