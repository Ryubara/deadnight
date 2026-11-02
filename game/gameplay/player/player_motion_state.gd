class_name PlayerMotionState
extends RefCounted
## Everything the simulation needs to carry from one tick to the next, and nothing else.
##
## This is what a server sends to correct a client, and what a client rewinds to before replaying
## its unacknowledged commands. The camera, animation and audio read it; they never change it.

## `fire_age` before the trigger was ever held: far past any hold.
const NEVER_FIRED := 1.0e6

var position := Vector3.ZERO
var velocity := Vector3.ZERO
## Which way the body faces, radians around Y (0 faces -Z).
var facing := 0.0
var on_floor := false
var sprinting := false
var aiming := false
var crouching := false
## Seconds since the trigger was last held without the aim button (a shot fired while aiming does
## not count: the aim has its own release, and leaves no hip-fire hold behind). The body keeps
## facing the view while this is short (`holds_aim`). A huge number until the first shot from the
## hip. It never zooms or moves the camera (#464).
var fire_age := NEVER_FIRED
## Whether the trigger was held in the last tick (a press is the tick it was not).
var trigger_down := false
## Seconds left of a press made before the body faced the view (`hip_fire_buffer`): the shot it
## asked for leaves the moment the body is there. Zero when nothing waits.
var shot_buffer := 0.0
## The same for the quick melee button: a press made before the body faced the view waits here
## (`hip_fire_buffer`) and the blow leaves the moment it does.
var melee_buffer := 0.0
## +1 camera over the right shoulder, -1 over the left.
var shoulder_side := 1.0
var view_yaw := 0.0
var view_pitch := 0.0
var coyote := 0.0
var jump_buffer := 0.0
var step_travelled := 0.0
## Metres still to walk after a step up during which a missing floor is forgiven.
var step_settle := 0.0

# What happened during the last simulated tick; reset every tick.
## The shot the trigger asks for may leave this tick: the trigger is held (or a press is buffered)
## and the body faces the view within `hip_fire_align_degrees`, or the aim button is down. The
## server shoots on this, never on the trigger alone (#477).
var shot_ready := false
## The quick melee the button asks for may leave this tick (a press, buffered until the body faces
## the view within `hip_fire_align_degrees`). The server swings on this (#411).
var melee_ready := false
## How far the body is from facing the view after this tick's turn, radians, 0 to pi.
var view_error := 0.0
var jumped := false
var landed := false
var landed_speed := 0.0
## Metres the body was lifted onto a ledge this tick (0 when it was not).
var stepped_up := 0.0
var footstep := false


## True while the body holds the aim pose: the aim button is down, or the trigger was held within
## `hold` seconds. The body's turn and strafing, the legs' aim gait and the weapon's pose read this
## answer; the camera does not (the view zooms for the aim button only, #464).
func holds_aim(hold: float) -> bool:
	return aiming or fire_age < hold


func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func copy_from(other: PlayerMotionState) -> void:
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			set(property.name, other.get(property.name))


func duplicate_state() -> PlayerMotionState:
	var copy := PlayerMotionState.new()
	copy.copy_from(self)
	return copy
