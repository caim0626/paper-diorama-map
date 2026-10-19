---
name: paper-diorama-map
description: Design and build a walkable 2.5D "paper diorama" region map for a game — real-time 3D heightmap terrain (terraces, cliffs, river, wooded rim) textured with a few small tiles, flat pixel-art cut-outs that always face the camera, paper-box buildings with painted elevations and thick outlines, free WASD walking with collision, Q/E camera turning, a corner minimap and an M map with click-to-travel. Covers the whole pipeline from layout sketch to region data, generated assets, Godot 4 implementation and footage-based acceptance. Use when someone wants an overworld / region / town map in this style (PokéBonk-like terrain + billboard sprites), wants to turn a painted map into an explorable one, or asks how to generate assets for such a map. Not for battle maps or first-person scenes.
---

# Paper diorama map

A region map that looks hand-drawn but is a real 3D space: the player walks anywhere the land allows and the
camera can go round buildings. It is cheap to make because the art is **parts, not pictures**: three or four
tiling ground textures, one sheet of nature props, one sheet of village props, and per building three wall
drawings. Everything else — where things stand, how the ground rises, where roads run — is data and code.

Godot 4 templates are in `templates/godot/` (tested on 4.6, Compatibility renderer), the asset slicer in
`scripts/slice_assets.py`, a complete example region in `references/`.

## Decide first

- **Don't generate "what it would look like" screenshots.** An image model paints an illustration, never a
  render: it adds detail everywhere, invents layout, and cannot show what this technique produces. Go straight
  to generating parts and look at the real engine.
- **The layout is data you own.** Places and roads come from a top-down sketch; the land is built so every road
  is walkable. Changing the map means editing JSON, not regenerating art.
- **One look for everything:** chunky pixel art, a bold even near-black outline on every sprite and building,
  flat 2–3 step shading, light from one side. Ground textures stay quiet so sprites read on them.

## The pipeline

1. **Sketch** (top-down, north up) — every place the player can enter, the roads between them, terrace edges,
   the river, the woods. Draw only places that can be visited; scenery fills the edges, the middle stays open.
2. **Region data** — `references/data-format.md`. Places + roads + `terrain` (levels, mountain, stairs, river,
   forests, pieces, scatter, solid, dress). Check: every place reachable, every piece on or beside a road.
3. **Asset list** — from the data: which tiles, which props (woods, scatter, dress), which buildings (box
   models) vs. which landmarks stay flat cut-outs (gates, piers, bridges, camps: things with no clear "walls").
4. **Generate assets** — `references/asset-prompts.md`. Tiles (seamless), prop grids (transparent),
   building elevation sheets (front / gable end / back, from the building's sprite as reference), roof tiles.
   Then `python scripts/slice_assets.py manifest.json` cuts them into game files.
5. **Implement** — copy `templates/godot/` into `res://paper_map/` (scripts + `shaders/`), put the art in
   `res://paper_map/art/`, write `kinds.json` (sprite heights, sway, wood mix, walker strip) and `houses.json`
   (building box sizes). Add a `PaperMapView`, call `open("res://.../region.json")`, connect `near_changed`
   and `interact` to your game. See `references/implementation.md`.
6. **Accept on footage** — record a walk (each region, turned camera, map open + travel), extract a frame a
   second, and have someone who has not seen the work judge: can you tell where you are and where to go, do
   buildings read as solid from every side, is the land pleasant, is the walker readable, any glitches. Fix the
   concrete items, re-record. A unit test covers walking (never inside anything, cliffs stop you, the camera
   turns the walk, near a place → interact works, map travel lands there).

## Rules that saved time

- Each generation prompt is written fresh from a format guide + only this job's inputs (what each reference
  image controls, what is in the picture). Old prompts pasted in carry old mistakes forward.
- Prompts describe what *is* there (no "no …" lists), name a professional role and use trade terms.
- First try plus at most two redos per asset; if it is still wrong, the prompt is unclear — fix the prompt.
- Ask for density in the brief ("two-thirds open ground", "small, re-used") or the model fills every inch.
- References pass their faults on: a prop sheet with flowers at every foot gives flowers everywhere.

## Pitfalls (each cost a round)

- **Cliff fins**: road smoothing leaves one-sample slivers of high ground → flatten samples higher than ≥3
  neighbours (`_defin`), and smooth a wide shoulder (full strength out to ~9 px past the road edge).
- **River vs. roads**: never smooth the river bed toward a road; give only the road's own width a causeway.
- **Stepped plateau edges**: wobble the terrace outline with low-frequency noise (≈0.06 /px, ±5 px) and blend
  over ±3 px; high-frequency wobble reads as torn paper.
- **Ground patches**: a soft-edged noise blend of a meadow tile reads as dirty smudges; use a narrow threshold.
- **Building outlines**: inflated inside-out hulls draw a black slab under the eaves; draw square ink beams
  along eaves, verges, ridge, corners and feet instead.
- **Elevation sheets come with roof bands** drawn over long walls; cut them (roof-colour rows, dark tile rows,
  rows wider than the wall below) or the box gets two roofs.
- **Godot winding**: front faces are clockwise; counter-clockwise walls are culled from outside.
- **Camera before first input**: position the camera when the map opens, or screen↔map conversion in the first
  frame uses the origin.
- **Map snapshot**: lift the fog on *every* material (ground, water, houses, cut-outs) for the one frame, and
  cull the walker with a render layer.
- **Occlusion**: dither a round window in front of the walker on cut-outs *and* buildings.
- **Walker scale**: on a 30 m camera distance a 2 m figure is a speck; ~4 m reads (it is a paper figure).
