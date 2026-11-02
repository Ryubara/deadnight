class_name StagePose
extends RefCounted
## Where the menu's camera stands for one tab, and how the soldier is turned. Plain data: the
## camera is placed from the focus point by an azimuth, a distance and a height, then slid sideways
## so the focus sits at `frame_x` of the picture's width (0 left edge, 1 right edge). The panels
## of a tab occupy one side of the screen; the soldier stands in the free part.

## The point the camera looks at, in the stage's metres.
var focus := Vector3(0.0, 1.0, 0.0)
## Degrees round the focus from the +Z axis (0 in front of the soldier, positive towards +X).
var azimuth := 0.0
## Metres from the focus on the ground plane, and the camera's height above the ground.
var distance := 5.0
var height := 1.2
## Vertical field of view in degrees.
var fov := 32.0
## Where the focus sits across the picture, 0 to 1.
var frame_x := 0.5
## Degrees the soldier is turned from facing +Z (positive towards +X).
var hero_yaw := 0.0


static func make(
	tab_azimuth: float,
	tab_distance: float,
	tab_height: float,
	tab_fov: float,
	tab_frame_x: float,
	tab_yaw: float,
	tab_focus := Vector3(0.0, 1.0, 0.0)
) -> StagePose:
	var pose := StagePose.new()
	pose.azimuth = tab_azimuth
	pose.distance = tab_distance
	pose.height = tab_height
	pose.fov = tab_fov
	pose.frame_x = tab_frame_x
	pose.hero_yaw = tab_yaw
	pose.focus = tab_focus
	return pose


## The pose of a tab. Play is the wide shot with the soldier left of centre and the screen over his
## shoulder; Loadout comes in close; Shop turns towards the concession counter; Challenges puts the
## soldier on the right under the ticket booth's lamp; More pulls back and up.
static func for_tab(tab: MenuTab.Id) -> StagePose:
	match tab:
		MenuTab.Id.LOADOUT:
			return make(-10.0, 4.8, 1.3, 30.0, 0.36, 8.0, Vector3(0.0, 0.95, 0.0))
		MenuTab.Id.SHOP:
			return make(32.0, 5.0, 1.35, 32.0, 0.27, 80.0, Vector3(0.0, 1.0, 0.0))
		MenuTab.Id.CHALLENGES:
			return make(-28.0, 5.2, 1.3, 32.0, 0.74, -82.0, Vector3(0.0, 1.0, 0.0))
		MenuTab.Id.MORE:
			return make(6.0, 9.5, 2.6, 34.0, 0.3, 70.0, Vector3(0.0, 1.5, 0.0))
	return make(16.0, 5.0, 1.45, 32.0, 0.3, 78.0, Vector3(0.0, 1.1, 0.0))


## The camera's place, and the point it looks at, for a picture of `aspect` (width over height).
## The shift that puts the focus at `frame_x` is worked out for at most 16:9, so a wider window
## keeps the soldier beside the same panels instead of drifting towards them.
func place(aspect: float) -> Array[Vector3]:
	var angle := deg_to_rad(azimuth)
	var offset := Vector3(sin(angle), 0.0, cos(angle)) * distance
	var from := Vector3(focus.x + offset.x, height, focus.z + offset.z)
	var forward := (focus - from).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var reach := (from - focus).length()
	var width := 2.0 * reach * tan(deg_to_rad(fov) * 0.5) * minf(aspect, 16.0 / 9.0)
	var shift := right * (0.5 - frame_x) * width
	var shifted: Array[Vector3] = [from + shift, focus + shift]
	return shifted
