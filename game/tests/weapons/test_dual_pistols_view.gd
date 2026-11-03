extends GdUnitTestSuite
## What the view draws of the dual pistols' shots (#789): the server's `shot_fired` names the hand,
## and the flash goes on that gun's muzzle (the right gun's or the mirrored left one's), the
## kick on that gun, for the player's own body and for another player's.

const TEST_ROOM := "res://world/test_room.tscn"
const SHOOTER := WeaponsFixture.SHOOTER
const BODY := Vector3(0, 1.1, 0)
const WEAPON := &"dual_pistols"

var _player: Player
var _animation: PlayerAnimation
var _camera: Camera3D
var _view: NightView
var _server: CombatServer


func before_test() -> void:
	var runner := scene_runner(TEST_ROOM)
	_player = runner.find_child("Player") as Player
	_player.capture_mouse = false
	_animation = _player.get_node("AnimationTree") as PlayerAnimation
	_animation.equip(WEAPON)
	_camera = auto_free(Camera3D.new())
	add_child(_camera)
	_camera.position = Vector3(0.0, 1.5, 6.0)
	_camera.make_current()
	var state := ClientState.new()
	state.player_id = 1
	_view = auto_free(NightView.new())
	add_child(_view)
	_view.setup(state, _camera)
	_view.bodies = func(_id: int) -> Player: return _player
	_server = WeaponsFixture.make_server()
	_server.apply(CombatAction.give_weapon(1, WEAPON))
	_server.apply(CombatAction.equip(1, WEAPON))
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 2)


## The server's next shot of the pair, as the events say.
func _shot(seq: int) -> Dictionary:
	var events := _server.apply(WeaponsFixture.fire_at(1, seq, SHOOTER, BODY, _server.now))
	var shot := WeaponsFixture.of(events, &"shot_fired")[0]
	WeaponsFixture.step(_server, {1: Vector3.ZERO}, 12)
	return shot


func _flash(hand: int) -> MuzzleFlash:
	return _animation.muzzle_point(hand).get_node(NodePath(MuzzleFlash.NODE_NAME)) as MuzzleFlash


func test_each_gun_has_its_own_muzzle_point() -> void:
	var right := _animation.muzzle_point(0)
	var left := _animation.muzzle_point(1)
	assert_object(right).is_not_null()
	assert_object(left).is_not_null()
	assert_bool(right == left).is_false()
	assert_bool(_animation.weapon().is_ancestor_of(right)).is_true()
	assert_bool(_animation.offhand_weapon().is_ancestor_of(left)).is_true()


func test_the_muzzles_alternate_shot_by_shot() -> void:
	# Two shots on a body not stepped between them: the right gun flashes first, then the left.
	var first := _shot(1)
	assert_int(first["hand"]).is_equal(0)
	_view._on_event(first)
	assert_bool(_flash(0).is_up()).is_true()
	(
		assert_object(_animation.muzzle_point(1).get_node_or_null(NodePath(MuzzleFlash.NODE_NAME)))
		. is_null()
	)
	var second := _shot(2)
	assert_int(second["hand"]).is_equal(1)
	_view._on_event(second)
	assert_bool(_flash(1).is_up()).is_true()


func test_the_flash_sits_on_the_gun_that_fired_and_points_down_its_barrel() -> void:
	for hand in [0, 1]:
		var muzzle := _animation.muzzle_point(hand)
		var gun := _animation.weapon() if hand == 0 else _animation.offhand_weapon()
		var barrel := (gun.global_basis * Vector3.LEFT).normalized()
		# The muzzle node's -Z is the barrel on the mirrored gun too.
		assert_float(rad_to_deg((-muzzle.global_basis.z).angle_to(barrel))).is_less(1.0)
		# And it sits at the model's muzzle point.
		var at := gun.to_global(_animation.weapon_hold().muzzle)
		assert_float(muzzle.global_position.distance_to(at)).is_less(0.02)


func test_the_shot_kicks_only_the_gun_that_fired() -> void:
	var hands := _animation.hands()
	_view._on_event(_shot(1))
	for i in 2:
		_animation._process(1.0 / 60.0)
	assert_float(hands.recoil).is_greater(0.3)
	assert_float(hands.recoil_left).is_equal(0.0)
	for i in 30:
		_animation._process(1.0 / 60.0)
	_view._on_event(_shot(2))
	for i in 2:
		_animation._process(1.0 / 60.0)
	assert_float(hands.recoil_left).is_greater(0.3)
	assert_float(hands.recoil).is_less(0.1)


func test_another_players_pair_flashes_on_the_gun_that_fired() -> void:
	var other := (load("res://gameplay/player/player.tscn") as PackedScene).instantiate() as Player
	other.capture_mouse = false
	add_child(other)
	auto_free(other)
	other.position = Vector3(3.0, 0.0, 0.0)
	var other_animation := other.get_node("AnimationTree") as PlayerAnimation
	other_animation.equip(WEAPON)
	_view.bodies = func(id: int) -> Player: return other if id == 2 else _player
	var first := _shot(1)
	first["shooter_id"] = 2
	_view._on_event(first)
	var second := _shot(2)
	second["shooter_id"] = 2
	_view._on_event(second)
	for hand in [0, 1]:
		var flash := (
			other_animation.muzzle_point(hand).get_node(NodePath(MuzzleFlash.NODE_NAME))
			as MuzzleFlash
		)
		assert_bool(flash.is_up()).override_failure_message("hand %d" % hand).is_true()
	assert_float(_player.camera_rig.shake.trauma).is_equal(0.0)
