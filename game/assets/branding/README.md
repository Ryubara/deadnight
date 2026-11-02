# Branding

The app icon ("Marquee ring") and the key art ("Back to back"), picked by the maintainer from six rendered
variations (issue #434).

All of it was rendered in Blender (Cycles) from the game's own models only: the Soldier and Greaser from
`assets/characters/soldier_parts/`, the zombies from `assets/characters/zombies/`, the double shotgun and lever rifle
from `assets/weapons/`, and the cars, street lights, screen frame and speaker posts from `assets/props/` and
`assets/drivein/`. The fence, screen face, projection booth, flare and bulb ring were modelled in the render scene.
No third-party asset is used.

| File | Use |
| --- | --- |
| `icon.png` (256) | `application/config/icon`: the window icon, and the web export's favicon and apple-touch icon |
| `icon.ico` (256, 128, 64, 48, 32, 16) | `application/config/windows_native_icon` |
| `keyart_1920x1080.png` | `application/boot_splash/image`, also the web shell's loading image |
| `source/icon_*.png` | the 1024 master and 512, 192, 180, 128, 64, 48, 32, 16 for store pages and other platforms |
| `source/keyart_3840x2160.png` | the 4K key art for store pages and press |

`source/` has a `.gdignore`, so Godot neither imports those files nor puts them in an export.
