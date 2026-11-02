"""A quick look at the drive-in props and the headliner before composing the title art.

blender -b --factory-startup -P preview_props.py -- --out <png>
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import keyart as K

argv = sys.argv[sys.argv.index("--") + 1 :]
out = Path(argv[argv.index("--out") + 1]).resolve()
K.reset()
K.ground(size=200, color="#5a5c66")
K.world_night(top="#30384f", horizon="#5a6488", strength=2.0)
x = -14.0
for name, w in (
    ("marquee", 6.2),
    ("ticket_booth", 2.6),
    ("concession_counter", 10.24),
    ("projector", 0.9),
    ("menu_board", 4.2),
    ("popcorn_machine", 0.74),
    ("speaker_post", 0.83),
):
    K.load_prop(f"drivein/{name}.gltf", (x + w / 2, 0, 0), 0.0, 1.0, name)
    x += w + 1.0
arm, _ = K.load_zombie("walker", "Idle", 0, location=(x + 1, 0, 0), yaw_deg=0.0)
before = set(bpy.data.actions)
objs = K.import_gltf(K.ASSETS / "characters/zombie_boss/zombie_boss.glb")
boss = next(o for o in objs if o.type == "ARMATURE")
K.take_actions(boss, before)
for o in [o for o in objs if o.type == "MESH" and "Far" in o.name]:
    bpy.data.objects.remove(o)
K.set_pose(boss, "Boss_Roar", 30)
K.place(boss, (x + 3.5, 0, 0), 0.0, K.ZOMBIE_SCALE)
print("ACTIONS", sorted(a.name for a in bpy.data.actions)[:80])
K.area_light("Key", (0, -20, 15), (0, 0, 1), K.hexrgb("#ffffff"), 40000, size=20)
c = K.camera((4.0, -30, 4.0), (4.0, 0, 2.5), lens=20)
K.cycles(samples=24, width=1920, height=720)
K.render(out)
