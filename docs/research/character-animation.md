# Character animation

What we learned authoring the Soldier's weapon clips in the pinned Blender (5.2.3) and playing them in Godot 4.7.2
(Deadnight #42). The clip spec is [Animation](../design/animation.md); the kit-wide recipe this builds on is the kit's
rig-sharing pages (Blender and Godot).

## The kit clips key few bones; the rest sit at the file's static pose

The kit Soldier's clips key 7 (`Idle`) to 19 (`Run_Gun`) of the 43 bones. Every other bone sits at its glTF node
transform: arms down, fingers curled. Blender's rest pose is different (arms out, fingers straight).

- The importer writes the node transforms into the pose bones; the first clip evaluation overwrites them. Read them
  right after the import (`soldier_clips.capture_static`), before any frame change.
- The kit recipe clears the pose bones before export, and the exporter's `export_reset_pose_bones=True` resets them
  between clips: every bone a clip leaves out is then sampled at Blender's rest. In the recipe's export, `Idle` keys
  `UpperArm.L` at exactly the rest rotation (arms out); in ours, at the static pose. Checked by reading both files'
  `Idle` channel.
- The fix: key the static pose into every clip for the bones it leaves out (`bake_static`), and pose the static pose
  before exporting with `export_reset_pose_bones=False`.
- Godot's skeleton rest stays Blender's rest (the exporter writes the joints' rest, not the pose): a Soldier with no
  clip playing stands in a T-pose. Something must always play.
- Godot's `remove_immutable_tracks` import option keeps a constant track whose value is not the rest: the baked
  `UpperArm.L` track survives in every clip (41 tracks per clip after import).

## Quaternion keys must keep one sign

`q` and `-q` are the same rotation, and the kit stores some bones with `w < 0` (`UpperArm.L` at -0.911). Blender
interpolates each quaternion component separately, so two neighbouring keys of opposite sign swing the bone through a
wild path: mid-equip, the gun went behind the Soldier's head. The exporter samples that path, so Godot plays it too.
Fix: flip each key to the sign of the one before it (`dot < 0` then negate), and flip the target before a slerp.

## The boots follow the IK foot bones

The kit legs are IK-baked: `UpperLeg` and `LowerLeg` carry rotations, and `Foot.L`/`Foot.R` (children of `Root`, not of
the shin) carry location keys, and the boots are weighted to them. A derived clip that keys only rotations (and
`Body`) leaves the feet at the static place while the shins swing: the first `Walk` stretched the boots into black
sticks. Key location on every bone a clip writes.

## Weapon holds measured in Godot

Leaving the kit Shotgun and Shovel in the hand of a measuring copy (`build_soldier.py --keep-held`) and dividing their
transform under the `Index1.R` BoneAttachment3D by the kit files' own node transform (the kit files store the mesh at
1/100 with a 100x, -90-degree node) gives the transform our weapon scenes take: [Animation](../design/animation.md#weapons-in-the-hand).
The offset is 0.2 m from the bone in metres, the "about 2 mm" the weapons page measured in the kit file's units.

## Bone axes on the kit rig

Measured with a probe sheet (40-degree offsets on each axis), TEMPERANCE import, local rotations on the pose:

| Bones | X | Y | Z |
| --- | --- | --- | --- |
| Abdomen, Torso, Neck | pitch, positive bends forward | yaw, positive turns the chest to his right | roll |
| UpperArm.R | raises the arm toward the head | twists and lifts it forward | swings it forward and out |
| LowerArm.R | small | twists | tips the hand: muzzle up |

Large yaw on the spine leans the body sideways as well (the spine bones are already pitched in the static pose): the
first horizontal melee swing bent the Soldier over at its midpoint. The swing became an overhead chop driven by the
arm raise and spine pitch.

## The kit gun hold is one-handed

In `Idle_Shoot` the right hand holds the weapon on `Index1.R` and the left arm hangs. Our clips keep that and leave the
left arm free for an IK target per weapon; the pistol stays one-handed.

## The exporter samples every bone; a clip that must not key some takes them out after

Leaving the fingers unkeyed in Blender is not enough: the glTF exporter (NLA tracks, forced sampling) writes a channel
for every bone of every clip, sampled at whatever the pose bone holds, and Godot kept 14 of those finger tracks (the
constant ones it drops are not all of them; `Repair_Board` carries 14 too). `build_soldier.py` now removes the
channels of the bones `soldier_clips.write(..., skip=...)` leaves out, straight from the .glb's JSON chunk
(`strip_channels`), and the downed and revive clips import with no finger track (#504).

## Lying and kneeling are posed in world space

Local Euler offsets were measured on the standing rig; on a body lying on its back the same axes point elsewhere. The
downed and revive poses turn bones about world axes (`turn`), move them in world metres (`move`, `place`) and solve
arms and legs onto world targets with a pole (`reach`; `legs` adds the kit leg shape of `gaitlib.leg_shape`). The
standing knee's own bend plane, which `gaitlib.solve_leg` keeps, bent a forward foot's knee backward into the ground
(-12 cm) until the knee got a pole. A probe that reads each part's lowest skin vertex (by its main vertex group)
caught both that and a toe 20 cm under the ground; the renders alone did not show them clearly.

## Chibi heads collide

The Soldier's head is about 40 % of his height. A reviver leaning over his hands to a downed teammate's chest put his
head in the teammate's face, in the game capture, not in Blender (one body there). Revive_Kneel is upright with the
arms reaching out and down, and the hands go on the belly.

## The sprint carry (#459)

- **Judge a carry from the game's camera.** The first two-handed carry, the gun low in front of the chest, looked
  right from the front and was invisible from behind: the body hid the whole gun, so the shoulder camera saw no swing
  at all. The muzzle now points across to his left and up, past the helmet, and the bat leans up and out over the
  right shoulder. `render_clips.py --view back` is the first look; the Godot tour is the proof.
- **The kit hold ties the gun to the forearm.** On `Index1.R` the grip sits 0.62 m out along the forearm and the
  barrel within 17 degrees of it, and the upper arm is only 0.39 m, so a grip target at the hip with a steep gun
  missed by 0.32 m: the carry is set by the upper arm's hang and the gun's direction, and the grip follows.
- **A melee weapon at the end of a hanging arm points at the legs.** Mirroring Run's free arm swung the bat like a
  pendulum, head down. A bent runner's arm with the forearm rolled to lean the shaft back keeps it up.
- **Locking two branches of a tree.** Godot 4.7 exposes every clip node's play position as
  `parameters/<path>/current_position` (and the last step as `current_delta`); seeking the carry there plus the step,
  every frame, keeps it on the Run's frame at any pace (measured within 0.002 s). See the kit's
  [AnimationTree page](https://github.com/Ryubara/gdstudio/blob/main/docs/godot/animation-tree.md).

## Godot headless

An `AnimationTree` built in a `SceneTree` script's `_init` does not process: `advance()` leaves the bones where they
were. Build it from a deferred call (`_run.call_deferred()`), once the root is running.

## Evidence

Contact sheets (four moments of each clip per class, the Body clips, and upper clips over Run and Walk) and the probe
sheet are attached to the pull request; `game/tests/art/check_soldier_clips.gd` prints the numbers above.
