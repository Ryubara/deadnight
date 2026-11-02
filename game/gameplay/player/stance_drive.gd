class_name StanceDrive
extends RefCounted
## The body machine's stance, followed from the player's state (#549): the fall when the body
## leaves the floor without rising, the crouch state while it crouches on the ground, and how much
## Walk shows under the held Duck pose. It reads only `Player.state`, so a played body and a puppet
## (a player on another machine, whose state `Player.puppet_to` sets from the frame's stance) are
## drawn by the same code. The jump and the landing come from the player's `jumped` and `landed`.

const STATE_LOCOMOTION := &"locomotion"
const STATE_FALL := &"fall"
## Crouched: the kit's Duck clip held at its lowest pose, with some of the Walk laid over it while
## the body moves (the kit has no crouch walk).
const STATE_CROUCH := &"crouch"
const CROUCH_MIX_PARAMETER := &"parameters/body/crouch/mix/blend_amount"
const CROUCH_RATE_PARAMETER := &"parameters/body/crouch/walk_rate/scale"
## Seconds of the Duck clip looped around its lowest pose to hold it.
const DUCK_HOLD := 0.1
## The slowest the Walk steps under the Duck pose, as a share of its own pace.
const CROUCH_WALK_RATE_MIN := 0.5

var _tree: AnimationTree
var _player: Player
var _tuning: PlayerTuning
var _playback: AnimationNodeStateMachinePlayback
var _was_on_floor := true


func _init(
	tree: AnimationTree,
	player: Player,
	tuning: PlayerTuning,
	playback: AnimationNodeStateMachinePlayback
) -> void:
	_tree = tree
	_player = player
	_tuning = tuning
	_playback = playback


## One frame: the fall, the crouch state, and the crouch's Walk mix for the body's ground speed.
func step() -> void:
	var on_floor := _player.state.on_floor
	if _was_on_floor and not on_floor and _player.state.velocity.y <= 0.0:
		_playback.travel(STATE_FALL)
	_was_on_floor = on_floor
	_follow_crouch(on_floor)
	var share := clampf(_player.ground_speed() / _tuning.crouch_speed, 0.0, 1.0)
	_tree.set(CROUCH_MIX_PARAMETER, share * _tuning.crouch_walk_blend)
	_tree.set(CROUCH_RATE_PARAMETER, maxf(share, CROUCH_WALK_RATE_MIN))


## Into the crouch state when the body crouches on the ground, back to the locomotion when it
## stands (a fall leaves it by its own transition, a landing returns to the locomotion).
func _follow_crouch(on_floor: bool) -> void:
	var current := _playback.get_current_node()
	if _player.state.crouching and on_floor and current == STATE_LOCOMOTION:
		_playback.travel(STATE_CROUCH)
	elif not _player.state.crouching and current == STATE_CROUCH:
		_playback.travel(STATE_LOCOMOTION)
