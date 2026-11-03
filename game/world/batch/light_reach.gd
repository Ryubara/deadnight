class_name LightReach
extends RefCounted
## Which lights can touch a box (#728). The Compatibility renderer lights a mesh with at most
## `max_lights_per_object` omni and spot lights, chosen by the box of the mesh, so a mesh the lights
## of a
## whole street reach drops some of them. The lot keeps every mesh under that cap, with room for a
## muzzle
## flash and a blast (`docs/research/night-environment.md`), and a batch must not undo it by making
## a mesh
## of many.

const DEFAULT_LIMIT := 8
const LIMIT_SETTING := "rendering/limits/opengl/max_lights_per_object"


## The project's cap of lights per mesh (the renderer's own default when the project sets none).
static func limit() -> int:
	return int(ProjectSettings.get_setting(LIMIT_SETTING, DEFAULT_LIMIT))


## Whether `light` can touch `box`: an omni's sphere, a spot's cone (by its box).
static func reaches(light: Light3D, box: AABB) -> bool:
	if light is OmniLight3D:
		var at := light.global_position
		var nearest := at.clamp(box.position, box.end)
		return at.distance_to(nearest) <= (light as OmniLight3D).omni_range
	var spot := light as SpotLight3D
	if spot == null:
		return false
	var forward := -spot.global_basis.z
	var centre := light.global_position + forward * spot.spot_range
	var radius := spot.spot_range * tan(deg_to_rad(spot.spot_angle))
	var extent := Vector3(
		radius * sqrt(1.0 - forward.x * forward.x),
		radius * sqrt(1.0 - forward.y * forward.y),
		radius * sqrt(1.0 - forward.z * forward.z)
	)
	var cone := AABB(light.global_position, Vector3.ZERO).merge(AABB(centre - extent, extent * 2.0))
	return cone.intersects(box)


## How many of `lights` reach `box`.
static func count(lights: Array[Light3D], box: AABB) -> int:
	var total := 0
	for light in lights:
		if reaches(light, box):
			total += 1
	return total
