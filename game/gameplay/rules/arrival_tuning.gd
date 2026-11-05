class_name ArrivalTuning
extends Resource
## How a player arrives in a night: by helicopter, on a rope, on their own screen (#1057). One table
## for both halves. The rules' half is the shield (below): while a player's client shows the drop,
## nothing in the night may touch them. The client's half is the show (`ArrivalPlan`,
## `ArrivalCutscene`): how long it runs, whether it can be skipped, and who sees it again. Designers
## edit these in `default_tuning.tres` (docs/design/arrival.md); no code holds the numbers.

## Whether a returning player sees the drop each time they join.
enum Repeat {
	## Every join: the start of a night, and every late join.
	ALWAYS,
	## Once for each time the game is opened; the next joins of that session go straight in.
	FIRST_PER_SESSION,
}

@export_group("Shield (the server's)")
## The most seconds the drop shields a player, if their client never says it landed (a client that
## stalled, closed or lied). The show is shorter than this by a margin for a slow web build.
@export_range(2.0, 60.0, 0.5, "suffix:s") var cap_seconds: float = 12.0
## Seconds after the landing in which a blow still does nothing: the controls are theirs, the dead
## are not yet at them.
@export_range(0.0, 10.0, 0.1, "suffix:s") var grace_seconds: float = 1.5

@export_group("Show (the client's)")
## Whether the player's own screen shows the drop at all. Off, nobody is dropped (no shield either).
@export var enabled: bool = true
## The length of the drop that opens a night: the helicopter comes in, hovers, lowers the rope.
@export_range(1.0, 30.0, 0.1, "suffix:s") var night_seconds: float = 6.5
## The length of the drop for a player who joins a night already going: no fly-in, a late joiner in
## a fight should not wait.
@export_range(1.0, 30.0, 0.1, "suffix:s") var late_seconds: float = 3.8
## Whether a press skips the drop (a key, a pad button, a click or a tap), after `skip_after`.
@export var skippable: bool = true
## Seconds into the drop before a press skips it, so the press that joined the night, or one made
## while looking away, does not skip a drop nobody saw.
@export_range(0.0, 10.0, 0.1, "suffix:s") var skip_after: float = 1.0
## Whether the drop plays for every join or once a session.
@export var repeat: Repeat = Repeat.ALWAYS
## Seconds the screen takes to fade in from black at the start, and out to black at the end.
@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_in_seconds: float = 0.6
@export_range(0.05, 3.0, 0.05, "suffix:s") var fade_out_seconds: float = 0.7
## Metres above the ground the helicopter hovers, and the camera above the landing spot.
@export_range(5.0, 40.0, 0.5, "suffix:m") var hover_height: float = 14.0
@export_range(5.0, 60.0, 0.5, "suffix:m") var camera_height: float = 26.0
## Metres the camera stands back from the landing spot, along the line it looks from.
@export_range(2.0, 60.0, 0.5, "suffix:m") var camera_back: float = 24.0
## The camera's field of view, degrees.
@export_range(20.0, 90.0, 1.0, "suffix:deg") var camera_fov: float = 50.0
## Metres the helicopter flies in from, before it hovers (the start of a night only).
@export_range(0.0, 200.0, 1.0, "suffix:m") var approach_distance: float = 70.0
## Share of the show the fly-in takes, and the share spent hovering with the rope still coming down
## before the Soldier lets go; the rest is the descent. (A late join has no fly-in.)
@export_range(0.0, 0.6, 0.01) var approach_share: float = 0.38
## The helicopter's lamp: a cone of this half-angle, reaching this far, with this much light.
@export_range(5.0, 60.0, 0.5, "suffix:deg") var lamp_angle: float = 24.0
@export_range(5.0, 60.0, 0.5, "suffix:m") var lamp_range: float = 26.0
@export_range(0.0, 16.0, 0.1) var lamp_energy: float = 6.0
## The rotor's turn, rotations a second.
@export_range(0.0, 20.0, 0.1, "suffix:rps") var rotor_rps: float = 5.5


## The seconds of the drop for a player who joins when `fresh` is true (the night's first break).
func seconds_for(fresh: bool) -> float:
	return night_seconds if fresh else late_seconds
