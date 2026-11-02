# Shot feedback: flash, impacts and shake, cheaply

How shooters make a shot feel like something for almost no frame time, and what Deadnight took from it. The numbers and
files are in [Shot feedback](../design/shot-feedback.md) and [Camera shake](../design/camera-shake.md).

## What the genre does

- **A muzzle flash is a sprite, not a light.** A few additive quads with a star or cone shape, rotated and scaled at
  random each shot, up for one to three frames. The eye reads the first frame as the shot and the random shape as
  fire; a fixed picture reads as a sticker after a minute of shooting. A real light on top is optional and brief.
- **Hit feedback is small and different for what was hit.** Dust and a spark on a wall, a dark puff or drops on flesh,
  a short life, a hard cap on how many are alive (the pool). What the player must read in half a second is "I hit it":
  the colour change from dust to red says it with no number.
- **Shake is felt, not seen.** The widely used form is *trauma* (Squirrel Eiserloh, GDC 2016): events add to a value in
  0 to 1 that drains steadily, and the shake is trauma squared (or cubed) times smooth noise, applied as a small
  rotation. Squaring makes the small things quiet and stacked things loud. Rotation, not translation, because a shifted
  camera slides across geometry and breaks the shoulder camera's wall sweep. Vlambeer's talk (Jan Willem Nijman, *The
  Art of Screenshake*) is the case for adding it; its other lesson is to make it adjustable, which is why it is a
  tuning resource and a setting here.
- **The shake is the view, never the aim.** Games that shake the aim make a shotgun blast miss; the crosshair ray is
  taken from the unshaken view, or the shake is small enough not to matter. We take it from the unshaken view.

- **A run is shown by the camera too, but only just.** First-person and shoulder shooters bob or sway the view with the
  footfalls while sprinting; the comfort advice is the same as for shake: rotation not translation, small, tied to
  the stride (a faster run, a faster bob), eased in and out, and switchable (reduced motion). We did the sway on the
  same lens turn as the shot shake, so one setting quiets both ([Camera shake](../design/camera-shake.md)).

## What we did and why

| Choice | Why |
| --- | --- |
| Flash as 3 quads, one shader, procedural (no texture) | The toon style is flat colour and hard edges: a shader draws them at any size with no texture to import or to pack into the web build; one transparent additive quad costs almost nothing on WebGL2 |
| Counted in rendered frames | A "1 to 3 frames" flash must be the same at 30, 60 and 144 fps and in a 10 fps capture; seconds are not |
| One flash light at a time, in a group | The Compatibility renderer lights a mesh with at most 8 lights; each extra light a flash adds could drop a lamp, so the number of flash lights on the map is 1 whatever the number of players (the kit's Compatibility lighting page) |
| Impacts pooled to 24 slots | A shotgun is eight pellets and an SMG ten shots a second: unbounded spawning is the usual way an effect becomes the frame-time problem. Reuse, and recycle the oldest |
| Mark without a Decal | The brief asks for a decal-less mark: a dark camera-facing dot that fades, 0.045 m, needs no surface normal (the event carries only points) and no decal support |
| `flesh` points in the event | The client cannot tell a zombie from a wall at a pellet's end without asking the world; the server already knows, so it says it (one `Vector3` per hit) |
| Sprint sway: a phase in footfalls, not seconds | The bob must follow the feet. Ground speed over `step_distance` (the metres to a footstep event, half the Run clip's cycle at its planted speed) is the footfall rate, so two speeds give two rates and a stopped body holds still; no clock is read, so tests and captures agree |
| Sway and shake are one lens turn, the sway ducking under trauma | Two separate effects on one lens fight when both are up; multiplying the turns and giving the sway up to half way at full trauma keeps a kick readable. Measured: pitch 0.30, yaw 0.15, roll 0.20 degrees at most while sprinting at 7 m/s, 4.7 footfalls a second |
| The shotgun's trauma 0.65 became 0.55 | The brief is "very subtle": at 0.65 the peak turn was 0.63 degrees, twice the sprint bob and over the half degree line; 0.55 gives 0.45 and a blast that drains in 0.21 s |
| Trauma in `WeaponDef`, shake maths in `PlayerTuning` | The amount is a property of the gun (the shotgun kicks, the SMG does not), the curve is a property of the camera; both edited in the Godot inspector |

## Things that bit

- **A flash drawn at the server's muzzle can be inside the player's own body.** The server's muzzle is an offset from
  the body (0.3 m right, 0.4 m forward), which the over-the-shoulder camera sees *behind* the helmet: the depth test hid
  the whole flash. On the weapon's own muzzle point it is in front. A weapon with no model (the pistol) flashes 0.6 m
  down the barrel instead.
- **The exit log is noisy under load, and not from the effects.** The CI night run greps for `leaked at exit` and
  `still in use`. Run next to a capture and a test suite it printed 34 resources "still in use"; every one was an
  Ogg audio stream still playing when the run quit, and the same run alone, three times, was clean. Run it alone. The
  effects keep materials per instance and share the one flash light through a node group, so nothing of theirs is
  left in a `static var`.
- **A capture's frame number is not the script's own frame count.** Movie Maker numbers files from the first rendered
  frame, including the ones spent loading; print `Engine.get_frames_drawn()` for the name of the file to keep.
- **A flash that lives two frames needs a capture at 10 fps to be seen at all:** it is up for exactly two files, so the
  capture script prints which ones.

## The web check

`tools/web_smoke/smoke.py` plays a night in headless Chromium, holding the fire button (it shoots all night), and
records frame times. Software GL on this machine; the numbers are in the pull request. The comparison is the same
script on the build before and after, same machine, same run length.

## Sources

- Squirrel Eiserloh, *Math for Game Programmers: Juicing Your Cameras With Maths*, GDC 2016
  ([GDC Vault](https://www.gdcvault.com/play/1023146/Math-for-Game-Programmers-Juicing)).
- Jan Willem Nijman (Vlambeer), *The Art of Screenshake*, 2013 ([YouTube](https://www.youtube.com/watch?v=AJdEqssNZ-U)).
- Godot docs: [Compatibility renderer feature list](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html),
  [Spatial shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/spatial_shader.html)
  (`MODELVIEW_MATRIX` billboards), `FastNoiseLite`.
- The kit's Compatibility lighting page (`docs/godot/compat-lighting.md` there): the 8 lights per mesh cap, additive
  quads instead of light range.
