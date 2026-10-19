# Region data

One JSON file per region (`example_region.json` is complete). Coordinates are **sheet pixels** on a flat
top-down plan of `size` (e.g. 640×360); `PaperTerrain.M` = 0.25 m per pixel, so 640×360 is 160×90 m.

```json
{"id": "valley", "name": "Valley", "size": [640, 360], "start": "gate",
 "places": [{"id": "inn", "kind": "building", "name": "Inn", "at": [520, 222]}, ...],
 "roads":  [{"a": "gate", "b": "inn", "via": [[600, 175], [585, 222]]}, ...],
 "terrain": {...}}
```

- **places**: `id`, `kind`, `name`, `at` (where the player stands to go in — the door, not the building's
  middle). `kind` is the game's: the view treats kinds in `PaperMapView.enterable` as places you can enter;
  `fork` is a road junction with nothing to enter. Extra keys are the game's own.
- **roads**: `a` → `b` through `via` points. Roads are what the terrain flattens into ramps, and what the
  optional "click a place, walk there" uses. Every place should be reachable (`PaperRegion.connected()`).

## terrain

| key | what |
|---|---|
| `levels` | `[{h, poly}]` terraces: ground inside `poly` rises to `h` metres; the edge becomes a cliff |
| `mountain` | `{h, rise, top, poly}` a slope rising `rise` m per pixel inward from `h`, capped at `top` |
| `stairs` | `[[pts]]` lines treated like roads (flattened, drawn as road) without being routes |
| `river` | `{width, depth, line}` a channel cut along `line`; a road crossing it gets a causeway |
| `forests` | `[poly]` areas filled with trees on a staggered grid (kept clear of roads and places); not walkable away from roads |
| `pieces` | `[{sprite, at, for?}]` hand-placed things: a building (if the sprite is in houses.json) or a cut-out; `for` = the place it stands for (its name slip hangs over it). A building's `at` is the middle of its front wall's foot |
| `scatter` | `{sprite: count}` strewn over open ground in small clumps (not on roads, slopes, water, woods); a sprite named `reeds` only grows by the river |
| `solid` | `{sprite: radius}` cut-outs the walker cannot pass (trees, rocks, wells…), radius in sheet pixels |
| `dress` | `{building sprite: [sprites]}` small props set beside each such building (not in front of its door) |

A margin of 80 px all round is added automatically: a rising wooded rim, so the edge of the world never shows.

## houses.json

```json
{"inn": {"w": 9.0, "d": 6.0, "h": 7.3, "rise": 2.2, "roof": "tile"}}
```
Box width (x), depth (z), wall height, roof rise above the eaves (metres), and the roof tile name
(`art/roof_<roof>.png`). Walls are `art/house_<name>_front|side|back.png`. A building with no wall drawings
falls back to its flat cut-out.

## kinds.json

`example_kinds.json`: per cut-out sprite its height in metres (`tall`) and wind sway (`sway`, metres at the
top), the mix of trees for the woods (`woods`), and the walker strip (`walker`: png, frames per direction,
height). The walker strip is one row: down, up, left, right, `frames` each, first frame standing.

## Sizes that worked

Buildings 6–9 m wide, walls 3.5–7 m, roof rise 2–3 m; trees 5–7 m; grass 0.9 m; walker 4.2 m; camera 30 m
away at 38° pitch, FOV 40°; terraces 3.5–8.5 m high; fog 30 → 80 m in six flat steps.
