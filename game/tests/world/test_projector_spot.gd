# The booth's projector spot lights the screen and nothing behind the booth's wall (issue #840).
# It was written with a yaw of 180, which turns a spot's -Z forward to +Z: it faced the road, and
# the Compatibility renderer casts no shadow, so it lit the booth's south door and the plaza
# through the booth's wall (0.9 energy). The beam it stands for runs from the port in the north
# wall to the screen, 70 m away. Aimed there, a cone aimed at the middle of the screen dipped below
# the stand's roof and put a seventh light on the stand's meshes (the cap is six and two for a
# fight, test_lot_light_cap.gd): its lower edge now runs level.
extends GdUnitTestSuite

const LOT := "res://world/drive_in_greybox.tscn"
const SPOT := "ProjectionBooth/Lamps/ProjectorBeam"
const BEAM := "ProjectionBooth/BeamFx"
const PANEL := "Field/ScreenPanel"
## Points round the cone's rim, and the steps along it, for the wall test.
const RIM_POINTS := 24
const STEPS := 40
## A wall box is shrunk by this on every side, so a surface a cone meets on a wall's own face does
## not count as inside it.
const SKIN := 0.03

var _lot: Node3D
var _spot: SpotLight3D
var _wall_boxes: Array[CSGBox3D] = []


func before_test() -> void:
	_lot = (load(LOT) as PackedScene).instantiate() as Node3D
	add_child(_lot)
	auto_free(_lot)
	_spot = _lot.get_node(SPOT) as SpotLight3D
	_wall_boxes.clear()
	for prefix in ["Wall", "Roof"]:
		for node in _lot.find_children(prefix + "*", "CSGBox3D", true, false):
			_wall_boxes.append(node as CSGBox3D)


func _axis() -> Vector3:
	return -_spot.global_basis.z.normalized()


## The point on the screen's face (the plane of its front) that the spot's axis meets.
func _axis_on_the_screen() -> Vector3:
	var panel := _lot.get_node(PANEL) as CSGBox3D
	var face_z := panel.global_position.z + panel.size.z * 0.5
	var axis := _axis()
	var t := (face_z - _spot.global_position.z) / axis.z
	return _spot.global_position + axis * t


## A point of the cone's rim `along` metres down its axis, `turn` of a full circle round it.
func _rim(along: float, turn: float) -> Vector3:
	var axis := _axis()
	var side := axis.cross(Vector3.UP).normalized()
	var up := side.cross(axis).normalized()
	var radius := along * tan(deg_to_rad(_spot.spot_angle))
	var around := side * cos(TAU * turn) + up * sin(TAU * turn)
	return _spot.global_position + axis * along + around * radius


func _inside_a_wall(point: Vector3) -> bool:
	for wall in _wall_boxes:
		var local := wall.global_transform.affine_inverse() * point
		var half := wall.size * 0.5 - Vector3.ONE * SKIN
		if absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z:
			return true
	return false


func _crosses_a_wall(from: Vector3, to: Vector3) -> bool:
	for wall in _wall_boxes:
		var inverse := wall.global_transform.affine_inverse()
		var half := wall.size * 0.5 - Vector3.ONE * SKIN
		if AABB(-half, half * 2.0).intersects_segment(inverse * from, inverse * to):
			return true
	return false


func test_the_spot_faces_the_screen_not_the_road() -> void:
	var panel := _lot.get_node(PANEL) as CSGBox3D
	var axis := _axis()
	# North is -Z: the screen is at the far end of the field, the road is behind the booth.
	assert_float(axis.z).is_less(-0.99)
	var hit := _axis_on_the_screen()
	var half := panel.size * 0.5
	assert_float(absf(hit.x - panel.global_position.x)).is_less(half.x)
	assert_float(absf(hit.y - panel.global_position.y)).is_less(half.y)


func test_the_middle_of_the_screen_is_inside_the_cone() -> void:
	# The haze (`BeamFx`, a mesh) runs from the lens to the middle of the screen: the light that goes
	# with it covers the same point.
	var beam := _lot.get_node(BEAM) as ProjectorBeam
	var middle := beam.global_position + beam.target_centre
	var off_axis := rad_to_deg(_axis().angle_to(middle - _spot.global_position))
	assert_float(off_axis).is_less(_spot.spot_angle)


func test_the_lower_edge_of_the_cone_runs_level_at_the_height_of_the_spot() -> void:
	# A mesh is lit by the box of the cone, not its shape (`LightCap.reaches`): a cone that dips below
	# the port's height lights the stand's roof and walls and the cars, a seventh light on meshes the
	# phone's cap leaves six for.
	var pitch := rad_to_deg(asin(_axis().y))
	assert_float(pitch).is_greater_equal(_spot.spot_angle - 0.05)


func test_the_cone_is_the_seven_degrees_the_beam_is_meant_to_have() -> void:
	assert_float(_spot.spot_angle).is_equal_approx(7.0, 0.01)
	assert_float(_spot.spot_range).is_greater(
		_spot.global_position.distance_to(_axis_on_the_screen())
	)


func test_the_spot_stands_inside_the_booth() -> void:
	var booth := _lot.get_node("ProjectionBooth/WallN0") as CSGBox3D
	# The north wall is the one with the port; the spot stands on the booth's side of it (south).
	assert_float(_spot.global_position.z).is_greater(booth.global_position.z + booth.size.z * 0.5)
	assert_float(_spot.global_position.z).is_less(32.0)


func test_the_cone_meets_no_wall_or_roof_of_the_lot() -> void:
	# The Compatibility renderer casts no shadow, so a wall or a roof that the cone's rim crosses is
	# lit through. The rim of the cone, from its apex to the screen's face, is sampled round and
	# along, and the segment from the apex to each point must cross no wall or roof of the lot (it
	# leaves the booth through the port in the north wall, which is a gap between the wall boxes).
	var reach := _spot.global_position.distance_to(_axis_on_the_screen())
	var crossed: Array[String] = []
	for step in range(1, STEPS + 1):
		var along := reach * float(step) / STEPS
		for turn in RIM_POINTS:
			var rim := _rim(along, float(turn) / RIM_POINTS)
			if _crosses_a_wall(_spot.global_position, rim) or _inside_a_wall(rim):
				crossed.append("%.1f m, %d/%d" % [along, turn, RIM_POINTS])
	(
		assert_array(crossed)
		. override_failure_message("the cone meets a wall or roof of the lot at %s" % [crossed])
		. is_empty()
	)
