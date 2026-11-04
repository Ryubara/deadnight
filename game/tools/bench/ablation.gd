class_name BenchAblation
extends RefCounted
## What a browser profile leaves out of a night to see what it costs (#689): a bench reads these
## arguments from the page's address and applies them once the night runs. Not part of the play.
##
##   `scale=N`  the 3D resolution scale in percent (the setting's own, over the player's)
##   `msaa=0`   no multisample anti-aliasing on the 3D view
##   `hide=A,B` hide the lot's areas of these names (`Field`, `Midway`, ...) from drawing
##   `lights=0` hide every light of the lot
##   `perf=1`   `PerfProbe`'s timers on: the page publishes them as `perf.<label>` (ms a frame)
##   `fog=0`    no fog
##   `cull=D`   every mesh of the lot stops drawing D metres from the camera
##   `cullsmall=D` the same, only for meshes under 2 m across
##   `ui=0`     hide the HUD and the touch layer
##   `dead=0`   hide the dead from drawing (their views still move and animate)
##   `shot=PATH` with `shot_frame=N`: save one picture of the view at frame N (`ShotTaker`)
##   `census=1` a line a second of where the dead stand and the renderer's CPU and GPU time
##   `anim=0`   stop the animation throttle: the dead keep their pose (no tree, no skeleton update)
##   `hints=0`  the touch hints ("DRAG TO MOVE") are marked used, as for a player who has played: an
##              autopilot never touches, so they would stay up and animate for the whole run (#834)
## It changes nothing the rules or the physics see.


## Applies what `args` ask for to the night on screen.
static func apply(args: NetArgs, night: Night, screen: Control) -> void:
	var viewport := screen.get_viewport()
	if args.get_int("perf") == 1:
		PerfProbe.enabled = true
	if args.has("scale"):
		viewport.scaling_3d_scale = args.get_float("scale") / 100.0
	if args.has("msaa"):
		viewport.msaa_3d = Viewport.MSAA_DISABLED if args.get_int("msaa") == 0 else Viewport.MSAA_2X
	var world: Node = night.world.greybox if night.world != null else null
	if world != null:
		for area_name in args.get_string("hide").split(",", false):
			var area := world.get_node_or_null(area_name) as Node3D
			if area != null:
				area.visible = false
		if args.has("lights") and args.get_int("lights") == 0:
			for light in world.find_children("*", "Light3D", true, false):
				(light as Light3D).visible = false
		if args.has("cull") or args.has("cullsmall"):
			var far := args.get_float("cull", args.get_float("cullsmall"))
			var small_only := args.has("cullsmall")
			for node in world.find_children("*", "MeshInstance3D", true, false):
				var mesh_node := node as MeshInstance3D
				if mesh_node.mesh == null:
					continue
				var across := (
					mesh_node.mesh.get_aabb().size * mesh_node.global_transform.basis.get_scale()
				)
				if small_only and maxf(across.x, maxf(across.y, across.z)) >= 2.0:
					continue
				mesh_node.visibility_range_end = far
		if args.has("fog") and args.get_int("fog") == 0:
			var env := world.find_children("*", "WorldEnvironment", true, false)
			for node in env:
				var e := (node as WorldEnvironment).environment
				if e != null:
					e.fog_enabled = false
	if args.has("shot"):
		var taker := ShotTaker.new()
		taker.path = args.get_string("shot")
		for frame in args.get_string("shot_frame", "600").split(",", false):
			taker.frames.append(int(frame))
		screen.add_child(taker)
	var horde: ZombieHorde = night.view.horde if night.view != null else null
	if horde != null:
		if args.has("dead") and args.get_int("dead") == 0:
			horde.visible = false
		if args.has("anim") and args.get_int("anim") == 0:
			horde.throttle.set_process(false)
	if horde != null and args.get_int("census") == 1:
		var census := CrowdCensus.new()
		census.horde = horde
		census.camera = viewport.get_camera_3d()
		screen.add_child(census)
	if args.has("ui") and args.get_int("ui") == 0:
		for child in screen.get_children():
			if child is Hud or child is TouchControls:
				(child as CanvasItem).visible = false
	if args.has("hints") and args.get_int("hints") == 0:
		for node in screen.get_tree().root.find_children("*", "TouchHints", true, false):
			for id in TouchHints.ORDER:
				(node as TouchHints).mark_used(id)
