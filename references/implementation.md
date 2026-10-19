# Implementation (Godot 4)

Copy `templates/godot/*.gd` into `res://paper_map/` and `templates/godot/shaders/` into
`res://paper_map/shaders/`. Compatibility renderer is enough; every shader is unshaded.

| file | does |
|---|---|
| `paper_region.gd` (`PaperRegion`) | loads a region file: places, roads (polylines), `terrain`; `connected()` |
| `paper_terrain.gd` (`PaperTerrain`) | builds the land: height grid (2 px step + 80 px rim), road/water mask, tree and scatter positions, blockers; `height_at`, `world`, `walkable`, `steep`, `mesh()` |
| `paper_house.gd` (`PaperHouse`) | a box building from houses.json: walls with the three drawings, gable roof with tile UVs, ink beams on the edges |
| `paper_map_view.gd` (`PaperMapView`) | the screen: SubViewport 3D world, cut-outs, houses, walker, camera, corner map, M map; WASD/Q/E/M/J; signals `near_changed`, `interact` |
| `shaders/terrain` | picks ground / meadow (noise patches) / road (mask) / cliff (slope) tiles, 3 light steps, fog in 6 flat steps |
| `shaders/card` | Y-axis billboard, hard alpha, wind sway (`sway` × height²), near-camera dissolve, see-through `hole` round the walker, fog |
| `shaders/house`, `outline` | building faces (3 light steps by facing) and the ink beams, both with the `hole` |
| `shaders/water`, `blob` | river surface with drifting ink ripples; the soft contact shadow |

## How the land is built (`PaperTerrain.build`)

1. Distance fields (per sheet pixel, capped) to roads+stairs and to the river, stamped segment by segment.
2. Raw height per sample: max over terraces (`smoothstep` over the noise-wobbled edge), the mountain slope, the
   river cut, a faint plain undulation, and the rim rising outside the sheet.
3. Two box blurs → `smooth`. Near a road, blend raw → smooth (full within ~9 px of the edge, fading by 32 px):
   roads become ramps. In the river only the road's width is raised (causeway).
4. `_defin` ×3: a sample higher than three neighbours by > 0.8 m drops to their mean (no fins).
5. Woods: staggered grid in each forest polygon and the rim, kept off roads and places. Dress then scatter in
   clumps on open flat ground. Blockers: building rectangles (behind `at`), solid cut-outs.

`walkable(p)`: inside the sheet, no height step > 0.6 m within 1.5 px, not in water unless on a road, not in a
forest polygon unless near a road, outside every blocker.

## The view

- **Camera**: focus = walker + 1.2 m, eased; position = focus + (sin yaw·cos pitch, sin pitch, cos yaw·cos
  pitch) × zoom. Q/E add ±45° to the target yaw (eased with `lerp_angle`).
- **Walking**: the stick is screen-relative; rotate by yaw into sheet space; try the step, then each axis alone
  (slide along walls). The nearest enterable place within 16 px is `near`.
- **Cut-outs** are unit quads with the origin at the foot, scaled to `tall` × aspect; the card shader turns them
  to the camera around Y. A blob shadow lies under each one on flat ground.
- **Name slips** are drawn in 2D over the viewport at `unproject_position` of the building's top.
- **Maps**: a second SubViewport shares the World3D with an orthographic camera high above, renders once with
  fog lifted on every material and the walker's layer culled; the image feeds the corner map (cropped round
  the walker) and the M map (scaled up, visited places named, click → `warp`).
- **Occlusion**: each frame write the walker's screen position and depth into every card/house material
  (`hole`); fragments nearer than him inside the radius are dithered away.

## Hooking into a game

```gdscript
var map := PaperMapView.new()
add_child(map)
map.near_changed.connect(func(p): hint.text = "" if p == "" else "J  Enter  " + map.region.places[p]["name"])
map.interact.connect(func(p): game.enter_place(p))
map.open("res://maps/valley.json", "gate")
```
The game keeps its own state (time of day, what is unlocked, where battles are) and draws extra markers by
projecting sheet points with the camera. Mark hidden places by leaving them out of `visited` and filtering.

## Tests worth having

- Walk 400 random directions: never ends on a non-walkable point.
- Walk into the mountain: height does not climb a cliff.
- Turn the camera 90°: "up" walks west.
- Stand by a place: `near` is it and interact fires; `warp` lands exactly on its point.
- Record footage with a scripted tour (hold keys, press Q/E, open the map, click a place) for review.
